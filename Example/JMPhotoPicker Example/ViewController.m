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


#import "ViewController.h"
#import "JMPhotoPickerController.h"
#import "JMPPUtils.h"

//********UPDATE CREDENTIALS********

//Note:App bundle identifier must match Facebook App's bundle identifier
#define kFacebookId             @""
#define kInstagramId            @""
#define kInstagramRedirect      @""
#define kInstagramSandbox       NO //indicates we will get max 20 images back in sandbox mode
//NOTE: be sure to set NSPhotoLibraryUsageDescription or iOS 10 will exit/crash

//*********************************

@interface ViewController ()

@property (nonatomic, strong) IBOutlet UIImageView *imageView;

- (IBAction)actionJMPhotoPicker:(id)sender;

@end

@implementation ViewController

- (IBAction)actionJMPhotoPicker:(id)sender
{
    [JMPhotoPickerController presentWithViewController:self andFacebookId:kFacebookId andInstagramId:kInstagramId andInstagramRedirect:kInstagramRedirect andInstagramSandboxMode:kInstagramSandbox andSuccess:^(UIImage *image) {
        if (image) [self.imageView setImage:image];
    } andFailure:^(NSError *error) {
        [JMPPUtils showAlert:error.localizedDescription];
    }];
}

@end
