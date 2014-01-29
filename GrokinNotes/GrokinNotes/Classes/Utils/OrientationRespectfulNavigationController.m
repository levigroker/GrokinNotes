//
//  OrientationRespectfulNavigationController.m
//
//  Created by Levi Brown on 11/15/12. @levigroker
//  This work is licensed under a Creative Commons Attribution 3.0 Unported License
//  http://creativecommons.org/licenses/by/3.0/
//  Attribution to Levi Brown (@levigroker) is appreciated but not required.
//

/*
 This NavigationController will query it's topmost view controller for desired rotation behavior,
 unlike the default implementation.

 From the iOS 6 release notes:
 http://developer.apple.com/library/ios/#releasenotes/General/RN-iOSSDK-6_0/_index.html

 Now, iOS containers (such as UINavigationController) do not consult their children to
 determine whether they should autorotate. By default, an app and a view controller’s
 supported interface orientations are set to UIInterfaceOrientationMaskAll for the iPad
 idiom and UIInterfaceOrientationMaskAllButUpsideDown for the iPhone idiom.
 */

#import "OrientationRespectfulNavigationController.h"

@implementation OrientationRespectfulNavigationController

- (BOOL)shouldAutorotate
{
    return [self.topViewController shouldAutorotate];
}

- (NSUInteger)supportedInterfaceOrientations
{
    return [self.topViewController supportedInterfaceOrientations];
}

- (UIInterfaceOrientation)preferredInterfaceOrientationForPresentation
{
    return [self.topViewController preferredInterfaceOrientationForPresentation];
}

@end
