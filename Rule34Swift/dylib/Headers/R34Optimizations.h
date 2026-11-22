//
//  R34Optimizations.h
//  Rule34Swift Optimizer Framework
//
//  Objective-C dynamic library for performance-critical operations.
//  4 modules: Image Processing, Network, Batch Download, Data Parsing.
//

#import <Foundation/Foundation.h>

#if __has_include(<UIKit/UIKit.h>)
#import <UIKit/UIKit.h>
#endif

NS_ASSUME_NONNULL_BEGIN

// MARK: - Module 1: Image Processor

@interface R34ImageProcessor : NSObject

/// Decode and resize image data at background priority. Returns nil on failure.
+ (nullable UIImage *)decodeAndResize:(NSData *)data
                            maxWidth:(CGFloat)maxWidth
                           maxHeight:(CGFloat)maxHeight
                           fastMode:(BOOL)fastMode;

/// Downsample a JPEG/PNG file on disk without fully loading into memory.
+ (nullable UIImage *)downsampleImageAtURL:(NSURL *)url
                                pointSize:(CGSize)pointSize
                            scaleFraction:(CGFloat)scaleFraction;

@end

// MARK: - Module 2: Network Manager

@interface R34NetworkManager : NSObject

/// Shared singleton session with optimized configuration.
+ (NSURLSession *)optimizedSession;

/// Prefetch multiple URLs into the session cache. Completion fires when all finish.
+ (void)prefetchURLs:(NSArray<NSURL *> *)urls
         referer:(NSString *)referer
      completion:(void (^)(NSUInteger succeeded, NSUInteger failed))completion;

/// Cancel all pending prefetch tasks.
+ (void)cancelPrefetch;

@end

// MARK: - Module 3: Data Parser

@interface R34DataParser : NSObject

/// Extract tag categories from raw tag string (space-separated). Returns dict: category -> [tag].
+ (NSDictionary<NSString *, NSArray<NSString *> *> *)parseTags:(NSString *)rawTags;

/// Decode HTML entities in a string.
+ (NSString *)decodeHTMLEntities:(NSString *)string;

/// Extract numeric post IDs from a JSON array of dictionaries.
+ (NSArray<NSString *> *)extractPostIDsFromJSON:(NSData *)jsonData;

@end

NS_ASSUME_NONNULL_END
