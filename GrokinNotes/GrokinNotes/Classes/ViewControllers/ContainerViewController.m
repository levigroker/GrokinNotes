//
//  ContainerViewController.m
//  GrokinNotes
//
//  Created by Levi Brown on 1/16/14.
//  Copyright (c) 2014 Levi Brown. All rights reserved.
//

#import "ContainerViewController.h"
#import "MainViewController.h"
#import "MenuViewController.h"

static NSString * const kSegueMain = @"main";

static CGFloat const kRevealPercentage = 0.8;
static NSTimeInterval const kRevealAnimationDuration = 0.25;

@interface ContainerViewController ()

@property (nonatomic,weak) IBOutlet NSLayoutConstraint *mainViewControllerXOffsetContstraint;
@property (nonatomic,weak) MainViewController *mainViewController;
@property (nonatomic,strong) MenuViewController *menuViewController;

@end

@implementation ContainerViewController

#pragma mark - Status Bar

- (UIStatusBarStyle)preferredStatusBarStyle
{
    return UIStatusBarStyleDefault;
}

#pragma mark - Rotation Handling

- (BOOL)shouldAutorotate
{
    return NO;
}

- (NSUInteger)supportedInterfaceOrientations
{
    return UIInterfaceOrientationMaskPortrait;
}

#pragma mark - Segue

- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender
{
    NSString *identifier = segue.identifier;
    if ([identifier isEqual:kSegueMain])
    {
        //Get a reference to the main view controller and configure it as it gets embedded.
        id obj = segue.destinationViewController;
        if ([obj isKindOfClass:UINavigationController.class])
        {
            UINavigationController *nav = (UINavigationController *)obj;

            //Add a pan gesture recognizer to handle menu reveals
            UIPanGestureRecognizer *panRecognizer = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePanGesture:)];
            [panRecognizer setMinimumNumberOfTouches:1];
            [panRecognizer setMaximumNumberOfTouches:1];
            [nav.navigationBar addGestureRecognizer:panRecognizer];

            id root = [nav.viewControllers firstObject];
            if ([root isKindOfClass:MainViewController.class])
            {
                self.mainViewController = (MainViewController *)root;
                
                //Add ourselves as the handler for menu actions
                self.mainViewController.menuActionHandler = self;
            }
            else
            {
                DDLogError(@"Root view controller is of unexpected type: %@", root);
            }
        }
        else
        {
            DDLogError(@"Seque '%@' is of unexpected type: %@", identifier, obj);
        }
    }
}

#pragma mark - Layout

- (void)setMainViewControllerOffset:(CGFloat)offset animationDuration:(NSTimeInterval)duration completion:(void(^)(void))completion
{
    self.mainViewControllerXOffsetContstraint.constant = offset;
    [self.view setNeedsUpdateConstraints];
    [UIView animateWithDuration:duration delay:0.0f options:UIViewAnimationOptionCurveLinear animations:^{
        [self.view layoutIfNeeded];
    } completion:^(BOOL finished) {
        if (completion)
        {
            completion();
        }
    }];
}

#pragma mark - Menu View Controller

- (void)addMenuViewController
{
    if (self.menuViewController)
    {
        [self removeMenuViewController];
    }
    
    //NOTE: Assumes the storyboard identifier is the same as the classname
    MenuViewController *viewController = [self.storyboard instantiateViewControllerWithIdentifier:NSStringFromClass(MenuViewController.class)];
    self.menuViewController = viewController;

    [self addChildViewController:viewController];
    [self.view insertSubview:viewController.view atIndex:0];
    [viewController didMoveToParentViewController:self];
    
    //Setup constraints to keep the new view pinned to our size.
    UIView *containedView = viewController.view;
    containedView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|[containedView]|" options:0 metrics:nil views:NSDictionaryOfVariableBindings(containedView)]];
    [self.view addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|[containedView]|" options:0 metrics:nil views:NSDictionaryOfVariableBindings(containedView)]];
}

- (void)removeMenuViewController
{
    [self.menuViewController willMoveToParentViewController:nil];
    [self.menuViewController.view removeFromSuperview];
    [self.menuViewController removeFromParentViewController];
    self.menuViewController = nil;
}

#pragma mark - Pan Gesture Handling

- (void)handlePanGesture:(UIPanGestureRecognizer *)panGesture
{
    CGPoint translatedPoint = [panGesture translationInView:self.view];
    
    switch (panGesture.state) {
        case UIGestureRecognizerStateBegan:
        {
            //If we will be showing the menu, then we must create and add it
            if (self.mainViewControllerXOffsetContstraint.constant == 0.0f)
            {
                [self addMenuViewController];
            }
            break;
        }
        case UIGestureRecognizerStateChanged:
        {
            //Only allow the main view to be pushed to the right (no negative x offsets allowed).
            CGFloat finalXOffset = MAX(0, self.mainViewControllerXOffsetContstraint.constant + translatedPoint.x);
            [self setMainViewControllerOffset:finalXOffset animationDuration:0.0f completion:nil];
            [panGesture setTranslation:CGPointZero inView:self.view];
            break;
        }
        case UIGestureRecognizerStateEnded:
        {
            CGFloat width = self.mainViewController.view.bounds.size.width;
            CGFloat halfWidth = width / 2.0f;
            CGFloat currentXOffset = self.mainViewControllerXOffsetContstraint.constant;
            CGFloat finalXOffset = 0.0f; //Default to no offset
            CGFloat durationPercentage;
            
            if (currentXOffset > halfWidth)
            {
                //Over half way, so complete the reveal
                finalXOffset = kRevealPercentage * width;
                durationPercentage = (finalXOffset - currentXOffset) / (finalXOffset - halfWidth);
            }
            else
            {
                durationPercentage = currentXOffset / halfWidth;
            }
            
            NSTimeInterval duration = kRevealAnimationDuration * durationPercentage;
            __weak ContainerViewController *weakSelf = self;
            [self setMainViewControllerOffset:finalXOffset animationDuration:duration completion:^{
                //If we have hidden the menu, then remove it
                if (finalXOffset == 0.0f)
                {
                    [weakSelf removeMenuViewController];
                }
            }];
            break;
        }
//        case UIGestureRecognizerStateCancelled:
//        case UIGestureRecognizerStateFailed:
//        {
//            //Make sure we're positioned back at zero offset
//            CGFloat width = self.mainViewController.view.bounds.size.width;
//            CGFloat currentXOffset = self.mainViewControllerXOffsetContstraint.constant;
//            CGFloat finalXOffset = 0.0f;
//
//            self.mainViewControllerXOffsetContstraint.constant = finalXOffset;
//            
//            //Animate the final positioning
//            [self.view setNeedsUpdateConstraints];
//            NSTimeInterval duration = kRevealAnimationDuration * (currentXOffset / width);
//            [UIView animateWithDuration:duration delay:0.0f options:UIViewAnimationOptionCurveLinear animations:^{
//                [self.view layoutIfNeeded];
//            } completion:nil];
//            
//            break;
//        }
        default:
            //Do nothing
            break;
    }
}

#pragma mark - MenuActionHanlder

- (void)handleMenuAction
{
    CGFloat width = self.mainViewController.view.bounds.size.width;
    CGFloat halfWidth = width / 2.0f;
    CGFloat currentXOffset = self.mainViewControllerXOffsetContstraint.constant;
    CGFloat finalXOffset = currentXOffset > halfWidth ? 0.0f : kRevealPercentage * width;
    
    //If we will be showing the menu, then we must create and add it
    if (finalXOffset > 0.0f)
    {
        [self addMenuViewController];
    }
    
    NSTimeInterval duration = kRevealAnimationDuration;
    __weak ContainerViewController *weakSelf = self;
    [self setMainViewControllerOffset:finalXOffset animationDuration:duration completion:^{
        //If we have hidden the menu, then remove it
        if (finalXOffset == 0.0f)
        {
            [weakSelf removeMenuViewController];
        }
    }];
}

@end
