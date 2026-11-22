//
//  R34NetworkManager.m
//  Rule34Swift Optimizer
//
//  Optimized NSURLSession with connection pooling, prefetch, and caching.
//

#import "../Headers/R34Optimizations.h"

@implementation R34NetworkManager

+ (NSURLSession *)optimizedSession {
    static NSURLSession *session = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
        config.timeoutIntervalForRequest = 30;
        config.timeoutIntervalForResource = 60;
        config.HTTPMaximumConnectionsPerHost = 6;
        config.requestCachePolicy = NSURLRequestReturnCacheDataElseLoad;
        NSURLCache *cache = [[NSURLCache alloc] initWithMemoryCapacity:50 * 1024 * 1024
                                                         diskCapacity:200 * 1024 * 1024
                                                             diskPath:@"R34NetworkCache"];
        [config setURLCache:cache];
        session = [NSURLSession sessionWithConfiguration:config delegate:nil delegateQueue:nil];
    });
    return session;
}

+ (void)prefetchURLs:(NSArray<NSURL *> *)urls
              referer:(NSString *)referer
           completion:(void (^)(NSUInteger, NSUInteger))completion {
    if (urls.count == 0) {
        if (completion) completion(0, 0);
        return;
    }

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        __block NSUInteger succeeded = 0;
        __block NSUInteger failed = 0;
        dispatch_group_t group = dispatch_group_create();

        for (NSURL *url in urls) {
            dispatch_group_enter(group);
            NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
            [request addValue:referer forHTTPHeaderField:@"Referer"];
            [request addValue:@"Rule34Swift/1.0" forHTTPHeaderField:@"User-Agent"];
            request.cachePolicy = NSURLRequestReloadRevalidatingCacheData;

            NSURLSessionDataTask *task = [[self optimizedSession] dataTaskWithRequest:request
                                                                    completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
                NSHTTPURLResponse *http = (NSHTTPURLResponse *)response;
                if (!error && http.statusCode >= 200 && http.statusCode < 300) {
                    __sync_fetch_and_add(&succeeded, 1);
                } else {
                    __sync_fetch_and_add(&failed, 1);
                }
                dispatch_group_leave(group);
            }];
            [task resume];
        }

        dispatch_group_wait(group, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(60 * NSEC_PER_SEC)));
        if (completion) {
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(succeeded, failed);
            });
        }
    });
}

+ (void)cancelPrefetch {
    [[self optimizedSession] getTasksWithCompletionHandler:^(NSArray *dataTasks, NSArray *uploadTasks, NSArray *downloadTasks) {
        for (NSURLSessionDataTask *task in dataTasks) {
            [task cancel];
        }
    }];
}

@end
