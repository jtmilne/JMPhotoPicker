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


#import "JMPhotoPickerController.h"
#import "JMPhotoPickerCollectionViewCell.h"
#import "JMPhotoPickerTableViewCell.h"
#import "JMPPDataSourceLibrary.h"
#import "JMPPDataSourceFacebook.h"
#import "JMPPDataSourceInstagram.h"
#import "JMPPAlbum.h"
#import "JMPPUtils.h"
#import "MBProgressHUD.h"
#import "JMPPStrings.h"
#import "JMPPError.h"

#define rad(angle)              ((angle) / 180.0 * M_PI)

#define kCollectionCellNib      @"JMPhotoPickerCollectionViewCell"
#define kCollectionCellReuseId  @"JMPhotoPickerCollectionCell"
#define kTableCellNib           @"JMPhotoPickerTableViewCell"
#define kTableCellReuseId       @"JMPhotoPickerTableCell"

#define kCellsPerRow            4

#define kImagePixels            [UIScreen mainScreen].bounds.size.width * [UIScreen mainScreen].scale
#define kImagePixelsThumbnail   (kImagePixels - (kCellSpacing*(kCellsPerRow-1)))/kCellsPerRow

#define kColorTextSelected      [UIColor blackColor]
#define kColorTextUnselected    [UIColor colorWithRed:170.0f/255.0f green:170.0f/255.0f blue:170.0f/255.0f alpha:1.0f]

@interface JMPhotoPickerController () <UIScrollViewDelegate, UICollectionViewDataSource, UICollectionViewDelegate, UICollectionViewDelegateFlowLayout, UITableViewDelegate, UITableViewDataSource>

@property (nonatomic, strong) IBOutlet UIView *viewHeader;
@property (nonatomic, strong) IBOutlet UIView *viewFooter;
@property (nonatomic, strong) IBOutlet UIButton *buttonDone;
@property (nonatomic, strong) IBOutlet UIButton *buttonSelect;
@property (nonatomic, strong) IBOutlet UIScrollView *scrollViewPhoto;
@property (nonatomic, strong) IBOutlet UIImageView *imageViewPhoto;
@property (nonatomic, strong) IBOutlet UICollectionView *collectionViewPhotos;
@property (nonatomic, strong) IBOutlet UIButton *buttonLibrary;
@property (nonatomic, strong) IBOutlet UIButton *buttonFacebook;
@property (nonatomic, strong) IBOutlet UIButton *buttonInstagram;
@property (nonatomic, strong) IBOutlet UIView *viewAlbum;
@property (nonatomic, strong) IBOutlet UILabel *labelAlbumName;
@property (nonatomic, strong) IBOutlet UIImageView *imageViewMoreAlbums;
@property (nonatomic, strong) IBOutlet UIView *viewAlbums;
@property (nonatomic, strong) IBOutlet UITableView *tableViewAlbums;
@property (nonatomic, strong) IBOutlet UIActivityIndicatorView *activityIndicator;

@property (nonatomic, strong) IBOutlet NSLayoutConstraint *constraintImageViewHeight;
@property (nonatomic, strong) IBOutlet NSLayoutConstraint *constraintImageViewWidth;
@property (nonatomic, strong) IBOutlet NSLayoutConstraint *constraintCollectionViewTop;

@property (nonatomic, strong) NSObject<JMPhotoPickerDataSource> *currentDataSource;
@property (nonatomic, strong) JMPPDataSourceLibrary *libraryDataSource;
@property (nonatomic, strong) JMPPDataSourceFacebook *facebookDataSource;
@property (nonatomic, strong) JMPPDataSourceInstagram *instagramDataSource;
@property (nonatomic, strong) NSArray *arrayAlbums;
@property (nonatomic, strong) JMPPAlbum *currentAlbum;
@property (nonatomic, copy) NSString *currentImageIdentifier;

- (IBAction)actionCancel:(id)sender;
- (IBAction)actionSelectImage:(id)sender;
- (IBAction)actionSelectDataSource:(id)sender;
- (IBAction)actionMoreAlbums:(id)sender;

//view management
- (void)updateAlbumView;
- (void)showAlbumsView;
- (void)hideAlbumsView;
- (void)showSelectedDataSourceButton:(UIButton *)button;
- (void)showImage:(UIImage *)imageToShow;

//utility methods
- (void)loadAlbumsWithSuccess:(JMPPSuccess)success andFailure:(JMPPFailure)failure;
- (void)switchToAlbumWithIndex:(NSUInteger)index;
- (UIImage *)captureImage;

@end

@implementation JMPhotoPickerController

////////////////////////////////////////////////////////////////
#pragma mark Class Methods
////////////////////////////////////////////////////////////////

+ (void)presentWithViewController:(UIViewController *)viewController andFacebookId:(NSString *)facebookId andInstagramId:(NSString *)instagramId andInstagramRedirect:(NSString *)instagramRedirect andSuccess:(JMPPSuccess)successBlock andFailure:(JMPPFailure)failureBlock;
{
    [JMPhotoPickerController presentWithViewController:viewController andFacebookId:facebookId andInstagramId:instagramId andInstagramRedirect:instagramRedirect andInstagramSandboxMode:NO andSuccess:successBlock andFailure:failureBlock];
}

+ (void)presentWithViewController:(UIViewController *)viewController andFacebookId:(NSString *)facebookId andInstagramId:(NSString *)instagramId andInstagramRedirect:(NSString *)instagramRedirect andInstagramSandboxMode:(BOOL)instagramSandboxMode andSuccess:(JMPPSuccess)successBlock andFailure:(JMPPFailure)failureBlock;
{
    JMPhotoPickerController *picker = [[JMPhotoPickerController alloc] init];
    [picker setFacebookId:facebookId];
    [picker setInstagramId:instagramId];
    [picker setInstagramRedirect:instagramRedirect];
    [picker setInstagramSandboxMode:instagramSandboxMode];
    [picker setSuccessBlock:successBlock];
    [picker setFailureBlock:failureBlock];
    [viewController presentViewController:picker animated:YES completion:nil];
}

////////////////////////////////////////////////////////////////
#pragma mark Object Lifecycle
////////////////////////////////////////////////////////////////

- (instancetype)init
{
    self = [super init];
    if (self) {
        [self setInstagramSandboxMode:NO];
        [self setLibraryDataSource:[[JMPPDataSourceLibrary alloc] init]];
        [self setFacebookDataSource:[[JMPPDataSourceFacebook alloc] init]];
        [self setInstagramDataSource:[[JMPPDataSourceInstagram alloc] init]];
        [self setCurrentDataSource:self.libraryDataSource];
    }
    return self;
}

////////////////////////////////////////////////////////////////
#pragma mark Custom Setters
////////////////////////////////////////////////////////////////

- (void)setFacebookId:(NSString *)facebookId
{
    _facebookId = [facebookId copy];
    [self.facebookDataSource setFacebookId:facebookId];
}

- (void)setInstagramId:(NSString *)instagramId
{
    _instagramId = [instagramId copy];
    [self.instagramDataSource setInstagramId:instagramId];
}

- (void)setInstagramRedirect:(NSString *)instagramRedirect
{
    _instagramRedirect = [instagramRedirect copy];
    [self.instagramDataSource setInstagramRedirectUri:instagramRedirect];
}

- (void)setInstagramSandboxMode:(BOOL)instagramSandboxMode
{
    _instagramSandboxMode = instagramSandboxMode;
    [self.instagramDataSource setInstagramSandboxMode:instagramSandboxMode];
}

////////////////////////////////////////////////////////////////
#pragma mark View Lifecycle
////////////////////////////////////////////////////////////////

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    NSAssert(self.facebookId && self.instagramId && self.instagramRedirect, @"JMPhotoPickerController::viewDidLoad - Social credentials not initialized");
        
    //register the NIB
    UINib *cellNibUser = [UINib nibWithNibName:kCollectionCellNib bundle:[NSBundle mainBundle]];
    [self.collectionViewPhotos registerNib:cellNibUser forCellWithReuseIdentifier:kCollectionCellReuseId];

    //load the folders for the current data source
    [self showSelectedDataSourceButton:self.buttonLibrary];
    [self loadAlbumsWithSuccess:nil andFailure:^(NSError *error) {
        
        [JMPPUtils logDebug:@"JMPhotoPickerController::viewDidLoad - Failed to load photo library: %@", error.localizedDescription];
        dispatch_async(dispatch_get_main_queue(), ^ {
            [self dismissViewControllerAnimated:YES completion:^{
                if (self.failureBlock) self.failureBlock(error);
            }];
        });
        
    }];
}

- (BOOL)prefersStatusBarHidden
{
    return YES;
}

////////////////////////////////////////////////////////////////
#pragma mark View Management
////////////////////////////////////////////////////////////////

- (void)updateAlbumView
{
    //ensure main thread for UI operations
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^ { [self updateAlbumView]; });
        return;
    }

    [self.labelAlbumName setText:self.currentAlbum.name];
    [self.imageViewMoreAlbums setHidden:(self.arrayAlbums.count < 2)];
    [self.viewAlbum layoutIfNeeded];
}

- (void)showAlbumsView
{
    //ensure main thread for UI operations
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^ { [self showAlbumsView]; });
        return;
    }

    if (!self.viewAlbums.superview) {
        
        [self.buttonDone setHidden:YES];
        [self.buttonSelect setHidden:YES];
        
        CGFloat screenHeight = self.viewFooter.frame.origin.y + self.viewFooter.frame.size.height;
        [self.viewAlbums setFrame:CGRectMake(0, screenHeight+1, self.viewFooter.bounds.size.width, screenHeight - self.viewHeader.bounds.size.height)];
        [self.view addSubview:self.viewAlbums];
        [UIView animateWithDuration:0.3 animations:^{
            [self.viewAlbums setFrame:CGRectMake(0, self.viewHeader.bounds.size.height, self.viewAlbums.bounds.size.width, self.viewAlbums.bounds.size.height)];
        }];
    }
}

- (void)hideAlbumsView
{
    //ensure main thread for UI operations
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^ { [self hideAlbumsView]; });
        return;
    }

    if (self.viewAlbums.superview) {
        
        [self.buttonDone setHidden:NO];
        [self.buttonSelect setHidden:NO];

        CGFloat screenHeight = self.viewFooter.frame.origin.y + self.viewFooter.frame.size.height;
        [UIView animateWithDuration:0.3 animations:^{
            [self.viewAlbums setFrame:CGRectMake(0, screenHeight+1, self.viewAlbums.bounds.size.width, self.viewAlbums.bounds.size.height)];
        } completion:^(BOOL finished) {
            [self.viewAlbums removeFromSuperview];
        }];
        
    }
}

- (void)showSelectedDataSourceButton:(UIButton *)button
{
    //ensure main thread for UI operations
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^ { [self showSelectedDataSourceButton:button]; });
        return;
    }
    
    [self.buttonLibrary setSelected:[button isEqual:self.buttonLibrary]];
    [self.buttonFacebook setSelected:[button isEqual:self.buttonFacebook]];
    [self.buttonInstagram setSelected:[button isEqual:self.buttonInstagram]];
    
    [self.buttonLibrary setTitleColor:[button isEqual:self.buttonLibrary] ? kColorTextSelected : kColorTextUnselected forState:UIControlStateNormal];
    [self.buttonFacebook setTitleColor:[button isEqual:self.buttonFacebook] ? kColorTextSelected : kColorTextUnselected forState:UIControlStateNormal];
    [self.buttonInstagram setTitleColor:[button isEqual:self.buttonInstagram] ? kColorTextSelected : kColorTextUnselected forState:UIControlStateNormal];
}

- (void)showImage:(UIImage *)imageToShow
{
    //ensure main thread for UI operations
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^ { [self showImage:imageToShow]; });
        return;
    }
    
    [self.scrollViewPhoto setZoomScale:1.0f];
    
    //init sizing vars
    CGFloat height=0.0f, width=0.0f, xOffset=0.0f, yOffset=0.0f;
    
    //calculate sizing vars
    if (imageToShow.size.width > imageToShow.size.height) {
        
        width = self.scrollViewPhoto.frame.size.width * (imageToShow.size.width / imageToShow.size.height);
        height = self.scrollViewPhoto.frame.size.height;
        xOffset = MAX(0, (width - self.scrollViewPhoto.frame.size.width)/2);
        
    } else {
        
        width = self.scrollViewPhoto.frame.size.width;
        height = self.scrollViewPhoto.frame.size.height * (imageToShow.size.height / imageToShow.size.width);
        yOffset = MAX(0, (height - self.scrollViewPhoto.frame.size.height)/2);
        
    }
    
    //update imageview size constraints
    [self.constraintImageViewWidth setConstant:width];
    [self.constraintImageViewHeight setConstant:height];
    [self.view layoutIfNeeded];
    
    //center the photo in the scroll view
    [self.scrollViewPhoto scrollRectToVisible:CGRectMake(xOffset, yOffset, MIN(width,height), MIN(width,height)) animated:NO];
    
    //add the image
    [self.imageViewPhoto setImage:imageToShow];
}

////////////////////////////////////////////////////////////////
#pragma mark Action Methods
////////////////////////////////////////////////////////////////

- (IBAction)actionCancel:(id)sender
{
    //ensure main thread for UI operations
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^ { [self actionCancel:sender]; });
        return;
    }

    [self dismissViewControllerAnimated:YES completion:^{
        if (self.failureBlock) self.failureBlock([JMPPError errorUserCanceled]);
    }];
}

- (IBAction)actionSelectImage:(id)sender
{
    //ensure main thread for UI operations
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^ { [self actionSelectImage:sender]; });
        return;
    }

    UIImage *image;
    if (self.imageViewPhoto.image) image = [self captureImage];
    
    [self dismissViewControllerAnimated:YES completion:^{
        if (self.successBlock) self.successBlock(image);
    }];
}

- (IBAction)actionSelectDataSource:(id)sender
{
    UIButton *button = sender;
    if (!button.isSelected) {
        
        if ([button isEqual:self.buttonLibrary]) {
            
            [self setCurrentDataSource:self.libraryDataSource];
            [self showSelectedDataSourceButton:self.buttonLibrary];
            
        } else if ([button isEqual:self.buttonFacebook]) {

            [self setCurrentDataSource:self.facebookDataSource];
            [self showSelectedDataSourceButton:self.buttonFacebook];

        } else if ([button isEqual:self.buttonInstagram]) {

            [self setCurrentDataSource:self.instagramDataSource];
            [self showSelectedDataSourceButton:self.buttonInstagram];

        } else {
        
            NSAssert(NO, @"JMPhotoPickerController::actionSelectDataSource - Invalid button.");

        }

        [MBProgressHUD showHUDAddedTo:self.view animated:YES];
        
        [self loadAlbumsWithSuccess:^(id result) {
            
            dispatch_async(dispatch_get_main_queue(), ^{
                [MBProgressHUD hideHUDForView:self.view animated:YES];
            });
            
        } andFailure:^(NSError *error) {
            
            [JMPPUtils logDebug:@"JMPhotoPickerController::actionSelectDataSource - Error loading albums: %@", error.localizedDescription];

            dispatch_async(dispatch_get_main_queue(), ^{
                [MBProgressHUD hideHUDForView:self.view animated:YES];
                if (error.code != kErrorCodeCanceled) [JMPPUtils showAlert:error.localizedDescription];
                [self actionSelectDataSource:self.buttonLibrary]; //revert back to photo library
            });
            
        }];

    }
}

- (IBAction)actionMoreAlbums:(id)sender
{
    if (!self.imageViewMoreAlbums.hidden) {
        if (self.viewAlbums.superview) [self hideAlbumsView];
        else [self showAlbumsView];
    }
}

////////////////////////////////////////////////////////////////
#pragma mark Utility Methods
////////////////////////////////////////////////////////////////

- (void)loadAlbumsWithSuccess:(JMPPSuccess)success andFailure:(JMPPFailure)failure
{
    [self.currentDataSource loadAlbumsWithSuccess:^(NSArray *results) {
        
        NSAssert([results isKindOfClass:[NSArray class]] && results.count > 0, @"JMPhotoPickerController::loadAlbumsWithSuccess - Invalid response.");
        
        [self setArrayAlbums:results];
        [self.tableViewAlbums reloadData];
        [self switchToAlbumWithIndex:0];
        
        if (success) success(nil);
        
    } andFailure:^(NSError *error) {
        
        if (failure) failure(error);

    }];
}

- (void)switchToAlbumWithIndex:(NSUInteger)index
{
    //ensure main thread for UI operations
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^ { [self switchToAlbumWithIndex:index]; });
        return;
    }

    [self setCurrentAlbum:self.arrayAlbums[index]];
    
    //update the folder drop down button
    [self updateAlbumView];
    
    //update the collection view
    [self.collectionViewPhotos reloadData];
    
    //select the first image in the collection view
    if (self.currentAlbum.count > 0) {
        
        [self.collectionViewPhotos selectItemAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:0] animated:NO scrollPosition:UICollectionViewScrollPositionTop];
        [self collectionView:self.collectionViewPhotos didSelectItemAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:0]];

    } else {
        [self.imageViewPhoto setImage:nil];
    }
}

- (UIImage *)captureImage
{
    if (!self.imageViewPhoto.image) return nil;
    
    UIImage *img = self.imageViewPhoto.image;
    
    //does the image need to be cropped?
    if (self.scrollViewPhoto.zoomScale == 1.0f && img.size.width == img.size.height) {
        
        return self.imageViewPhoto.image;
        
    } else {
        
        CGRect visibleRect = [self.scrollViewPhoto convertRect:self.scrollViewPhoto.bounds toView:self.imageViewPhoto];
        CGFloat scaleFactor = (img.size.width / self.imageViewPhoto.frame.size.width) * self.scrollViewPhoto.zoomScale;
        visibleRect = CGRectMake(visibleRect.origin.x * scaleFactor, visibleRect.origin.y * scaleFactor, visibleRect.size.width * scaleFactor, visibleRect.size.height * scaleFactor);
        
        CGAffineTransform rectTransform;
        switch (img.imageOrientation)
        {
            case UIImageOrientationLeft:
                rectTransform = CGAffineTransformTranslate(CGAffineTransformMakeRotation(rad(90)), 0, -img.size.height);
                break;
            case UIImageOrientationRight:
                rectTransform = CGAffineTransformTranslate(CGAffineTransformMakeRotation(rad(-90)), -img.size.width, 0);
                break;
            case UIImageOrientationDown:
                rectTransform = CGAffineTransformTranslate(CGAffineTransformMakeRotation(rad(-180)), -img.size.width, -img.size.height);
                break;
            default:
                rectTransform = CGAffineTransformIdentity;
        };
        visibleRect = CGRectApplyAffineTransform(visibleRect, CGAffineTransformScale(rectTransform, img.scale, img.scale));
        
        CGImageRef refImage = CGImageCreateWithImageInRect([self.imageViewPhoto.image CGImage], visibleRect);
        UIImage *imageCaptured = [[UIImage alloc] initWithCGImage:refImage scale:self.imageViewPhoto.image.scale orientation:self.imageViewPhoto.image.imageOrientation];
        CGImageRelease(refImage);
        refImage = NULL;
        return imageCaptured;
        
    }
}

////////////////////////////////////////////////////////////////
#pragma mark UIScrollView Delegate Methods
////////////////////////////////////////////////////////////////

-(UIView *)viewForZoomingInScrollView:(UIScrollView *)scrollView
{
    return self.imageViewPhoto;
}

////////////////////////////////////////////////////////////////
#pragma mark UICollectionView Delegate Methods
////////////////////////////////////////////////////////////////

- (NSInteger)numberOfSectionsInCollectionView:(UICollectionView *)collectionView
{
    return 1;
}

- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section
{
    return (self.currentAlbum) ? self.currentAlbum.count : 0;
}

- (UICollectionViewCell *)collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath
{
    JMPhotoPickerCollectionViewCell *cell=[collectionView dequeueReusableCellWithReuseIdentifier:kCollectionCellReuseId forIndexPath:indexPath];
    
    [cell updateCellFromDataSource:self.currentDataSource andAlbum:self.currentAlbum andIndex:indexPath.row];

    return cell;
}

- (void)collectionView:(UICollectionView *)collectionView didSelectItemAtIndexPath:(NSIndexPath *)indexPath
{
    //store an id for this image request
    NSString *imageIdentifier = [[NSUUID UUID] UUIDString];
    [self setCurrentImageIdentifier:imageIdentifier];
    
    //reset the image to show it is loading only if it doesn't load really fast (avoid the flicker if it loads super fast)
    __block BOOL loaded = NO;
    dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, 0.3 * NSEC_PER_SEC);
    dispatch_after(popTime, dispatch_get_main_queue(), ^{
        
        //reset the main photo
        if (!loaded) {
            [self.imageViewPhoto setImage:nil];
            [self.activityIndicator setHidden:NO];
            [self.activityIndicator startAnimating];
        }
        
    });
    
    //load the selected photo
    [self.currentDataSource loadPhotoFromAlbum:self.currentAlbum withIndex:indexPath.row andMinPixels:(NSUInteger)kImagePixels andSuccess:^(UIImage *image) {
        
        loaded = YES;

        //make sure this image is still the one we want (in case another cell has been clicked since we sent the download request)
        if (self.currentImageIdentifier && [self.currentImageIdentifier isEqualToString:imageIdentifier]) {
            
            dispatch_async(dispatch_get_main_queue(), ^ {
                [self.activityIndicator stopAnimating];
                if (image) [self showImage:image];
                else [self.imageViewPhoto setImage:kImagePlaceholder];
            });

        }
        
    } andFailure:^(NSError *error) {
        
        loaded = YES;

        dispatch_async(dispatch_get_main_queue(), ^ {
            [self.activityIndicator stopAnimating];
            [self.imageViewPhoto setImage:kImagePlaceholder];
        });
        
    }];
}

- (CGSize)collectionView:(UICollectionView *)collectionView layout:(UICollectionViewLayout*)collectionViewLayout sizeForItemAtIndexPath:(NSIndexPath *)indexPath
{
    CGFloat sizeCell = [UIScreen mainScreen].bounds.size.width/kCellsPerRow;
    return CGSizeMake(sizeCell, sizeCell);
}

- (CGFloat)collectionView:(UICollectionView *)collectionView layout:(UICollectionViewLayout *)collectionViewLayout minimumLineSpacingForSectionAtIndex:(NSInteger)section
{
    return 0.0f;
}

- (CGFloat)collectionView:(UICollectionView *)collectionView layout:(UICollectionViewLayout *)collectionViewLayout minimumInteritemSpacingForSectionAtIndex:(NSInteger)section
{
    return 0.0f;
}

////////////////////////////////////////////////////////////////
#pragma mark UITableView Delegate Methods
////////////////////////////////////////////////////////////////

-(NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return [self.arrayAlbums count];
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath
{
    return 90.0f;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:kTableCellReuseId];
    
    if (cell == nil) {
        
        [tableView registerNib:[UINib nibWithNibName:kTableCellNib bundle:nil] forCellReuseIdentifier:kTableCellReuseId];
        cell = [tableView dequeueReusableCellWithIdentifier:kTableCellReuseId];
        
    }

    return cell;
}

- (void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath
{
    [(JMPhotoPickerTableViewCell *)cell updateCellFromDataSource:self.currentDataSource andAlbum:self.arrayAlbums[indexPath.row]];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    [self hideAlbumsView];
    [self switchToAlbumWithIndex:indexPath.row];
    
}

@end
