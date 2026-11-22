//
//  R34BatchDownloader.m
//  Rule34Swift Optimizer
//
//  Concurrent file downloader with rate limiting and cancellation.
//

#import "../Headers/R34Optimizations.h"

@interface R34BatchDownloader ()
@property (nonatomic, strong) NSOperationQueue *downloadQueue;
@property (nonatomic, strong) NSMutableSet<NSNumber *> *activeTasks;
@property (nonatomic, strong) dispatch_semaphore_t concurrencyLock;
@end

@implementation R34BatchDownloader

- (instancetype)initWithMaxConcurrent:(NSUInteger)max {
    self = [super init];
    if (self) {
        _maxConcurrent = max > 0 ? max : 4;
        _downloadQueue = [[NSOperationQueue alloc] init];
        _downloadQueue.maxConcurrentOperationCount = _maxConcurrent;
        _downloadQueue.qualityOfService = NSQualityOfServiceUserInitiated;
        _activeTasks = [NSMutableSet set];
        _concurrencyLock = dispatch_semaphore_create(_maxConcurrent);
    }
    return self;
}

- (instancetype)init {
    return [self initWithMaxConcurrent:4];
}

- (void)downloadURL:(NSURL *)url
             toFile:(NSURL *)fileURL
        completion:(void (^)(BOOL, NSError * _Nullable))completion {
    if (!url || !fileURL) {
        if (completion) completion(NO, [NSError errorWithDomain:@"R34BatchDownloader"
                                                          code:-1
                                                      userInfo:@{NSLocalizedDescriptionKey: @"Invalid URL or file path"}]);
        return;
    }

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        dispatch_semaphore_wait(self.concurrencyLock, DISPATCH_TIME_FOREVER);

        NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
        [request addValue:@"https://rule34.xxx/" forHTTPHeaderField:@"Referer"];
        [request addValue:@"Rule34Swift/1.0" forHTTPHeaderField:@"User-Agent"];
        request.timeoutInterval = 60;

        NSURLSessionDataTask *task = [[R34NetworkManager optimizedSession] dataTaskWithRequest:request
                                                                            completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
            dispatch_semaphore_signal(self.concurrencyLock);

            if (error || !data) {
                if (completion) completion(NO, error);
                return;
            }

            NSHTTPURLResponse *http = (NSHTTPURLResponse *)response;
            if (http.statusCode < 200 || http.statusCode >= 300) {
                NSError *statusError = [NSError errorWithDomain:@"R34BatchDownloader"
                                                          code:http.statusCode
                                                      userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"HTTP %ld", (long)http.statusCode]}];
                if (completion) completion(NO, statusError);
                return;
            }

            NSError *writeError = nil;
            BOOL written = [data writeToURL:fileURL options:NSDataWritingAtomic error:&writeError];
            if (completion) completion(written, writeError);
        }];

        [task resume];
    });
}

- (void)cancelAll {
    [self.downloadQueue cancelAllOperations];
    [[R34NetworkManager optimizedSession] getTasksWithCompletionHandler:^(NSArray *dataTasks, NSArray *uploadTasks, NSArray *downloadTasks) {
        for (NSURLSessionDataTask *task in dataTasks) {
            [task cancel];
        }
    }];
}

@end
