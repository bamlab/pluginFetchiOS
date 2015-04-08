#import "FPFetchPlugin.h"
#import "NSData+Base64.h"

@interface FPFetchPlugin (Private)
- (void)_startJsonDownload:(NSArray *)arguments;
- (void)_startTilesDownload:(NSArray *)arguments;
- (NSURLSession *)_downloadSessionForId:(NSString *)sessionId;
- (void)_startTasksWithSession:(NSURLSession *)session arguments:(NSArray *)arguments;
- (void)_sendError:(NSString *)callbackId;
- (void)_checkDictEnd:(NSURLSession *)session;
@end

@implementation FPFetchPlugin

-(void)fetchAndProcessJsonFiles:(CDVInvokedUrlCommand *)command {
    self.fetchAndProcessJsonFilesCommandCallbackId = command.callbackId;
    [self.commandDelegate runInBackground:^{
        [self _startJsonDownload:command.arguments];
    }];
}

-(void)fetchAndProcessTilesFiles:(CDVInvokedUrlCommand *)command {
    self.fetchAndProcessTilesFilesCommandCallbackId = command.callbackId;
    [self.commandDelegate runInBackground:^{
        [self _startTilesDownload:command.arguments];
    }];
}

- (void)URLSession:(NSURLSession *)session downloadTask:(NSURLSessionDownloadTask *)downloadTask didFinishDownloadingToURL:(NSURL *)location {
    NSFileManager * fileManager = [NSFileManager defaultManager];
    if (location) {
        if (fileManager) {
            if ([downloadTask originalRequest] && [[downloadTask originalRequest] URL] && [[[downloadTask originalRequest] URL] absoluteString]) {
                NSURL * libDirectory = [fileManager URLsForDirectory:NSLibraryDirectory inDomains:NSUserDomainMask][0];
                NSString * chunckFileName = [[[downloadTask originalRequest] URL] lastPathComponent];
                NSURL * chunckPath = [libDirectory URLByAppendingPathComponent:chunckFileName];
                [fileManager removeItemAtURL:chunckPath error:NULL];
                [fileManager copyItemAtURL:location toURL:chunckPath error:NULL];
                [self.responseDict setObject:[chunckPath path] forKey:[[[downloadTask originalRequest] URL] absoluteString]];
                [self _checkDictEnd:session];
            }
            return;
        }
    }
    [self _sendError:self.fetchAndProcessJsonFilesDownloadSession == session ? self.fetchAndProcessJsonFilesCommandCallbackId : self.fetchAndProcessTilesFilesCommandCallbackId];
}

- (void)URLSession:(NSURLSession *)session downloadTask:(NSURLSessionDownloadTask *)downloadTask didWriteData:(int64_t)bytesWritten totalBytesWritten:(int64_t)totalBytesWritten totalBytesExpectedToWrite:(int64_t)totalBytesExpectedToWrite {
    NSLog(@"Progress : %lli/%lli", totalBytesWritten, totalBytesExpectedToWrite);
}

@end

@implementation FPFetchPlugin (Private)

- (void)_startJsonDownload:(NSArray *)arguments {
    self.fetchAndProcessJsonFilesDownloadSession = [self _downloadSessionForId:@"fr.bamlab.bigfetch.fetchplugin.fetchAndProcessJson"];
    if (self.fetchAndProcessJsonFilesDownloadSession && arguments) {
        [self _startTasksWithSession:self.fetchAndProcessJsonFilesDownloadSession arguments:arguments];
    }
}

- (void)_startTilesDownload:(NSArray *)arguments {
    self.fetchAndProcessTilesFilesDownloadSession = [self _downloadSessionForId:@"fr.bamlab.bigfetch.fetchplugin.fetchAndProcessTiles"];
    if (self.fetchAndProcessTilesFilesDownloadSession && arguments) {
        [self _startTasksWithSession:self.fetchAndProcessTilesFilesDownloadSession arguments:arguments];
    }
}

- (void)_startTasksWithSession:(NSURLSession *)session arguments:(NSArray *)arguments {
    self.responseDict = [[NSMutableDictionary alloc] init];
    self.arguments = [NSArray arrayWithArray:arguments];
    for (NSString * chunckURLString in arguments) {
        NSURLRequest * request = [NSURLRequest requestWithURL:[NSURL URLWithString:chunckURLString]];
        NSURLSessionDownloadTask * downloadTask = [session downloadTaskWithRequest:request];
        [downloadTask resume];
    }
}

- (NSURLSession *)_downloadSessionForId:(NSString *)sessionId {
    if (sessionId) {
        NSURLSessionConfiguration * config = [NSURLSessionConfiguration backgroundSessionConfigurationWithIdentifier:sessionId];
        return [NSURLSession sessionWithConfiguration:config delegate:self delegateQueue:[NSOperationQueue mainQueue]];
    }
    return nil;
}

- (void)_sendError:(NSString *)callbackId {
    if (callbackId) {
        CDVPluginResult * pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR];
        [self.commandDelegate sendPluginResult:pluginResult callbackId:callbackId];
    }
}

- (void)_checkDictEnd:(NSURLSession *)session {
    NSLog(@"%lu", (unsigned long)[self.responseDict count]);
    if ([self.arguments count] == [self.responseDict count]) {
        NSFileManager * fileManager = [NSFileManager defaultManager];
        NSMutableData * responseData = [[NSMutableData alloc] init];
        for (NSString * chunkUrl in self.arguments) {
            NSData * retrievedData = [fileManager contentsAtPath:[self.responseDict objectForKey:chunkUrl]];
            [responseData appendData:retrievedData];
            [fileManager removeItemAtPath:[self.responseDict objectForKey:chunkUrl] error:NULL];
        }
        self.responseDict = nil;
        NSError * error;
        NSDictionary * jsonDict = [NSJSONSerialization JSONObjectWithData:responseData
                                                                  options:session == self.fetchAndProcessJsonFilesDownloadSession ? NSJSONReadingMutableContainers : 0
                                                                    error:&error];
        if ([jsonDict isKindOfClass:[NSDictionary class]]) {
            if (session == self.fetchAndProcessJsonFilesDownloadSession) {
                if ([jsonDict objectForKey:@"places"]) {
                    for (NSDictionary * placeDict in [jsonDict objectForKey:@"places"]) {
                        if ([placeDict objectForKey:@"picture"]  && [[placeDict objectForKey:@"picture"] objectForKey:@"url"]) {
                            NSString * imageString = [[placeDict objectForKey:@"picture"] objectForKey:@"url"];
                            imageString = [imageString stringByReplacingOccurrencesOfString:@"data:image/png;base64," withString:@""];
                            NSData * imageData = [[NSData alloc] initWithBase64Encoding:imageString];
                            NSURL * libDirectory = [fileManager URLsForDirectory:NSLibraryDirectory inDomains:NSUserDomainMask][0];
                            NSURL * noCloudURL = [libDirectory URLByAppendingPathComponent:@"NoCloud"];
                            NSError * dirExistsError = nil;
                            if (![fileManager fileExistsAtPath:[noCloudURL path]]) {
                                [fileManager createDirectoryAtPath:[noCloudURL path] withIntermediateDirectories:NO attributes:nil error:&dirExistsError];
                            }
                            NSString * placeFileName = [NSString stringWithFormat:@"place_%@", [placeDict objectForKey:@"objectId"]];
                            NSURL * placePath = [noCloudURL URLByAppendingPathComponent:placeFileName];
                            [fileManager removeItemAtURL:placePath error:NULL];
                            [imageData writeToURL:placePath atomically:NO];
                            [[placeDict objectForKey:@"picture"] setObject:[placePath path] forKey:@"url"];
                        }
                    }
                }
                NSData * jsonData =[NSJSONSerialization dataWithJSONObject:jsonDict options:0 error:NULL];
                NSString * jsonString = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
                CDVPluginResult * pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:jsonString];
                [self.commandDelegate sendPluginResult:pluginResult callbackId:self.fetchAndProcessJsonFilesCommandCallbackId];
                return;
            } else {
                if ([jsonDict objectForKey:@"maptile"]) {
                    for (NSDictionary * tileDict in [jsonDict objectForKey:@"maptile"]) {
                        if ([tileDict objectForKey:@"tileFile"]  && [[tileDict objectForKey:@"tileFile"] objectForKey:@"url"]) {
                            NSString * imageString = [[tileDict objectForKey:@"tileFile"] objectForKey:@"url"];
                            imageString = [imageString stringByReplacingOccurrencesOfString:@"data:image/png;base64," withString:@""];
                            NSData * imageData = [[NSData alloc] initWithBase64Encoding:imageString];
                            NSURL * libDirectory = [fileManager URLsForDirectory:NSLibraryDirectory inDomains:NSUserDomainMask][0];
                            NSURL * noCloudURL = [libDirectory URLByAppendingPathComponent:@"NoCloud"];
                            NSError * dirExistsError = nil;
                            if (![fileManager fileExistsAtPath:[noCloudURL path]]) {
                                [fileManager createDirectoryAtPath:[noCloudURL path] withIntermediateDirectories:NO attributes:nil error:&dirExistsError];
                            }
                            NSString * tileFileName = [NSString stringWithFormat:@"tile_%ld_%ld_%ld.png", (long)[[tileDict objectForKey:@"zoom"] integerValue], (long)[[tileDict objectForKey:@"x"] integerValue], (long)[[tileDict objectForKey:@"y"] integerValue]];
                            NSURL * tilePath = [noCloudURL URLByAppendingPathComponent:tileFileName];
                            [fileManager removeItemAtURL:tilePath error:NULL];
                            [imageData writeToURL:tilePath atomically:NO];
                        }
                    }
                    CDVPluginResult * pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:@"Tiles stored locally!"];
                    [self.commandDelegate sendPluginResult:pluginResult callbackId:self.fetchAndProcessTilesFilesCommandCallbackId];
                    return;
                }
            }
            [self _sendError:self.fetchAndProcessJsonFilesDownloadSession == session ? self.fetchAndProcessJsonFilesCommandCallbackId : self.fetchAndProcessTilesFilesCommandCallbackId];
        }
    }
}

@end