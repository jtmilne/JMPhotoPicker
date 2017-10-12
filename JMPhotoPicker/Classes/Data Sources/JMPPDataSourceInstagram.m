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


#import "JMPPDataSourceInstagram.h"
#import <UIKit/UIImage.h>
#import "SDWebImageManager.h"
#import "JMPPAlbum.h"
#import "JMPPUtils.h"
#import "JMPPStrings.h"
#import "JMPPError.h"

#define kInstagramAuthUrl           @"https://api.instagram.com/oauth/authorize/"
#define kInstagramApiUrl            @"https://api.instagram.com/v1/"
#define kInstagramCookieUrl         @"https://www.instagram.com/"
#define kInstagramUserSelf          @"users/self"
#define kInstagramUserMedia         @"users/self/media/recent"
#define kPhotosPerRequest           @"20"
#define kTokenString                @"jmpp_token"

@interface JMPPDataSourceInstagram() <UIWebViewDelegate>

@property (nonatomic, copy) NSString *accessToken;
@property (nonatomic, strong) UIView *viewLogin;
@property (nonatomic, strong) UIWebView *webViewLogin;
@property (nonatomic, copy) JMPPSuccess authSuccess;
@property (nonatomic, copy) JMPPFailure authFailure;

- (void)handleAuthComplete:(NSString *)accessToken;
- (void)handleAuthError:(NSError *)error;
- (void)loadPhotoDataForAlbum:(JMPPAlbum *)album andIndex:(NSUInteger)index withSuccess:(JMPPSuccess)success andFailure:(JMPPFailure)failure;
- (NSDictionary *)findBestImageFromImages:(NSDictionary *)dictImages withMinPixels:(NSUInteger)minPixels;

- (void)showLoginView;
- (void)hideLoginView;
- (void)actionCancelLogin;

@end

@implementation JMPPDataSourceInstagram

////////////////////////////////////////////////////////////////
#pragma mark JMPhotoPickerDataSource Delegate Methods
////////////////////////////////////////////////////////////////

- (void)requestAccessWithSuccess:(JMPPSuccess)success andFailure:(JMPPFailure)failure
{
    NSAssert(self.instagramId && (self.instagramId.length > 1), @"JMPhotoPicker not properly initialized. Missing Instagram Client Id.");
    
    if (self.accessToken) {
        if (success) success(nil);
        return;
    }

    //check for a saved access token
    NSString *token = [[NSUserDefaults standardUserDefaults] stringForKey:kTokenString];
    if (token) {
        
        //create a request to verify the token
        NSString *urlString = [NSString stringWithFormat:@"%@%@", kInstagramApiUrl, kInstagramUserSelf];
        NSURLComponents *components = [NSURLComponents componentsWithString:urlString];
        NSURLQueryItem *queryToken = [NSURLQueryItem queryItemWithName:@"access_token" value:token];
        components.queryItems = @[queryToken];
        NSURLRequest *request = [NSURLRequest requestWithURL:components.URL];
        
        //execute request
        [[[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
            
            if (error) {
                [JMPPUtils logDebug:@"JMPPDataSourceInstagram::requestAccessWithSuccess - Error verifying access token: %@", error.localizedDescription];
                [[NSUserDefaults standardUserDefaults] removeObjectForKey:kTokenString];
                [[NSUserDefaults standardUserDefaults] synchronize];
                [self requestAccessWithSuccess:success andFailure:failure];
                return;
            }
            
            //decode the response
            NSError *jsonError = nil;
            NSDictionary *dictResponse = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
            BOOL isDictValid = (dictResponse && [dictResponse isKindOfClass:[NSDictionary class]]);
            if (jsonError || !isDictValid) {
                [JMPPUtils logDebug:@"JMPPDataSourceInstagram::requestAccessWithSuccess - Error decoding Instagram response: %@", (jsonError) ? jsonError.localizedDescription : @"Invalid dictionary"];
                [[NSUserDefaults standardUserDefaults] removeObjectForKey:kTokenString];
                [[NSUserDefaults standardUserDefaults] synchronize];
                [self requestAccessWithSuccess:success andFailure:failure];
                return;
            }
            
            //check for error
            if (dictResponse[@"meta"][@"error_message"] || dictResponse[@"error_message"]) {
                NSString *strErr = dictResponse[@"meta"][@"error_message"] ? dictResponse[@"meta"][@"error_message"] : dictResponse[@"error_message"];
                [JMPPUtils logDebug:@"JMPPDataSourceInstagram::requestAccessWithSuccess - Error returned from  Instagram: %@", strErr];
                [[NSUserDefaults standardUserDefaults] removeObjectForKey:kTokenString];
                [[NSUserDefaults standardUserDefaults] synchronize];
                [self requestAccessWithSuccess:success andFailure:failure];
                return;
            }
            
            //access token was accepted
            [JMPPUtils logDebug:@"JMPPDataSourceInstagram::requestAccessWithSuccess - Instagram token verified."];
            [self setAccessToken:token];
            if (success) success(nil);
            
        }] resume];
        
    } else {
     
        //store the completion blocks
        [self setAuthSuccess:success];
        [self setAuthFailure:failure];

        //clear cookies
        NSHTTPCookieStorage *cookies = [NSHTTPCookieStorage sharedHTTPCookieStorage];
        NSArray *instagramCookies = [cookies cookiesForURL:[NSURL URLWithString:kInstagramCookieUrl]];
        for (NSHTTPCookie *cookie in instagramCookies) [cookies deleteCookie:cookie];
        
        //load the login webview
        [self showLoginView];
        NSString *url = [NSString stringWithFormat:@"%@?client_id=%@&redirect_uri=%@&response_type=token", kInstagramAuthUrl, self.instagramId, self.instagramRedirectUri];
        [self.webViewLogin loadRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:url]]];

    }
}

- (void)loadAlbumsWithSuccess:(JMPPSuccess)success andFailure:(JMPPFailure)failure
{
    //confirm access
    if (!self.accessToken) {
        
        [self requestAccessWithSuccess:^(id result) {
            [self loadAlbumsWithSuccess:success andFailure:failure];
        } andFailure:^(NSError *error) {
            if (failure) failure(error);
        }];
        return;
        
    }
    
    //create a request to get the media count
    NSString *urlString = [NSString stringWithFormat:@"%@%@", kInstagramApiUrl, kInstagramUserSelf];
    NSURLComponents *components = [NSURLComponents componentsWithString:urlString];
    NSURLQueryItem *queryToken = [NSURLQueryItem queryItemWithName:@"access_token" value:self.accessToken];
    components.queryItems = @[queryToken];
    NSURLRequest *request = [NSURLRequest requestWithURL:components.URL];
    
    //execute request
    [[[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
        
        if (error) {
            [JMPPUtils logDebug:@"JMPPDataSourceInstagram::loadAlbumsWithSuccess - Error loading albums: %@", error.localizedDescription];
            if (failure) failure(error);
            return;
        }
        
        //decode the response
        NSError *jsonError = nil;
        NSDictionary *dictResponse = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
        BOOL isDictValid = (dictResponse && [dictResponse isKindOfClass:[NSDictionary class]]);
        if (jsonError || !isDictValid) {
            [JMPPUtils logDebug:@"JMPPDataSourceInstagram::loadAlbumsWithSuccess - Error decoding Instagram response: %@", (jsonError) ? jsonError.localizedDescription : @"Invalid dictionary"];
            if (failure) failure([JMPPError createErrorWithString:kErrMsgInstaData]);
            return;
        }
        
        //check for error
        if (dictResponse[@"meta"][@"error_message"] || dictResponse[@"error_message"]) {
            NSString *strErr = dictResponse[@"meta"][@"error_message"] ? dictResponse[@"meta"][@"error_message"] : dictResponse[@"error_message"];
            [JMPPUtils logDebug:@"JMPPDataSourceInstagram::loadAlbumsWithSuccess - Error returned from  Instagram: %@", strErr];
            if (failure) failure([JMPPError createErrorWithString:strErr]);
            return;
        }

        //there is only the root album for Instagram
        JMPPAlbum *albumNew = [JMPPAlbum new];
        [albumNew setName:dictResponse[@"data"][@"username"]];
        [albumNew setCount:[dictResponse[@"data"][@"counts"][@"media"] unsignedIntegerValue]];
        if (self.instagramSandboxMode) [albumNew setCount:MIN(20, albumNew.count)];
        
        //return the albums
        if (success) success([NSArray arrayWithObject:albumNew]);

        //start loading the first page of photo metadata in the background
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{
            [self loadPhotoFromAlbum:albumNew withIndex:0 andMinPixels:0 andSuccess:nil andFailure:nil];
        });
        
    }] resume];
}

- (void)loadCoverPhotoForAlbum:(JMPPAlbum *)album withMinPixels:(NSUInteger)minPixels andSuccess:(JMPPSuccess)success andFailure:(JMPPFailure)failure
{
    NSAssert(NO, @"JMPPDataSourceInstagram::loadCoverPhotoForAlbum - Should never be called. Only 1 album.");
}

- (void)loadPhotoFromAlbum:(JMPPAlbum *)album withIndex:(NSUInteger)index andMinPixels:(NSUInteger)minPixels andSuccess:(JMPPSuccess)success andFailure:(JMPPFailure)failure
{
    //confirm access
    if (!self.accessToken) {
        
        [self requestAccessWithSuccess:^(id result) {
            [self loadPhotoFromAlbum:album withIndex:index andMinPixels:minPixels andSuccess:success andFailure:failure];
        } andFailure:^(NSError *error) {
            if (failure) failure(error);
        }];
        return;
        
    }
    
    //get the meta data for this photo
    [self loadPhotoDataForAlbum:album andIndex:index withSuccess:^(NSDictionary *dictPhoto) {
        
        //don't bother loading the image if there is no success block to return it
        if (success) {
            
            //get the images for this photo (each photo has multiple images available from Instagram)
            NSDictionary *dictImages = dictPhoto[@"images"];
            NSDictionary *dictImage = [self findBestImageFromImages:dictImages withMinPixels:minPixels];
            NSString *strUrl = dictImage[@"url"];
            
            //load the photo using SDWebImageManager for caching
            SDWebImageOptions options = (SDWebImageRetryFailed | SDWebImageContinueInBackground);
            [[SDWebImageManager sharedManager] downloadImageWithURL:[NSURL URLWithString:strUrl] options:options progress:nil completed:^(UIImage *image, NSError *error, SDImageCacheType cacheType, BOOL finished, NSURL *imageURL) {
                
                if (error) {
                    [JMPPUtils logDebug:@"JMPPDataSourceInstagram::loadPhotoFromAlbum - Error loading Instagram photo: %@", error.localizedDescription];
                    if (failure) failure(error);
                    return;
                }
                
                if (!image) {
                    [JMPPUtils logDebug:@"JMPPDataSourceInstagram::loadPhotoFromAlbum - Invalid photo received from Instagram"];
                    if (failure) failure([JMPPError createErrorWithString:kErrMsgInstaPhoto]);
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

- (void)handleAuthComplete:(NSString *)accessToken
{
    NSAssert(accessToken, @"JMPPDataSourceInstagram::handleAuthComplete - accessToken required.");
    [JMPPUtils logDebug:@"JMPPDataSourceInstagram::handleAuthComplete - Instagram access granted."];
    
    //store access token
    //NOTE: the access token is not particurly senstitive as it simply authorizes this app to view photos
    [[NSUserDefaults standardUserDefaults] setObject:accessToken forKey:kTokenString];
    [[NSUserDefaults standardUserDefaults] synchronize];
    [self setAccessToken:accessToken];

    //finish up
    [self hideLoginView];
    if (self.authSuccess) self.authSuccess(nil);
    [self setAuthSuccess:nil];
    [self setAuthFailure:nil];
}

- (void)handleAuthError:(NSError *)error
{
    NSAssert(error, @"JMPPDataSourceInstagram::handleAuthComplete - error required.");
    [self hideLoginView];
    if (self.authFailure) self.authFailure(error);
    [self setAuthSuccess:nil];
    [self setAuthFailure:nil];
}

- (void)loadPhotoDataForAlbum:(JMPPAlbum *)album andIndex:(NSUInteger)index withSuccess:(JMPPSuccess)success andFailure:(JMPPFailure)failure
{
    NSAssert(!album.photos || album.nextPhotos || [(NSArray *)album.photos count] == album.count, @"JMPPDataSourceInstagram::loadPhotoDataForAlbum - No photos to load.");

    //load in a serial queue per album (to avoid concurrency issues when multiple cells request loads simultaneously)
    dispatch_async(album.queueLoadPhotos, ^{

        //has the meta data for this photo been loaded already?
        if (album.photos && index < [(NSArray *)album.photos count]) {
            if (success) success(album.photos[index]);
            return;
        }
        
        //create a request
        NSURLRequest *request;
        if (album.nextPhotos) {
            
            request = [NSURLRequest requestWithURL:[NSURL URLWithString:album.nextPhotos]];
            
        } else {
            
            NSString *urlString = [NSString stringWithFormat:@"%@%@", kInstagramApiUrl, kInstagramUserMedia];
            NSURLComponents *components = [NSURLComponents componentsWithString:urlString];
            NSURLQueryItem *queryToken = [NSURLQueryItem queryItemWithName:@"access_token" value:self.accessToken];
            NSURLQueryItem *queryCount = [NSURLQueryItem queryItemWithName:@"count" value:kPhotosPerRequest];
            components.queryItems = @[queryToken, queryCount];
            request = [NSURLRequest requestWithURL:components.URL];
            
        }
        
        //make the request synchronous with a semaphore
        __block NSError *requestError;
        dispatch_semaphore_t semaBlock = dispatch_semaphore_create(0);

        //execute the request
        [[[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
            
            if (error) {
                [JMPPUtils logDebug:@"JMPPDataSourceInstagram::loadPhotosForAlbum - Error loading Instagram photos: %@", error.localizedDescription];
                requestError = error;
                dispatch_semaphore_signal(semaBlock);
                return;
            }
            
            //decode the response
            NSError *jsonError = nil;
            NSDictionary *dictResponse = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
            BOOL isDictValid = (dictResponse && [dictResponse isKindOfClass:[NSDictionary class]]);
            if (jsonError || !isDictValid) {
                [JMPPUtils logDebug:@"JMPPDataSourceInstagram::loadPhotosForAlbum - Error decoding Instagram response: %@", (jsonError) ? jsonError.localizedDescription : @"Invalid dictionary"];
                requestError = [JMPPError createErrorWithString:kErrMsgInstaData];
                dispatch_semaphore_signal(semaBlock);
                return;
            }
            
            //check for error
            if (dictResponse[@"meta"][@"error_message"] || dictResponse[@"error_message"]) {
                NSString *strErr = dictResponse[@"meta"][@"error_message"] ? dictResponse[@"meta"][@"error_message"] : dictResponse[@"error_message"];
                [JMPPUtils logDebug:@"JMPPDataSourceInstagram::loadPhotosForAlbum - Error returned from  Instagram: %@", strErr];
                requestError = [JMPPError createErrorWithString:strErr];
                dispatch_semaphore_signal(semaBlock);
                return;
            }
            
            //get the array
            NSMutableArray *arrayPhotos = [NSMutableArray arrayWithArray:dictResponse[@"data"]];
            if (!arrayPhotos || ![arrayPhotos isKindOfClass:[NSArray class]]) {
                [JMPPUtils logDebug:@"JMPPDataSourceInstagram::loadPhotosForAlbum - Error decoding Instagram response"];
                requestError = [JMPPError createErrorWithString:kErrMsgInstaData];
                dispatch_semaphore_signal(semaBlock);
                return;
            }
            
            //add the photos to the dictionary - TO DO: remove all the extra crap and only store the images info
            if (!album.photos) [album setPhotos:arrayPhotos];
            else [album setPhotos:[album.photos arrayByAddingObjectsFromArray:arrayPhotos]];
            
            //store the next page url
            if (dictResponse[@"pagination"][@"next_url"]) [album setNextPhotos:dictResponse[@"pagination"][@"next_url"]];
            else [album setNextPhotos:nil];
            
            //make sure we haven't added too many photos - multithreading check
            if ([(NSArray *)album.photos count] > album.count) {
                [JMPPUtils logDebug:@"JMPPDataSourceInstagram::loadPhotosForAlbum - Warning: loaded %i photos but the album is only supposed to contain %i photos. This is a problem unless more photos were added to the album since we got the metadata.", (int)[(NSArray *)album.photos count], (int)album.count];
            }
            
            //done
            dispatch_semaphore_signal(semaBlock);
            
        }] resume];

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

- (NSDictionary *)findBestImageFromImages:(NSDictionary *)dictImages withMinPixels:(NSUInteger)minPixels
{
    NSArray *arrayImages = [dictImages allValues];
    NSAssert(arrayImages.count > 0, @"JMPPDataSourceInstagram::findBestImageFromImages - No images in array");
    
    NSUInteger index = 0;
    
    for (int i=1; i< arrayImages.count; i++) {
        
        NSDictionary *dictImageCurrent = arrayImages[index];
        NSDictionary *dictImageToCompare = arrayImages[i];
        
        if (!dictImageCurrent || !dictImageToCompare || !dictImageCurrent[@"height"] || !dictImageToCompare[@"height"] || !dictImageCurrent[@"width"] || !dictImageToCompare[@"width"]) {
            [JMPPUtils logDebug:@"JMPPDataSourceInstagram::findBestImageFromImages - Invalid data."];
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

////////////////////////////////////////////////////////////////
#pragma mark Login UI Methods
////////////////////////////////////////////////////////////////

- (void)showLoginView
{
    //need to run UI on the main thread
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^ { [self showLoginView]; });
        return;
    }

    if (!self.viewLogin) {
        
        //create the views
        [self setViewLogin:[[UIView alloc] initWithFrame:[UIScreen mainScreen].bounds]];
        
        //create the toolbar
        UIToolbar *toolbarLogin = [[UIToolbar alloc] initWithFrame:CGRectMake(0, 0, self.viewLogin.frame.size.width, 44)];
        UIBarButtonItem *buttonSpace = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFixedSpace target:nil action:nil];
        [buttonSpace setWidth:10.0f];
        UIBarButtonItem *buttonCancel = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel target:self action:@selector(actionCancelLogin)];
        [toolbarLogin setItems:@[buttonSpace, buttonCancel]];
        
        //create the webview
        [self setWebViewLogin:[[UIWebView alloc] initWithFrame:CGRectMake(0, 44, self.viewLogin.frame.size.width, self.viewLogin.frame.size.height - 44)]];
        [self.webViewLogin setDelegate:self];
        
        //add the toolbar and webview
        [self.viewLogin addSubview:toolbarLogin];
        [self.viewLogin addSubview:self.webViewLogin];
        
    }
    
    if (!self.viewLogin.superview) {
        
        NSEnumerator *frontToBackWindows = [UIApplication.sharedApplication.windows reverseObjectEnumerator];
        for (UIWindow *window in frontToBackWindows) {
            BOOL windowOnMainScreen = window.screen == UIScreen.mainScreen;
            BOOL windowIsVisible = !window.hidden && window.alpha > 0;
            BOOL windowLevelNormal = window.windowLevel == UIWindowLevelNormal;
            
            if (windowOnMainScreen && windowIsVisible && windowLevelNormal) {
                [window addSubview:self.viewLogin];
                break;
            }
        }
        
    }
}

- (void)hideLoginView
{
    //need to run UI on the main thread
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^ { [self hideLoginView]; });
        return;
    }

    [self.viewLogin removeFromSuperview];
}

- (void)actionCancelLogin
{
    [self handleAuthError:[JMPPError errorUserCanceled]];
}

////////////////////////////////////////////////////////////////
#pragma mark UIWebViewDelegate Methods
////////////////////////////////////////////////////////////////

- (void)webView:(UIWebView *)webView didFailLoadWithError:(NSError *)error
{
    [self handleAuthError:error];
}

- (void)webViewDidFinishLoad:(UIWebView *)webView
{
    NSString *html = [webView stringByEvaluatingJavaScriptFromString: @"document.body.innerHTML"];
    if ([html containsString:@"error_message"]) {
        [JMPPUtils logDebug:@"%@", html];
        [self handleAuthError:[JMPPError createErrorWithString:@"Error authenticating Instagram"]];
        //Note:For some reason if you attempt to login using an invalid sandbox user the error is returned as a webpage
        //with JSON data as the HTML rather than redirecting to the redirect URI with the error. Hopefully this is only a sandbox
        //bug in the Instagram API and no other error conditions get caught here.
    }
}

-(BOOL)webView:(UIWebView *)webView shouldStartLoadWithRequest:(NSURLRequest *)request navigationType:(UIWebViewNavigationType)navigationType
{
    NSURL *url = request.URL;
    
    if([url.absoluteString hasPrefix:self.instagramRedirectUri]) {
        
        NSString *query = [url fragment];
        if (!query) query = [url query];

        NSDictionary *params = [JMPPUtils parseURLParams:query];
        NSString *accessToken = [params valueForKey:@"access_token"];

        if (!accessToken) {
            
            NSString *errorName = [params valueForKey:@"error"];
            NSString *errorReason = [params valueForKey:@"error_reason"];
            NSString *errorDescription = [params valueForKey:@"error_description"];
            
            //BOOL userDenied = [errorReason isEqualToString:@"user_denied"];
            
            if (errorName && errorReason && errorDescription) {

                [JMPPUtils logDebug:@"JMPPDataSourceInstagram::shouldStartLoadWithRequest - Error authorizing Instagram: %@ - %@ - %@", errorName, errorReason, errorDescription];
                [self handleAuthError:[JMPPError createErrorWithString:errorDescription]];

            } else {

                [JMPPUtils logDebug:@"JMPPDataSourceInstagram::shouldStartLoadWithRequest - Error authorizing Instagram: Invalid Response"];
                [self handleAuthError:[JMPPError createErrorWithString:kErrMsgInstaData]];

            }
            
        } else {
            
            //we're good - return the access token
            [self handleAuthComplete:accessToken];

        }
        
        return NO;
        
    }
    
    return YES;
}

@end
