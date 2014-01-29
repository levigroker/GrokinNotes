//
//  TestFlightManager.m
//  GrokinNotes
//
//  Created by Levi Brown on 1/16/14.
//  Copyright (c) 2014 Levi Brown. All rights reserved.
//

#import "TestFlightManager.h"
#ifdef TESTFLIGHT
#import "TestFlight.h"
#endif

static NSString * const kTestFlightConfigurationPList = @"TestFlightConfiguration";
static NSString * const kTestFlightConfigurationKeyEnabled = @"enabled";
static NSString * const kTestFlightConfigurationKeyAppToken = @"app_token";

@implementation TestFlightManager

#pragma mark - Class Level

+ (void)startup
{
    //Currently no need to keep ourselves around, so just perform the startup and go away.
    [[[self alloc] init] startup];
}

#pragma mark - Implementation

- (void)startup
{
#ifdef TESTFLIGHT
    NSString *configPath = [[NSBundle mainBundle] pathForResource:kTestFlightConfigurationPList ofType:@"plist"];
    DDLogVerbose(@"%@", configPath.length > 0 ? @"Found TestFlight configuration." : [NSString stringWithFormat:@"No TestFlight configuration plist ('%@.plist') found in the main bundle. TestFlight will not be enabled.", kTestFlightConfigurationPList]);
    NSDictionary *config = [NSDictionary dictionaryWithContentsOfFile:configPath];
    BOOL enabled = [[config objectForKey:kTestFlightConfigurationKeyEnabled] boolValue];
    NSString *appToken = [config valueForKey:kTestFlightConfigurationKeyAppToken];
    DDLogVerbose(@"TestFlight is %@enabled with%@ an app token.", enabled ? @"" : @"not ", appToken.length > 0 ? @"" : @"out");
    if (enabled && appToken.length > 0)
    {
        [TestFlight takeOff:appToken];
    }
#else
    DDLogVerbose(@"TestFlight disabled at compile-time.");
#endif
}

@end
