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


#import "JMPhotoPickerCollectionViewCell.h"

@interface JMPhotoPickerCollectionViewCell()

@property (nonatomic, strong) IBOutlet UIView *viewPhoto;
@property (nonatomic, strong) IBOutlet UIImageView *imageViewPhoto;
@property (nonatomic, strong) IBOutlet UIActivityIndicatorView *activityIndicator;

@property (nonatomic, strong) IBOutlet NSLayoutConstraint *constraintImageTop;
@property (nonatomic, strong) IBOutlet NSLayoutConstraint *constraintImageBottom;
@property (nonatomic, strong) IBOutlet NSLayoutConstraint *constraintImageLeading;
@property (nonatomic, strong) IBOutlet NSLayoutConstraint *constraintImageTrailing;

@property (nonatomic, strong) NSString *imageIdentifier;

- (void)resetConstraints;

@end

@implementation JMPhotoPickerCollectionViewCell

////////////////////////////////////////////////////////////////
#pragma mark Object Lifecycle
////////////////////////////////////////////////////////////////

- (void)awakeFromNib
{
    [self.viewPhoto.layer setBorderColor:[UIColor blueColor].CGColor];    
}

- (void)prepareForReuse
{
    [super prepareForReuse];
    
    //reset the cell
    [self.imageViewPhoto setImage:nil];
    [self.activityIndicator setHidden:NO];
    [self.activityIndicator startAnimating];
    [self setImageIdentifier:nil];
    [self resetConstraints];

}

////////////////////////////////////////////////////////////////
#pragma mark Custom Setters/Getters
////////////////////////////////////////////////////////////////

- (void)setSelected:(BOOL)selected
{
    [super setSelected:selected];
    [self.viewPhoto.layer setBorderWidth:(selected) ? 2 : 0];
}

////////////////////////////////////////////////////////////////
#pragma mark Public Methods
////////////////////////////////////////////////////////////////

- (void)updateCellFromDataSource:(NSObject<JMPhotoPickerDataSource> *)dataSource andAlbum:(JMPPAlbum *)album andIndex:(NSUInteger)index
{
    NSString *imageIdentifier = [[NSUUID UUID] UUIDString];
    [self setImageIdentifier:imageIdentifier];
    
    //calculate image size to request
    [self resetConstraints];
    NSUInteger pixels = roundf(self.viewPhoto.bounds.size.width * [UIScreen mainScreen].scale);

    //load the image and center it in the square
    [dataSource loadPhotoFromAlbum:album withIndex:index andMinPixels:pixels andSuccess:^(UIImage *image) {
        
        //make sure this image is still the image for this cell (in case it's been reused since we sent the download request)
        if (self.imageIdentifier && [self.imageIdentifier isEqualToString:imageIdentifier]) {
            
            dispatch_async(dispatch_get_main_queue(), ^ {
                
                CGFloat aspectRatio = image.size.width / image.size.height;

                if (aspectRatio < 1.0f) {
                    
                    CGFloat dy = self.imageViewPhoto.frame.size.height - (self.imageViewPhoto.frame.size.width / aspectRatio);
                    [self.constraintImageTop setConstant:dy/2.0f];
                    [self.constraintImageBottom setConstant:dy/2.0f];
                    [self layoutIfNeeded];
                    
                } else if (aspectRatio > 1.0f) {
                    
                    CGFloat dx = self.imageViewPhoto.frame.size.width - (self.imageViewPhoto.frame.size.height * aspectRatio);
                    [self.constraintImageLeading setConstant:dx/2.0f];
                    [self.constraintImageTrailing setConstant:dx/2.0f];
                    [self layoutIfNeeded];
                    
                }
                
                [self.imageViewPhoto setImage:image];
                [self.activityIndicator stopAnimating];

            });
            
        }
        
    } andFailure:^(NSError *error) {
        
        dispatch_async(dispatch_get_main_queue(), ^ {
            
            [self.imageViewPhoto setImage:kImageDownloadFail];
            [self.activityIndicator stopAnimating];
            
        });
        
    }];
}

////////////////////////////////////////////////////////////////
#pragma mark Private Methods
////////////////////////////////////////////////////////////////

- (void)resetConstraints
{
    [self.constraintImageTop setConstant:0.0f];
    [self.constraintImageBottom setConstant:0.0f];
    [self.constraintImageLeading setConstant:0.0f];
    [self.constraintImageTrailing setConstant:0.0f];
    [self layoutIfNeeded];
}

@end
