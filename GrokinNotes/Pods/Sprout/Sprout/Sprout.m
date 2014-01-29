//
//  Sprout.m
//
//  Created by Levi Brown on 10/4/12.
//  Copyright (c) 2012, 2013 Levi Brown <mailto:levigroker@gmail.com>
//  This work is licensed under the Creative Commons Attribution 3.0
//  Unported License. To view a copy of this license, visit
//  http://creativecommons.org/licenses/by/3.0/ or send a letter to Creative
//  Commons, 444 Castro Street, Suite 900, Mountain View, California, 94041,
//  USA.
//
//  The above attribution and the included license must accompany any version
//  of the source code. Visible attribution in any binary distributable
//  including this work (or derivatives) is not required, but would be
//  appreciated.
//

#include <execinfo.h>
#import <UIKit/UIKit.h>
#import "Sprout.h"
#import "CustomLogFormatter.h"
#import "SSZipArchive.h"

#ifdef TESTFLIGHT
#import "TestFlightLogger.h"
#endif

#define DDLogException(frmt, ...)   LOG_MAYBE(LOG_ASYNC_ERROR, ddLogLevel, LOG_FLAG_ERROR, 0, "Exception Handler", frmt, ##__VA_ARGS__)
#define DDLogSignal(frmt, ...)   LOG_MAYBE(LOG_ASYNC_ERROR, ddLogLevel, LOG_FLAG_ERROR, 0, "Signal Handler", frmt, ##__VA_ARGS__)

void exceptionHandler(NSException *exception);
void signalHandler(int signal);

@interface Sprout ()

@property (nonatomic,assign) BOOL started;
@property (nonatomic,strong) DDFileLogger *fileLogger;
@property (nonatomic,strong) DDTTYLogger *ttyLogger;
@property (nonatomic,strong) NSFileManager *fileManager;

@end

void exceptionHandler(NSException *exception)
{
    DDLogException(@"Exception: %@\nCall stack:\n%@", exception, [exception callStackSymbols]);
}

void signalHandler(int signal)
{
    NSString *signalSring = @"unknown";
    switch (signal)
    {
        case SIGABRT:
            signalSring = @"SIGABRT";
            break;
        case SIGILL:
            signalSring = @"SIGILL";
            break;
        case SIGBUS:
            signalSring = @"SIGBUS";
            break;
        case SIGSEGV:
            signalSring = @"SIGSEGV";
            break;
        default:
            break;
    }
    NSString *backtrace = [Sprout backtraceSkipping:2 /* Skip the backrace method and this signal handler */ length:20 /* Get the next 20 stack frames */];
    DDLogSignal(@"Recieved %@ signal. Call stack:\n%@", signalSring, backtrace);
}

@implementation Sprout

#pragma mark - Lifecycle

+ (Sprout *)sharedInstance
{
    static dispatch_once_t onceQueue;
    static Sprout *sprout = nil;
    
    dispatch_once(&onceQueue, ^{ sprout = [[self alloc] init]; });
    return sprout;
}

- (id)init
{
    if ((self = [super init]))
    {
        self.fileManager = [[NSFileManager alloc] init];
    }
    
    return self;
}

#pragma mark Class Level

//Original concept and code from http://www.cocoawithlove.com/2010/05/handling-unhandled-exceptions-and.html
//Since modified
+ (NSString *)backtraceSkipping:(int)skip length:(int)length
{
    void* callstack[128];
    int frames = backtrace(callstack, 128);
    char **strs = backtrace_symbols(callstack, frames);
    
    NSMutableArray *backtrace = [NSMutableArray arrayWithCapacity:frames];
    for (int i = skip; i < skip + length; ++i)
    {
        [backtrace addObject:[NSString stringWithUTF8String:strs[i]]];
    }
    free(strs);
    
    NSString *retVal = [backtrace componentsJoinedByString:@"\n"];
    return retVal;
}

#pragma mark - Implementation

- (void)startLogging
{
    if (!self.started)
    {
        //Initialize logging
        
        //Register our handler for uncaught exceptions
        NSSetUncaughtExceptionHandler(&exceptionHandler);
        
        //Register our handler for signals
        
        //Create the signal action structure
        struct sigaction signalAction;
        //Initialize the signal action structure
        memset(&signalAction, 0, sizeof(signalAction));
        //Set 'signalHandler' as the handler in the signal action structure
        signalAction.sa_handler = &signalHandler;
        //Set 'signalHandler' as the handlers for SIGABRT, SIGILL and SIGBUS
        sigaction(SIGABRT, &signalAction, NULL);
        sigaction(SIGILL, &signalAction, NULL);
        sigaction(SIGBUS, &signalAction, NULL);
        sigaction(SIGSEGV, &signalAction, NULL);
        
        [self setupTTYLogger];
        [self setupFileLogger];
        [self setupTestFlightLogger];
        [self setupAdditionalLoggers];
        
        DDLogInfo(@"CocoaLumberjack loggers initialized!");
        
        self.started = YES;
    }
}

#ifndef SPROUT_DISABLE_DYNAMIC_LOG_LEVEL
- (void)setLogLevel:(int)logLevel
{
    ddLogLevel = logLevel;
}
#endif

- (void)logAppAndDeviceInfo
{
    NSString *appName = [self appName];
    NSString *appVersion = [self appVersion];
    NSString *appIdentifier = [self appIdentifier];
    NSString *appBuildNumber = [self appBuildNumber];
    NSString *deviceModel = [UIDevice currentDevice].model;
    NSString *systemName = [UIDevice currentDevice].systemName;
    NSString *systemVersion = [UIDevice currentDevice].systemVersion;
    
    DDLogInfo(@"%@ %@ (%@ %@) %@, %@ %@", appName, appVersion, appIdentifier, appBuildNumber, deviceModel, systemName, systemVersion);
}

- (NSData *)logsAsZippedData
{
    NSData *retVal = nil;
#ifdef _SSZIPARCHIVE_H
    NSString *tempDir = [self tempDirectory];
    if (tempDir)
    {
        NSString *tempFile = [tempDir stringByAppendingPathComponent:[self UUID]];
        NSArray *logFiles = [self logFiles];
        if ([SSZipArchive createZipFileAtPath:tempFile withFilesAtPaths:logFiles])
        {
            //Read the temp zip file into memory
            retVal = [NSData dataWithContentsOfFile:tempFile];
            //Delete the temp directory and contents
            [self.fileManager removeItemAtPath:tempDir error:nil];
        }
    }
#else
#warning SSZipArchive framework not found in project, or not included in precompiled header. `logsAsZippedData` will return `nil`.
#endif
    
    return retVal;
}

- (NSArray *)logFiles
{
    NSUInteger maximumLogFilesToReturn = MIN(self.fileLogger.logFileManager.maximumNumberOfLogFiles, 10);
    NSMutableArray *logFiles = [NSMutableArray arrayWithCapacity:maximumLogFilesToReturn];
    NSArray *sortedLogFileInfos = [self.fileLogger.logFileManager sortedLogFileInfos];
    for (int i = 0; i < MIN(sortedLogFileInfos.count, maximumLogFilesToReturn); ++i)
    {
        DDLogFileInfo *logFileInfo = [sortedLogFileInfos objectAtIndex:i];
        NSString *logFile = logFileInfo.filePath;
        if (logFile)
        {
            [logFiles addObject:logFile];
        }
    }
    return logFiles;
}

#pragma mark - Logging Setup

- (void)setupTTYLogger
{
    #ifdef SPROUT_CONSOLE_LOGGING
    //Console
    self.ttyLogger = [DDTTYLogger sharedInstance];
    CustomLogFormatter *ttyFormatter = [[CustomLogFormatter alloc] init];
    [self.ttyLogger setLogFormatter:ttyFormatter];
    [self.ttyLogger setColorsEnabled:YES];
    [DDLog addLogger:self.ttyLogger];
    #endif
}

- (void)setupFileLogger
{
    #ifdef SPROUT_FILE_LOGGING
    //File logging
    self.fileLogger = [[DDFileLogger alloc] init];
    self.fileLogger.rollingFrequency = 60 * 60 * 24; // 24 hour rolling
    self.fileLogger.logFileManager.maximumNumberOfLogFiles = 7;
    CustomLogFormatter *fileFormatter = [[CustomLogFormatter alloc] init];
    [self.fileLogger setLogFormatter:fileFormatter];
    [DDLog addLogger:self.fileLogger];
    #endif
}

- (void)setupTestFlightLogger
{
    #ifdef SPROUT_TESTFLIGHT_LOGGING
    //File logging
    self.fileLogger = [[DDFileLogger alloc] init];
    self.fileLogger.rollingFrequency = 60 * 60 * 24; // 24 hour rolling
    self.fileLogger.logFileManager.maximumNumberOfLogFiles = 7;
    CustomLogFormatter *fileFormatter = [[CustomLogFormatter alloc] init];
    [self.fileLogger setLogFormatter:fileFormatter];
    [DDLog addLogger:self.fileLogger];
    #endif
}

- (void)setupAdditionalLoggers
{
    //No implementation here; just for subclasses
}

#pragma mark - Helpers

- (NSString *)appVersion
{
    NSString *retVal = [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleShortVersionString"];
    return retVal;
}

- (NSString *)appBuildNumber
{
    NSString *retVal = [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleVersion"];
    return retVal;
}

- (NSString *)appName
{
    NSDictionary *info = [[NSBundle mainBundle] infoDictionary];
    NSString *name = [info objectForKey:@"CFBundleDisplayName"];
    if (!name)
    {
        name = [info objectForKey:@"CFBundleName"];
    }

    return name;
}

- (NSString *)appIdentifier
{
    NSString *retVal = [[NSBundle mainBundle] bundleIdentifier];
    return retVal;
}

- (NSString *)tempDirectory
{
    //Modified from: http://cocoawithlove.com/2009/07/temporary-files-and-folders-in-cocoa.html
    
    NSString *retVal = nil;
    
    NSString *tempDirectoryTemplate = [NSTemporaryDirectory() stringByAppendingPathComponent:[self UUID]];
    const char *tempDirectoryTemplateCString = [tempDirectoryTemplate fileSystemRepresentation];
    char *tempDirectoryNameCString = (char *)malloc(strlen(tempDirectoryTemplateCString) + 1);
    strcpy(tempDirectoryNameCString, tempDirectoryTemplateCString);
    
    char *result = mkdtemp(tempDirectoryNameCString);
    if (result)
    {
        retVal = [self.fileManager stringWithFileSystemRepresentation:tempDirectoryNameCString length:strlen(result)];
    }
    
    free(tempDirectoryNameCString);
    
    return retVal;
}

- (NSString *)UUID
{
    CFUUIDRef uuidRef = CFUUIDCreate(NULL);
    CFStringRef stringRef = CFUUIDCreateString(NULL, uuidRef);
    CFRelease(uuidRef);
    NSString *retVal = (NSString *)CFBridgingRelease(stringRef);
    return retVal;
}

@end

