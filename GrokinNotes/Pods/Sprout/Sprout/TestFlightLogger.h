//
//  TestFlightLogger.h
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

#import <Foundation/Foundation.h>

#import "DDLog.h"

@interface TestFlightLogger : DDAbstractLogger <DDLogger>

+ (TestFlightLogger *)sharedInstance;

// Inherited from DDAbstractLogger

// - (id <DDLogFormatter>)logFormatter;
// - (void)setLogFormatter:(id <DDLogFormatter>)formatter;

@end
