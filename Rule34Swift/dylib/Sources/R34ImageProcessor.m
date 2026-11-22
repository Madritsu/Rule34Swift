//
//  R34ImageProcessor.m
//  Rule34Swift Optimizer
//
//  High-performance image decoding and downsampling using Core Graphics directly.
//

#import "../Headers/R34Optimizations.h"
#import <ImageIO/ImageIO.h>
#import <CoreGraphics/CoreGraphics.h>

@implementation R34ImageProcessor

+ (nullable UIImage *)decodeAndResize:(NSData *)data
                            maxWidth:(CGFloat)maxWidth
                           maxHeight:(CGFloat)maxHeight
                           fastMode:(BOOL)fastMode {
    if (!data || data.length == 0) return nil;

    CGImageSourceRef source = CGImageSourceCreateWithData((__bridge CFDataRef)data, NULL);
    if (!source) return nil;

    CGImageRef cgImage = CGImageSourceCreateImageAtIndex(source, 0, NULL);
    CFRelease(source);
    if (!cgImage) return nil;

    size_t origW = CGImageGetWidth(cgImage);
    size_t origH = CGImageGetHeight(cgImage);

    CGFloat scaleX = maxWidth / (CGFloat)origW;
    CGFloat scaleY = maxHeight / (CGFloat)origH;
    CGFloat scale = MIN(scaleX, scaleY);
    if (scale > 1.0) scale = 1.0;

    size_t targetW = (size_t)round(origW * scale);
    size_t targetH = (size_t)round(origH * scale);

    if (targetW == origW && targetH == origH) {
        UIImage *image = [UIImage imageWithCGImage:cgImage];
        CGImageRelease(cgImage);
        return image;
    }

    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    CGContextRef ctx = CGBitmapContextCreate(NULL, targetW, targetH, 8, targetW * 4,
                                             colorSpace, kCGImageAlphaPremultipliedLast);
    CGColorSpaceRelease(colorSpace);

    if (!ctx) {
        CGImageRelease(cgImage);
        return nil;
    }

    CGContextSetInterpolationQuality(ctx, fastMode ? kCGInterpolationLow : kCGInterpolationHigh);
    CGContextDrawImage(ctx, CGRectMake(0, 0, targetW, targetH), cgImage);

    CGImageRef resized = CGBitmapContextCreateImage(ctx);
    CGContextRelease(ctx);
    CGImageRelease(cgImage);

    UIImage *result = [UIImage imageWithCGImage:resized];
    CGImageRelease(resized);
    return result;
}

+ (nullable UIImage *)downsampleImageAtURL:(NSURL *)url
                                pointSize:(CGSize)pointSize
                            scaleFraction:(CGFloat)scaleFraction {
    if (!url) return nil;

    CGImageSourceRef source = CGImageSourceCreateWithURL((__bridge CFURLRef)url, NULL);
    if (!source) return nil;

    CGFloat maxSize = pointSize.width * scaleFraction;
    NSNumber *maxPixelSize = @(maxSize);
    NSDictionary *opts = @{
        (__bridge NSString *)kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        (__bridge NSString *)kCGImageSourceCreateThumbnailFromImageAlways: @YES
    };
    CGImageRef thumb = CGImageSourceCreateThumbnailAtIndex(source, 0, (__bridge CFDictionaryRef)opts);
    CFRelease(source);

    if (!thumb) return nil;

    UIImage *result = [UIImage imageWithCGImage:thumb];
    CGImageRelease(thumb);
    return result;
}

@end
