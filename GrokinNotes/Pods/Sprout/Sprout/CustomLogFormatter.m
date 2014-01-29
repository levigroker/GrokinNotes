//
//  CustomLogFormatter.m
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

#import "CustomLogFormatter.h"

@implementation CustomLogFormatter

- (id)init
{
    if ((self = [super init]))
    {
        self.dateFormatter = [[NSDateFormatter alloc] init];
        [self.dateFormatter setFormatterBehavior:NSDateFormatterBehavior10_4];
        [self.dateFormatter setDateFormat:@"yyyy-MM-dd HH:mm:ss:SSS"];
    }
    return self;
}

- (NSString *)formatLogMessage:(DDLogMessage *)logMessage
{
    NSString *logLevel = nil;
    switch (logMessage->logFlag)
    {
        case LOG_FLAG_ERROR : logLevel = @"[ERROR]"; break;
        case LOG_FLAG_WARN  : logLevel = @" [WARN]"; break;
        case LOG_FLAG_INFO  : logLevel = @" [INfO]"; break;
        default             : logLevel = @"[DEBUG]"; break;
    }
    NSString *file = [NSString stringWithCString:logMessage->file encoding:NSASCIIStringEncoding];
    file = [file lastPathComponent];
    NSString *function = [NSString stringWithCString:logMessage->function encoding:NSASCIIStringEncoding];
    NSString *timestamp = [self.dateFormatter stringFromDate:(logMessage->timestamp)];

    char tidCStr[9];
    int tidLen = snprintf(tidCStr, 9, "%x", logMessage->machThreadID);
    NSString *threadID = [NSString stringWithCString:tidCStr encoding:NSASCIIStringEncoding];
    threadID = [threadID substringToIndex:MIN((size_t)8, tidLen)];

	return [NSString stringWithFormat:@"%@         <%@> %@(%@ %d)\n%@ %@ %@", timestamp, threadID, function, file, logMessage->lineNumber, timestamp, logLevel, logMessage->logMsg];
}

@end
