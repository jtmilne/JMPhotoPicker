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

@property (nonatomic, strong) IBOutlet UIView *viewCellPhoto;
@property (nonatomic, strong) IBOutlet UIImageView *imageViewCellPhoto;
@property (nonatomic, strong) IBOutlet UIActivityIndicatorView *activityIndicatorCell;

@property (nonatomic, strong) IBOutlet NSLayoutConstraint *constraintCellImageTop;
@property (nonatomic, strong) IBOutlet NSLayoutConstraint *constraintCellImageBottom;
@property (nonatomic, strong) IBOutlet NSLayoutConstraint *constraintCellImageLeading;
@property (nonatomic, strong) IBOutlet NSLayoutConstraint *constraintCellImageTrailing;

@property (nonatomic, strong) NSString *imageIdentifier;

- (void)resetConstraints;

@end

@implementation JMPhotoPickerCollectionViewCell

////////////////////////////////////////////////////////////////
#pragma mark Object Lifecycle
////////////////////////////////////////////////////////////////

- (void)awakeFromNib
{
    [super awakeFromNib];
    [self.viewCellPhoto.layer setBorderColor:[UIColor blueColor].CGColor];
}

- (void)prepareForReuse
{
    [super prepareForReuse];
    
    //reset the cell
    [self.imageViewCellPhoto setImage:nil];
    [self.activityIndicatorCell setHidden:NO];
    [self.activityIndicatorCell startAnimating];
    [self setImageIdentifier:nil];
    [self resetConstraints];

}

////////////////////////////////////////////////////////////////
#pragma mark Custom Setters/Getters
////////////////////////////////////////////////////////////////

- (void)setSelected:(BOOL)selected
{
    [super setSelected:selected];
    [self.viewCellPhoto.layer setBorderWidth:(selected) ? 2 : 0];
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
    NSUInteger pixels = roundf(self.viewCellPhoto.bounds.size.width * [UIScreen mainScreen].scale);

    //load the image and center it in the square
    [dataSource loadPhotoFromAlbum:album withIndex:index andMinPixels:pixels andSuccess:^(UIImage *image) {
        
        //make sure this image is still the image for this cell (in case it's been reused since we sent the download request)
        if (self.imageIdentifier && [self.imageIdentifier isEqualToString:imageIdentifier]) {
            
            dispatch_async(dispatch_get_main_queue(), ^ {
                
                CGFloat aspectRatio = image.size.width / image.size.height;

                if (aspectRatio < 1.0f) {
                    
                    CGFloat dy = self.imageViewCellPhoto.frame.size.height - (self.imageViewCellPhoto.frame.size.width / aspectRatio);
                    [self.constraintCellImageTop setConstant:dy/2.0f];
                    [self.constraintCellImageBottom setConstant:dy/2.0f];
                    [self layoutIfNeeded];
                    
                } else if (aspectRatio > 1.0f) {
                    
                    CGFloat dx = self.imageViewCellPhoto.frame.size.width - (self.imageViewCellPhoto.frame.size.height * aspectRatio);
                    [self.constraintCellImageLeading setConstant:dx/2.0f];
                    [self.constraintCellImageTrailing setConstant:dx/2.0f];
                    [self layoutIfNeeded];
                    
                }
                
                [self.imageViewCellPhoto setImage:image];
                [self.activityIndicatorCell stopAnimating];

            });
            
        }
        
    } andFailure:^(NSError *error) {
        
        dispatch_async(dispatch_get_main_queue(), ^ {
            
            [self.imageViewCellPhoto setImage:kImageDownloadFail];
            [self.activityIndicatorCell stopAnimating];
            
        });
        
    }];
}

////////////////////////////////////////////////////////////////
#pragma mark Private Methods
////////////////////////////////////////////////////////////////

- (void)resetConstraints
{
    [self.constraintCellImageTop setConstant:0.0f];
    [self.constraintCellImageBottom setConstant:0.0f];
    [self.constraintCellImageLeading setConstant:0.0f];
    [self.constraintCellImageTrailing setConstant:0.0f];
    [self layoutIfNeeded];
}

@end
