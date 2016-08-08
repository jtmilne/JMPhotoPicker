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
#import <Accounts/Accounts.h>
#import <Social/Social.h>
#import "SDWebImageManager.h"
#import "JMPPUtils.h"
#import "JMPPAlbum.h"
#import "JMPPStrings.h"
#import "JMPPError.h"

#define kPhotosPerRequest       @"100"

@interface JMPPDataSourceFacebook()

@property (nonatomic, strong) ACAccountStore *accountStore;
@property (nonatomic, strong) ACAccount *accountFacebook;

- (void)loadPhotoDataForAlbum:(JMPPAlbum *)album andIndex:(NSUInteger)index withSuccess:(JMPPSuccess)success andFailure:(JMPPFailure)failure;
- (NSDictionary *)findBestImageFromImages:(NSArray *)arrayImages withMinPixels:(NSUInteger)minPixels;

@end

@implementation JMPPDataSourceFacebook

////////////////////////////////////////////////////////////////
#pragma mark JMPhotoPickerDataSource Delegate Methods
////////////////////////////////////////////////////////////////

- (void)requestAccessWithSuccess:(JMPPSuccess)success andFailure:(JMPPFailure)failure
{
    NSAssert(self.facebookId, @"JMPhotoPicker not properly initialized. Missing Facebook App Id.");

    if (![SLComposeViewController isAvailableForServiceType:ACAccountTypeIdentifierFacebook]) {
        if (failure) failure([JMPPError createErrorWithString:kErrMsgFBNoAccount]);
        return;
    }
    
    NSDictionary *options = @{
                              ACFacebookAppIdKey : self.facebookId,
                              ACFacebookPermissionsKey : @[@"user_photos"]
                              };
    
    //request access
    [self setAccountStore:[[ACAccountStore alloc] init]];
    ACAccountType *accountType = [self.accountStore accountTypeWithAccountTypeIdentifier:ACAccountTypeIdentifierFacebook];
    [self.accountStore requestAccessToAccountsWithType:accountType options:options completion:^(BOOL granted, NSError *error){
        
        //check for an error
        if (error) {
            
            //handle errors gracefully
            NSString *errorMsg = nil;
            if ([[error domain] isEqualToString:ACErrorDomain]) {
                
                // The following error codes and descriptions are found in ACError.h
                switch ([error code]) {
                    case ACErrorAccountNotFound:;
                        errorMsg = kErrMsgFBNoAccount;
                        break;
                    case ACErrorPermissionDenied:;
                        errorMsg = kErrMsgFBDenied;
                        break;
                    case ACErrorUnknown:
                    default:;
                        errorMsg = [error localizedDescription];
                        break;
                }
            } else {
                // handle other error domains
                errorMsg = [error localizedDescription];
            }
            
            [JMPPUtils logDebug:@"JMPPDataSourceFacebook::requestAccessWithSuccess - Error logging in with Facebook account: %@", errorMsg];
            if (failure) failure([JMPPError createErrorWithString:errorMsg]);
            return;
        }
        
        //check if access was granted
        if (!granted) {
            [JMPPUtils logDebug:@"JMPPDataSourceFacebook::requestAccessWithSuccess - Facebook account access denied."];
            if (failure) failure([JMPPError createErrorWithString:kErrMsgFBDenied]);
            return;
        }
        
        // Check if the users has setup at least one account of this type
        NSArray *accounts = [self.accountStore accountsWithAccountType:accountType];
        if (accounts.count < 1) {
            [JMPPUtils logDebug:@"JMPPDataSourceFacebook::requestAccessWithSuccess - Access granted, but no Facebook account found. Should not happen."];
            if (failure) failure([JMPPError createErrorWithString:kErrMsgFBNoAccount]);
            return;
        }
        
        //save the account for future acccess
        [self setAccountFacebook:[accounts lastObject]];
        
        //make sure there is an access token
        if (self.accountFacebook.credential.oauthToken) {
            
            [JMPPUtils logDebug:@"JMPPDataSourceFacebook::requestAccessWithSuccess - Facebook access granted."];
            success(nil);
            return;

        }
        
        //try and renew the credential
        [self.accountStore renewCredentialsForAccount:self.accountFacebook completion:^(ACAccountCredentialRenewResult renewResult, NSError *error) {
            
            if (error) {
                
                [JMPPUtils logDebug:@"JMPPDataSourceFacebook::requestAccessWithSuccess - Error renewing credential: %@", error.localizedDescription];
                if (failure) failure(error);
                
            } else if (renewResult != ACAccountCredentialRenewResultRenewed) {
                
                [JMPPUtils logDebug:@"JMPPDataSourceFacebook::requestAccessWithSuccess - App is no longer authorized."];
                if (failure) failure([JMPPError createErrorWithString:kErrMsgFBExpired]);
                
            } else {
                
                [JMPPUtils logDebug:@"JMPPDataSourceFacebook::requestAccessWithSuccess - Facebook access granted."];
                if (success) success(nil);
                
            }
            
        }];
        
    }];
}

- (void)loadAlbumsWithSuccess:(JMPPSuccess)success andFailure:(JMPPFailure)failure
{
    //confirm access
    if (!self.accountFacebook) {
        
        [self requestAccessWithSuccess:^(id result) {
            [self loadAlbumsWithSuccess:success andFailure:failure];
        } andFailure:^(NSError *error) {
            if (failure) failure(error);
        }];
        return;
        
    }
    
    NSURL *urlAlbums = [NSURL URLWithString:@"https://graph.facebook.com/me/albums"];
    NSDictionary *params = @{@"limit":@"100", @"fields":@"id,name,count"};
    SLRequest *requestMe = [SLRequest requestForServiceType:SLServiceTypeFacebook requestMethod:SLRequestMethodGET URL:urlAlbums parameters:params];
    requestMe.account = self.accountFacebook;
    
    [requestMe performRequestWithHandler:^(NSData *responseData, NSHTTPURLResponse *urlResponse, NSError *error) {
        
        if (error) {
            [JMPPUtils logDebug:@"JMPPDataSourceFacebook::loadAlbumsWithSuccess - Error accessing Facebook albums: %@", error.localizedDescription];
            if (failure) failure(error);
            return;
        }
        
        NSError *jsonError = nil;
        NSDictionary *dictResponse = [NSJSONSerialization JSONObjectWithData:responseData options:0 error:&jsonError];
        NSArray *arrayData = dictResponse[@"data"];
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
    NSAssert(self.accountFacebook, @"JMPPDataSourceFacebook::loadCoverPhotoForAlbum - Missing Facebook account.");

    //load the photo using SDWebImageManager for caching
    NSString *strType = ([UIScreen mainScreen].scale > 1.0) ? @"album" : @"small";
    NSString *strUrl = [NSString stringWithFormat:@"https://graph.facebook.com/%@/picture?type=%@&access_token=%@", album.identifier, strType, self.accountFacebook.credential.oauthToken];
    
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
    NSAssert(self.accountFacebook, @"JMPPDataSourceFacebook::loadPhotoFromAlbum - Missing Facebook account.");
    
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
        SLRequest *requestPhotos;
        if (album.nextPhotos) {
            
            requestPhotos = [SLRequest requestForServiceType:SLServiceTypeFacebook requestMethod:SLRequestMethodGET URL:[NSURL URLWithString:album.nextPhotos] parameters:nil];
            
        } else if (!album.photos) {
            
            NSDictionary *params = @{@"limit":kPhotosPerRequest, @"fields":@"id,images"};
            NSString *strUrl = [NSString stringWithFormat:@"https://graph.facebook.com/%@/photos", album.identifier];
            requestPhotos = [SLRequest requestForServiceType:SLServiceTypeFacebook requestMethod:SLRequestMethodGET URL:[NSURL URLWithString:strUrl] parameters:params];
            requestPhotos.account = self.accountFacebook;
            
        }
        
        //make the request synchronous with a semaphore
        __block NSError *requestError;
        dispatch_semaphore_t semaBlock = dispatch_semaphore_create(0);
        
        //execute the request
        [requestPhotos performRequestWithHandler:^(NSData *responseData, NSHTTPURLResponse *urlResponse, NSError *error) {
            
            if (error) {
                [JMPPUtils logDebug:@"JMPPDataSourceFacebook::loadPhotosForAlbum - Error loading Facebook photos from album: %@", error.localizedDescription];
                requestError = error;
                dispatch_semaphore_signal(semaBlock);
                return;
            }
            
            //decode the response
            NSError *jsonError = nil;
            NSDictionary *dictResponse = [NSJSONSerialization JSONObjectWithData:responseData options:0 error:&jsonError];
            if (jsonError || !dictResponse || ![dictResponse isKindOfClass:[NSDictionary class]]) {
                [JMPPUtils logDebug:@"JMPPDataSourceFacebook::loadPhotosForAlbum - Error decoding Facebook response: %@", (jsonError) ? jsonError.localizedDescription : @"Invalid dictionary"];
                requestError = [JMPPError createErrorWithString:kErrMsgFBData];
                dispatch_semaphore_signal(semaBlock);
                return;
            }
            
            //check for error
            if (dictResponse[@"error"]) {
                [JMPPUtils logDebug:@"JMPPDataSourceFacebook::loadPhotosForAlbum - Error returned from  Facebook: %@", dictResponse[@"error"][@"message"]];
                requestError = [JMPPError createErrorWithString:dictResponse[@"error"][@"message"]];
                dispatch_semaphore_signal(semaBlock);
                return;
            }
            
            //get the array
            NSMutableArray *arrayPhotos = [NSMutableArray arrayWithArray:dictResponse[@"data"]];
            if (!arrayPhotos || ![arrayPhotos isKindOfClass:[NSArray class]]) {
                [JMPPUtils logDebug:@"JMPPDataSourceFacebook::loadPhotosForAlbum - Error decoding Facebook response"];
                requestError = [JMPPError createErrorWithString:kErrMsgFBData];
                dispatch_semaphore_signal(semaBlock);
                return;
            }
            
            //add the photos to the dictionary
            if (!album.photos) [album setPhotos:arrayPhotos];
            else [album setPhotos:[album.photos arrayByAddingObjectsFromArray:arrayPhotos]];
            if (dictResponse[@"paging"][@"next"]) [album setNextPhotos:dictResponse[@"paging"][@"next"]];
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
