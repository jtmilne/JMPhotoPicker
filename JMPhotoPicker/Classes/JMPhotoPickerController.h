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


#import <UIKit/UIKit.h>
#import "JMPPConstants.h"

@class JMPPAlbum;

@protocol JMPhotoPickerDataSource
@required
- (void)requestAccessWithSuccess:(JMPPSuccess)success andFailure:(JMPPFailure)failure;
- (void)loadAlbumsWithSuccess:(JMPPSuccess)success andFailure:(JMPPFailure)failure;
- (void)loadCoverPhotoForAlbum:(JMPPAlbum *)album withMinPixels:(NSUInteger)minPixels andSuccess:(JMPPSuccess)success andFailure:(JMPPFailure)failure;
- (void)loadPhotoFromAlbum:(JMPPAlbum *)album withIndex:(NSUInteger)index andMinPixels:(NSUInteger)minPixels andSuccess:(JMPPSuccess)success andFailure:(JMPPFailure)failure;
@end


@interface JMPhotoPickerController : UIViewController

@property (nonatomic, copy) NSString *instagramId;
@property (nonatomic, copy) NSString *instagramRedirect;
@property (nonatomic) BOOL instagramSandboxMode;
@property (nonatomic, copy) JMPPSuccess successBlock;
@property (nonatomic, copy) JMPPFailure failureBlock;

+ (void)presentWithViewController:(UIViewController *)viewController andInstagramId:(NSString *)instagramId andInstagramRedirect:(NSString *)instagramRedirect andSuccess:(JMPPSuccess)successBlock andFailure:(JMPPFailure)failureBlock;

+ (void)presentWithViewController:(UIViewController *)viewController andInstagramId:(NSString *)instagramId andInstagramRedirect:(NSString *)instagramRedirect andInstagramSandboxMode:(BOOL)instagramSandboxMode andSuccess:(JMPPSuccess)successBlock andFailure:(JMPPFailure)failureBlock;

@end
