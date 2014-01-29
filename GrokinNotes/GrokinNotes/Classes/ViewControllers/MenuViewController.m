//
//  MenuViewController.m
//  GrokinNotes
//
//  Created by Levi Brown on 1/16/14.
//  Copyright (c) 2014 Levi Brown. All rights reserved.
//

#import "MenuViewController.h"
#import "NoteManager.h"
#import "GoogleDriveManager.h"
#import "UIAlertView+GRKAlertBlocks.h"

@interface MenuViewController ()

@property (nonatomic,weak) IBOutlet UIButton *signInOutButton;

- (IBAction)signInOutAction;

@end

@implementation MenuViewController

#pragma mark - Lifecycle

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];

    [self updateSignInOutButton];
}

#pragma mark - Actions

- (IBAction)signInOutAction
{
    NoteManager *noteManager = [NoteManager shared];
    GoogleDriveManager *driveManager = noteManager.driveManager;
    if ([driveManager authorized])
    {
        [driveManager signout];
        [self updateSignInOutButton];
    }
    else
    {
        GTMOAuth2ViewControllerTouch *authViewController = [driveManager createAuthControllerWithCompletion:^(GTMOAuth2ViewControllerTouch *viewController, NSError *error) {
            [self dismissViewControllerAnimated:YES completion:^{
                [self updateSignInOutButton];
                if (error)
                {
                    UIAlertView *alert = [UIAlertView alertWithTitle:NSLocalizedString(@"Authorization Failed", nil) message:[error localizedDescription]];
                    [alert addButtonWithTitle:NSLocalizedString(@"Drat!", nil) handler:nil];
                    [alert show];
                }
            }];
        }];
        [self presentViewController:authViewController animated:YES completion:nil];
    }
}

#pragma mark - Helpers

- (void)updateSignInOutButton
{
    NoteManager *noteManager = [NoteManager shared];
    GoogleDriveManager *driveManager = noteManager.driveManager;
    
    NSString *buttonTitle = [driveManager authorized] ? NSLocalizedString(@"Sign Out", nil) : NSLocalizedString(@"Sign In", nil);
    [self.signInOutButton setTitle:buttonTitle forState:UIControlStateNormal];
}

@end
