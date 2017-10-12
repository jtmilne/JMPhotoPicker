//
//    Copyright (c) 2016 Joel Milne
//
//    Permission is hereby granted, free of charge, to any person obtaining a copy of
//    this software and associated documentation files (the "Software"), to deal in
//    the Software without restriction, including without limitation the rights to
//    use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of
//    the Software, and to permit persons to whom the Software is furnished to do so,
//    subject to the following conditions:
//
//    The above copyright notice and this permission notice shall be included in all
//    copies or substantial portions of the Software.
//
//    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//    IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS
//    FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR
//    COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER
//    IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
//    CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.


#import "JMPPDataSourceFacebook.h"
#import "SDWebImageManager.h"
#import "JMPPUtils.h"
#import "JMPPAlbum.h"
#import "JMPPStrings.h"
#import "JMPPError.h"
#import <FBSDKLoginKit/FBSDKLoginKit.h>
#import <FBSDKCoreKit/FBSDKAccessToken.h>
#import <FBSDKCoreKit/FBSDKGraphRequest.h>

#define kFacebookPermissions    @[@"user_photos"]
#define kPhotosPerRequest       @"100"

@interface JMPPDataSourceFacebook()

- (BOOL)checkPermissions;
- (void)loadPhotoDataForAlbum:(JMPPAlbum *)album andIndex:(NSUInteger)index withSuccess:(JMPPSuccess)success andFailure:(JMPPFailure)failure;
- (NSDictionary *)findBestImageFromImages:(NSArray *)arrayImages withMinPixels:(NSUInteger)minPixels;

@end

@implementation JMPPDataSourceFacebook

////////////////////////////////////////////////////////////////
#pragma mark JMPhotoPickerDataSource Delegate Methods
////////////////////////////////////////////////////////////////

- (BOOL)checkPermissions
{
    for (NSString *permission in kFacebookPermissions) {
        if (![[FBSDKAccessToken currentAccessToken] hasGranted:permission]) return NO;
    }
    return YES;
}

- (void)requestAccessWithSuccess:(JMPPSuccess)success andFailure:(JMPPFailure)failure
{
    NSAssert(self.delegate, @"JMPPDataSourceFacebook::requestAccessWithSuccess - delegate view controller not set.");

    //is user already logged in?
    if ([FBSDKAccessToken currentAccessToken] && [[FBSDKAccessToken currentAccessToken] hasGranted:@"user_photos"]) {
        
        [JMPPUtils logDebug:@"JMPPDataSourceFacebook::requestAccessWithSuccess - Facebook access previously granted."];
        if (success) success(nil);
        return;
        
    }
    
    //use the login manager
    FBSDKLoginManager *fbLoginManager = [FBSDKLoginManager new];
    [fbLoginManager setLoginBehavior:FBSDKLoginBehaviorNative];
    [fbLoginManager logInWithReadPermissions:kFacebookPermissions fromViewController:self.delegate handler:^(FBSDKLoginManagerLoginResult *result, NSError *error) {
        
        //check for an error
        if (error) {
            [JMPPUtils logDebug:@"JMPPDataSourceFacebook::requestAccessWithSuccess - Error logging in with Facebook account: %@", [error localizedDescription]];
            if (failure) failure(error);
            return;
        }
        
        if (result.isCancelled) {
            [JMPPUtils logDebug:@"JMPPDataSourceFacebook::requestAccessWithSuccess - User canceled Facebook login"];
            if (failure) failure([JMPPError errorUserCanceled]);
            return;
        }
        
        if (![self checkPermissions]) {
            [JMPPUtils logDebug:@"JMPPDataSourceFacebook::requestAccessWithSuccess - User denied permissions."];
            if (failure) failure([JMPPError createErrorWithString:kErrMsgFBDenied]);
            return;
        }
        
        [JMPPUtils logDebug:@"JMPPDataSourceFacebook::requestAccessWithSuccess - Facebook access granted."];
        if (success) success(nil);
        
    }];
}

- (void)loadAlbumsWithSuccess:(JMPPSuccess)success andFailure:(JMPPFailure)failure
{
    //confirm access
    if (![FBSDKAccessToken currentAccessToken]) {
        
        [self requestAccessWithSuccess:^(id result) {
            [self loadAlbumsWithSuccess:success andFailure:failure];
        } andFailure:^(NSError *error) {
            if (failure) failure(error);
        }];
        return;
        
    }
    
    //Make graph request for me to get the id and other user info
    NSDictionary *params = @{@"limit":@"100", @"fields":@"id,name,count"};
    FBSDKGraphRequest *request = [[FBSDKGraphRequest alloc] initWithGraphPath:@"me/albums" parameters:params];
    [request startWithCompletionHandler:^(FBSDKGraphRequestConnection *connection, id result, NSError *error) {
        
        if (error) {
            [JMPPUtils logDebug:@"JMPPDataSourceFacebook::loadAlbumsWithSuccess - Error accessing Facebook albums: %@", error.localizedDescription];
            if (failure) failure(error);
            return;
        }
        
        NSArray *arrayData = result[@"data"];
        if (!arrayData || ![arrayData isKindOfClass:[NSArray class]]) {
            if (failure) failure([JMPPError createErrorWithString:kErrMsgFBData]);
            return;
        }
        
        NSMutableArray *arrayAlbums = [NSMutableArray array];
        for (NSDictionary *dictAlbum in arrayData) {
            
            if ([dictAlbum[@"count"] intValue] > 0) {
                
                JMPPAlbum *albumNew = [JMPPAlbum new];
                [albumNew setIdentifier:dictAlbum[@"id"]];
                [albumNew setName:dictAlbum[@"name"]];
                [albumNew setCount:[dictAlbum[@"count"] unsignedIntegerValue]];
                
                if ([albumNew.name isEqualToString:@"Profile Pictures"]) [arrayAlbums insertObject:albumNew atIndex:0];
                else [arrayAlbums addObject:albumNew];
                
            }
            
        }
        
        //return the albums
        if (success) success(arrayAlbums);
        
        //load the first page of photo metadata for each album in the background
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{
            for (JMPPAlbum *albumIterate in arrayAlbums) {
                [self loadPhotoFromAlbum:albumIterate withIndex:0 andMinPixels:0 andSuccess:nil andFailure:nil];
            }
        });
    
    }];
}

- (void)loadCoverPhotoForAlbum:(JMPPAlbum *)album withMinPixels:(NSUInteger)minPixels andSuccess:(JMPPSuccess)success andFailure:(JMPPFailure)failure
{
    NSAssert([FBSDKAccessToken currentAccessToken], @"JMPPDataSourceFacebook::loadCoverPhotoForAlbum - Missing Facebook access token.");

    //load the photo using SDWebImageManager for caching
    NSString *strType = ([UIScreen mainScreen].scale > 1.0) ? @"album" : @"small";
    NSString *strUrl = [NSString stringWithFormat:@"https://graph.facebook.com/%@/picture?type=%@&access_token=%@", album.identifier, strType, [FBSDKAccessToken currentAccessToken].tokenString];
    
    SDWebImageOptions options = (SDWebImageRetryFailed | SDWebImageContinueInBackground);
    [[SDWebImageManager sharedManager] downloadImageWithURL:[NSURL URLWithString:strUrl] options:options progress:nil completed:^(UIImage *image, NSError *error, SDImageCacheType cacheType, BOOL finished, NSURL *imageURL) {
        
        if (error) {
            [JMPPUtils logDebug:@"JMPPDataSourceFacebook::loadCoverPhotoForAlbum - Error loading Facebook album cover: %@", error.localizedDescription];
            if (failure) failure(error);
            return;
        }
        
        if (!image) {
            [JMPPUtils logDebug:@"JMPPDataSourceFacebook::loadCoverPhotoForAlbum - Invalid image received from Facebook Graph"];
            if (failure) failure([JMPPError createErrorWithString:kErrMsgFBPhoto]);
            return;
        }
        
        if (success) success(image);
        
    }];
}

- (void)loadPhotoFromAlbum:(JMPPAlbum *)album withIndex:(NSUInteger)index andMinPixels:(NSUInteger)minPixels andSuccess:(JMPPSuccess)success andFailure:(JMPPFailure)failure
{
    NSAssert([FBSDKAccessToken currentAccessToken], @"JMPPDataSourceFacebook::loadPhotoFromAlbum - Missing Facebook access token.");
    
    //get the meta data for this photo
    [self loadPhotoDataForAlbum:album andIndex:index withSuccess:^(NSDictionary *dictPhoto) {
        
        //don't bother loading the image if there is no success block to return it
        if (success) {
            
            //get the images for this photo (each photo has multiple images available from FB)
            NSArray *arrayImages = dictPhoto[@"images"];
            NSDictionary *dictImage = [self findBestImageFromImages:arrayImages withMinPixels:minPixels];
            NSString *strUrl = dictImage[@"source"];
            
            SDWebImageOptions options = (SDWebImageRetryFailed | SDWebImageContinueInBackground);
            [[SDWebImageManager sharedManager] downloadImageWithURL:[NSURL URLWithString:strUrl] options:options progress:nil completed:^(UIImage *image, NSError *error, SDImageCacheType cacheType, BOOL finished, NSURL *imageURL) {
                
                if (error) {
                    [JMPPUtils logDebug:@"JMPPDataSourceFacebook::loadPhotoFromAlbum - Error loading Facebook photo: %@", error.localizedDescription];
                    if (failure) failure(error);
                    return;
                }
                
                if (!image) {
                    [JMPPUtils logDebug:@"JMPPDataSourceFacebook::loadPhotoFromAlbum - Invalid photo received from Facebook Graph"];
                    if (failure) failure([JMPPError createErrorWithString:kErrMsgFBPhoto]);
                    return;
                }
                
                success(image);
                
            }];
            
        }
        
    } andFailure:^(NSError *error) {
        
        if (failure) failure(error);
        
    }];
}

////////////////////////////////////////////////////////////////
#pragma mark Private Methods
////////////////////////////////////////////////////////////////

- (void)loadPhotoDataForAlbum:(JMPPAlbum *)album andIndex:(NSUInteger)index withSuccess:(JMPPSuccess)success andFailure:(JMPPFailure)failure
{
    NSAssert(!album.photos || album.nextPhotos || [(NSArray *)album.photos count] == album.count, @"JMPPDataSourceFacebook::loadPhotoDataForAlbum - No photos to load.");
    
    //load in a serial queue per album (to avoid concurrency issues when multiple cells request loads simultaneously)
    dispatch_async(album.queueLoadPhotos, ^{
        
        //has the meta data for this photo been loaded already?
        if (album.photos && index < [(NSArray *)album.photos count]) {
            if (success) success(album.photos[index]);
            return;
        }
        
        //create a request
        FBSDKGraphRequest *requestPhotos;
        if (album.nextPhotos) {

            requestPhotos = [[FBSDKGraphRequest alloc] initWithGraphPath:album.nextPhotos parameters:nil];
            
        } else if (!album.photos) {
            
            NSDictionary *params = @{@"limit":kPhotosPerRequest, @"fields":@"id,images"};
            NSString *strPath = [NSString stringWithFormat:@"%@/photos", album.identifier];
            requestPhotos = [[FBSDKGraphRequest alloc] initWithGraphPath:strPath parameters:params];
            
        }
        
        //make the request synchronous with a semaphore
        __block NSError *requestError;
        dispatch_semaphore_t semaBlock = dispatch_semaphore_create(0);
        
        //execute the request
        [requestPhotos startWithCompletionHandler:^(FBSDKGraphRequestConnection *connection, id result, NSError *error) {
            
            if (error) {
                [JMPPUtils logDebug:@"JMPPDataSourceFacebook::loadPhotosForAlbum - Error loading Facebook photos from album: %@", error.localizedDescription];
                requestError = error;
                dispatch_semaphore_signal(semaBlock);
                return;
            }
            
            //check for error
            if (result[@"error"]) {
                [JMPPUtils logDebug:@"JMPPDataSourceFacebook::loadPhotosForAlbum - Error returned from  Facebook: %@", result[@"error"][@"message"]];
                requestError = [JMPPError createErrorWithString:result[@"error"][@"message"]];
                dispatch_semaphore_signal(semaBlock);
                return;
            }
            
            //get the array
            NSMutableArray *arrayPhotos = [NSMutableArray arrayWithArray:result[@"data"]];
            if (!arrayPhotos || ![arrayPhotos isKindOfClass:[NSArray class]]) {
                [JMPPUtils logDebug:@"JMPPDataSourceFacebook::loadPhotosForAlbum - Error decoding Facebook response"];
                requestError = [JMPPError createErrorWithString:kErrMsgFBData];
                dispatch_semaphore_signal(semaBlock);
                return;
            }
            
            //add the photos to the dictionary
            if (!album.photos) [album setPhotos:arrayPhotos];
            else [album setPhotos:[album.photos arrayByAddingObjectsFromArray:arrayPhotos]];
            if (result[@"paging"][@"next"]) [album setNextPhotos:result[@"paging"][@"next"]];
            else [album setNextPhotos:nil];
            
            //make sure we haven't added too many photos - multithreading check
            if ([(NSArray *)album.photos count] > album.count) {
                [JMPPUtils logDebug:@"JMPPDataSourceFacebook::loadPhotosForAlbum - Warning: loaded more photos than the album contains. This is a problem unless more photos were added to the album since we got the metadata."];
            }
            
            //done
            dispatch_semaphore_signal(semaBlock);
            
        }];
        
        //wait for the request to complete
        dispatch_semaphore_wait(semaBlock, DISPATCH_TIME_FOREVER);
        
        //return any errors
        if (requestError) {
            if (failure) failure(requestError);
            return;
        }
        
        //do we have the meta data for this photo yet?
        if (index >= [(NSArray *)album.photos count]) {
            [self loadPhotoDataForAlbum:album andIndex:index withSuccess:success andFailure:failure]; //recurse
            return;
        }
        
        //got it!
        if (success) success(album.photos[index]);

    });
}

- (NSDictionary *)findBestImageFromImages:(NSArray *)arrayImages withMinPixels:(NSUInteger)minPixels
{
    NSAssert(arrayImages.count > 0, @"JMPPDataSourceFacebook::findBestImageFromImages - No images in array");
    
    NSUInteger index = 0;
    
    for (int i=1; i< arrayImages.count; i++) {
        
        NSDictionary *dictImageCurrent = arrayImages[index];
        NSDictionary *dictImageToCompare = arrayImages[i];
        
        if (!dictImageCurrent || !dictImageToCompare || !dictImageCurrent[@"height"] || !dictImageToCompare[@"height"] || !dictImageCurrent[@"width"] || !dictImageToCompare[@"width"]) {
            [JMPPUtils logDebug:@"JMPPDataSourceFacebook::findBestImageFromImages - Invalid data."];
            return arrayImages[0]; //data fail so just load the first one
        }
        
        NSUInteger sizeCurrent = MIN([dictImageCurrent[@"height"] integerValue], [dictImageCurrent[@"width"] integerValue]);
        NSUInteger sizeToCompare = MIN([dictImageToCompare[@"height"] integerValue], [dictImageToCompare[@"width"] integerValue]);
        
        if (sizeCurrent < minPixels) {
            
            if (sizeToCompare > sizeCurrent) index = i;
            
        } else {
            
            if (sizeToCompare < sizeCurrent && sizeToCompare > minPixels) index = i;
            
        }
        
    }
    
    return arrayImages[index];
}


@end
