//
//  Sprout.h
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

/**
 Sprout is used to bootstrap the (excellent) CocoaLumberjack https://github.com/robbiehanson/CocoaLumberjack logging framework.
 
 In the simplest case, setup is just:
 
 - Add `Sprout.h` to your precompiled header:
 
        #ifdef __OBJC__
        #import <Foundation/Foundation.h>
        //Third Party
        #import "Sprout.h"
        #endif
 
 - Start Logging in your `application:didFinishLaunchingWithOptions:` UIApplicationDelegate
 
        - (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions
        {
            //Initialize logging
            [[Sprout sharedInstance] startLogging];
            //. . .
 
 - Define `DEBUG`
 In your Preprocessor Macros target build settings, define `DEBUG=1` (this may not be needed, as it is a default setting in later XCode project templates).
 
 - Run!
 After the above setup, you should be able to run and see:
 
        CocoaLumberjack loggers initialized!
 
 appear in your console.
 
 To use with TestFlight http://testflightapp.com :
 
 If you `#define TESTFLIGHT` (or define TESTFLIGHT in your build settings), Sprout will add the `TestFlightLogger` to send log messages to the `TFLog` TestFlight SDK logger at your current log level.
 @warning If you define `TESTFLIGHT` you must have libTestFlight.a linked or you'll get a linker error (see https://testflightapp.com/sdk/doc/ for information on installing TestFlight)
 @warning If you're using TestFlight you should initialize Sprout before calling `TestFlight takeOff:`
 */

#ifndef _SPROUT_H
#define _SPROUT_H

#import <Foundation/Foundation.h>

#import "DDLog.h"
#import "DDFileLogger.h"
#import "DDTTYLogger.h"

//Set the logging level and optional loggers

#define SPROUT_FILE_LOGGING

#ifdef DEBUG
    #ifndef SPROUT_DISABLE_DYNAMIC_LOG_LEVEL
        static int ddLogLevel = LOG_LEVEL_VERBOSE;
    #else
        static const int ddLogLevel = LOG_LEVEL_VERBOSE;
    #endif
    #define SPROUT_CONSOLE_LOGGING
#else
    #ifndef SPROUT_DISABLE_DYNAMIC_LOG_LEVEL
        static int ddLogLevel = LOG_LEVEL_WARN;
    #else
        static const int ddLogLevel = LOG_LEVEL_WARN;
    #endif
#endif

#ifdef TESTFLIGHT
    #define SPROUT_TESTFLIGHT_LOGGING
#endif

@interface Sprout : NSObject

/**
 * @return `YES` if Sprout has configured CocoaLumberjack
 */
@property (nonatomic,assign,readonly) BOOL started;
/**
 * @return The `DDFileLogger` used to write log statements to files.
 */
@property (nonatomic,strong,readonly) DDFileLogger *fileLogger;
/**
 * @return The `DDTTYLogger` used to write log statements to the console.
 */
@property (nonatomic,strong,readonly) DDTTYLogger *ttyLogger;
/**
 * @return The `NSFileManager` used to perform file based operations.
 */
@property (nonatomic,strong,readonly) NSFileManager *fileManager;

/**
 * @return The singleton instance of `Sprout`
 */
+ (Sprout *)sharedInstance;
/**
 * Configures CocoaLumberjack for logging, and attaches signal handlers, etc.
 * After this is called, `started` will be `YES`
 */
- (void)startLogging;
#ifndef SPROUT_DISABLE_DYNAMIC_LOG_LEVEL
/**
 * Sets the logging level to that specified.
 * @param logLevel The new log level to be used. Takes affect immediately.
 * @warning If `SPROUT_DISABLE_DYNAMIC_LOG_LEVEL` is defined, this functionality is disabled.
 * @see https://github.com/robbiehanson/CocoaLumberjack/wiki/DynamicLogLevels
 * Default CocoaLumberjack has these log levels defined:
 *
 *   LOG_LEVEL_OFF
 *   LOG_LEVEL_ERROR
 *   LOG_LEVEL_WARN
 *   LOG_LEVEL_INFO
 *   LOG_LEVEL_VERBOSE
 */
- (void)setLogLevel:(int)logLevel;
#endif
/**
 * Outputs a log statement at LOG_LEVEL_INFO with the app name, bundle identifier, versions (CFBundleShortVersionString and CFBundleVersion), device model, OS name and version.
 */
- (void)logAppAndDeviceInfo;
/**
 * @return All file logs as an `NSData` representing a zip archive of the log files.
 */
- (NSData *)logsAsZippedData;
/**
 * @return An `NSArray` of `NSString` objects containing the full path to the most recent (up to 10) log files.
 */
- (NSArray *)logFiles;

//Setup various loggers (primarity for subclasses to override)
/**
 * Setup the console (TTY) logger
 */
- (void)setupTTYLogger;
/**
 * Setup the File logger
 */
- (void)setupFileLogger;
/**
 * Setup the TestsFlight logger
 */
- (void)setupTestFlightLogger;
/**
 * Setup any additional loggers. Meant for subclasses to override. Current implementation does nothing.
 */
- (void)setupAdditionalLoggers;

//Helper implementation
+ (NSString *)backtraceSkipping:(int)skip length:(int)length;
- (NSString *)tempDirectory;
- (NSString *)UUID;

@end

#endif /* _SPROUT_H */
