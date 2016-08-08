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


#import "JMPPDataSourceLibrary.h"
#import <UIKit/UIImage.h>
#import <Photos/Photos.h>
#import "JMPPUtils.h"
#import "JMPPAlbum.h"
#import "JMPPStrings.h"
#import "JMPPError.h"

@interface JMPPDataSourceLibrary()

- (NSArray *)loadAlbumsWithType:(NSInteger)type andSubtypes:(NSArray *)arraySubtypes;
- (void)addCollections:(NSArray *)fetchResults toAlbums:(NSMutableArray *)albums;

@end

@implementation JMPPDataSourceLibrary

////////////////////////////////////////////////////////////////
#pragma mark JMPhotoPickerDataSource Delegate Methods
////////////////////////////////////////////////////////////////

- (void)requestAccessWithSuccess:(JMPPSuccess)success andFailure:(JMPPFailure)failure
{
    [PHPhotoLibrary requestAuthorization:^(PHAuthorizationStatus status) {
        
        if (status == PHAuthorizationStatusAuthorized) {
            if (success) success(nil);
        } else {
            if (failure) failure([JMPPError createErrorWithString:kErrMsgLibDenied]);
        }
            
    }];
}

- (void)loadAlbumsWithSuccess:(JMPPSuccess)success andFailure:(JMPPFailure)failure
{
    //confirm access
    if (PHPhotoLibrary.authorizationStatus != PHAuthorizationStatusAuthorized) {
        
        [self requestAccessWithSuccess:^(id result) {
            [self loadAlbumsWithSuccess:success andFailure:failure];
        } andFailure:^(NSError *error) {
            if (failure) failure(error);
        }];
        return;
        
    }
    
    NSMutableArray *arrayAlbums = [NSMutableArray array];
    
    //load Smart Albums
    NSArray *arraySmartAlbums = [self loadAlbumsWithType:PHAssetCollectionTypeSmartAlbum
                                             andSubtypes:@[
                                                           [NSNumber numberWithInteger:PHAssetCollectionSubtypeSmartAlbumUserLibrary],
                                                           [NSNumber numberWithInteger:PHAssetCollectionSubtypeSmartAlbumRecentlyAdded],
                                                           [NSNumber numberWithInteger:PHAssetCollectionSubtypeSmartAlbumFavorites],
                                                           [NSNumber numberWithInteger:PHAssetCollectionSubtypeSmartAlbumBursts]
                                                           ]
                             ];
    [self addCollections:arraySmartAlbums toAlbums:arrayAlbums];
    
    //load User Albums
    NSArray *arrayUserAlbums = [self loadAlbumsWithType:PHAssetCollectionTypeAlbum andSubtypes:@[[NSNumber numberWithInteger:PHAssetCollectionSubtypeAny]]];
    [self addCollections:arrayUserAlbums toAlbums:arrayAlbums];

    success(arrayAlbums);
}

- (void)loadCoverPhotoForAlbum:(JMPPAlbum *)album withMinPixels:(NSUInteger)minPixels andSuccess:(JMPPSuccess)success andFailure:(JMPPFailure)failure
{
    [self loadPhotoFromAlbum:album withIndex:0 andMinPixels:minPixels andSuccess:success andFailure:failure];
}

 - (void)loadPhotoFromAlbum:(JMPPAlbum *)album withIndex:(NSUInteger)index andMinPixels:(NSUInteger)minPixels andSuccess:(JMPPSuccess)success andFailure:(JMPPFailure)failure;
{
    //get this asset from the album
    PHAsset *asset = album.photos[index];
    NSAssert (asset.mediaType == PHAssetMediaTypeImage, @"JMPPDataSourceLibrary::loadPhotoFromAlbum - Invalid media type");
    
    //calculate the target size
    CGSize targetSize = CGSizeMake(minPixels, minPixels);
    
    //make the shorter side the minPixels
    if (asset.pixelWidth < asset.pixelHeight) {
        CGFloat dy = (CGFloat)asset.pixelHeight/(CGFloat)asset.pixelWidth;
        targetSize.height = roundf(targetSize.height * dy);
    } else if (asset.pixelWidth > asset.pixelHeight) {
        CGFloat dx = (CGFloat)asset.pixelWidth/(CGFloat)asset.pixelHeight;
        targetSize.width = roundf(targetSize.width * dx);
    }
    
    //make the request only load the final result (no intermediate images)
    PHImageRequestOptions *options = [[PHImageRequestOptions alloc] init];
    [options setDeliveryMode:PHImageRequestOptionsDeliveryModeHighQualityFormat];
    [options setResizeMode:PHImageRequestOptionsResizeModeExact];
    
    //get the image and return it
    [[PHImageManager defaultManager] requestImageForAsset:asset targetSize:targetSize contentMode:PHImageContentModeDefault options:options resultHandler:^(UIImage * _Nullable result, NSDictionary * _Nullable info) {
        if (success) success(result);
    }];
}

////////////////////////////////////////////////////////////////
#pragma mark Private Methods
////////////////////////////////////////////////////////////////

- (NSArray *)loadAlbumsWithType:(NSInteger)type andSubtypes:(NSArray *)arraySubtypes
{
    NSMutableArray *results = [NSMutableArray array];
    for (NSNumber *numberSubtype in arraySubtypes) {
        PHFetchResult *fetchResult = [PHAssetCollection fetchAssetCollectionsWithType:type subtype:[numberSubtype integerValue] options:nil];
        if (fetchResult.count > 0) [results addObject:fetchResult];
    }
    return results;
}

- (void)addCollections:(NSArray *)fetchResults toAlbums:(NSMutableArray *)albums
{
    for (PHFetchResult *fetchResult in fetchResults) {
        
        [fetchResult enumerateObjectsUsingBlock:^(PHAssetCollection *collection, NSUInteger idx, BOOL *stop) {

            PHFetchOptions *onlyImagesOptions = [PHFetchOptions new];
            onlyImagesOptions.predicate = [NSPredicate predicateWithFormat:@"mediaType = %i", PHAssetMediaTypeImage];
            onlyImagesOptions.sortDescriptors = @[[NSSortDescriptor sortDescriptorWithKey:@"creationDate" ascending:NO]];
            PHFetchResult *result = [PHAsset fetchAssetsInAssetCollection:collection options:onlyImagesOptions];
            if (result.count > 0) {
                
                //create a new album and add to the result
                JMPPAlbum *albumNew = [JMPPAlbum new];
                [albumNew setName:collection.localizedTitle];
                [albumNew setCount:result.count];
                [albumNew setPhotos:result];
                [albums addObject:albumNew];
                
            }

            
        }];
        
    }
}

@end
