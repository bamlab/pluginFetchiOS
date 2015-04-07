#import <Foundation/Foundation.h>
#import <Cordova/CDV.h>

@interface FPFetchPlugin : CDVPlugin <NSURLSessionDownloadDelegate>

@property (nonatomic) NSString * fetchAndProcessJsonFilesCommandCallbackId;
@property (nonatomic) NSURLSession * fetchAndProcessJsonFilesDownloadSession;
@property (nonatomic) NSString * fetchAndProcessTilesFilesCommandCallbackId;
@property (nonatomic) NSURLSession * fetchAndProcessTilesFilesDownloadSession;
@property (nonatomic) NSMutableDictionary * responseDict;
@property (nonatomic) NSArray * arguments;
- (void)fetchAndProcessJsonFiles:(CDVInvokedUrlCommand*)command;
- (void)fetchAndProcessTilesFiles:(CDVInvokedUrlCommand*)command;
@end