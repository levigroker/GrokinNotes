//
//  TestFlightLogger.m
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

#import "TestFlightLogger.h"

#ifdef TESTFLIGHT
#import "TestFlight.h"
#endif

@implementation TestFlightLogger

+ (TestFlightLogger *)sharedInstance
{
    static dispatch_once_t onceQueue;
    static TestFlightLogger *testFlightLogger = nil;
    
    dispatch_once(&onceQueue, ^{ testFlightLogger = [[self alloc] init]; });
    return testFlightLogger;
}

- (void)logMessage:(DDLogMessage *)logMessage
{
#ifdef TESTFLIGHT
	NSString *logMsg = logMessage->logMsg;
	
	if (formatter)
	{
		logMsg = [formatter formatLogMessage:logMessage];
	}
	
	if (logMsg)
	{
        TFLog(@"%@", logMsg);
	}
#endif
}

- (NSString *)loggerName
{
	return @"cocoa.lumberjack.testFlightLogger";
}

@end
