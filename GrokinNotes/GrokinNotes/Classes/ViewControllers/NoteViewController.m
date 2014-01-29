//
//  NoteViewController.m
//  GrokinNotes
//
//  Created by Levi Brown on 1/22/14.
//  Copyright (c) 2014 Levi Brown. All rights reserved.
//

#import "NoteViewController.h"
#import "NoteManager.h"
#import "UIAlertView+GRKAlertBlocks.h"

static NSTimeInterval const kContentAnimationDuration = 0.25f;

@interface NoteViewController ()

@property (nonatomic,weak) IBOutlet UITextField *titleTextField;
@property (nonatomic,weak) IBOutlet UITextView *textView;
@property (nonatomic,weak) IBOutlet NSLayoutConstraint *textViewBottomConstraint;
@property (nonatomic,strong) NSOperationQueue *autosaveOperationQueue;

@end

@implementation NoteViewController

#pragma mark - Lifecycle

- (void)dealloc
{
    //Remove ourselves as a notification observer
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboardWillShow:) name:UIKeyboardWillShowNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboardWillHide:) name:UIKeyboardWillHideNotification object:nil];

    NoteManager *noteManager = [NoteManager shared];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(notificationNoteUpdated:) name:kNoteNotificationNoteUpdated object:noteManager];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    
    [self.note readContent:^(NSString *content, NSError *error) {
        [UIView transitionWithView:self.view duration:kContentAnimationDuration options:UIViewAnimationOptionTransitionCrossDissolve animations:^{
            self.titleTextField.text = self.note.title;
            self.textView.text = content;
        } completion:^(BOOL finished) {
            if (self.shouldEdit)
            {
                [self.textView becomeFirstResponder];
            }
        }];
        if (error)
        {
            DDLogError(@"Unable to read content of note '%@'. Error: %@", self.note, error);
        }
    }];
}

- (void)viewWillDisappear:(BOOL)animated
{
    [super viewWillDisappear:animated];
    
    [self.view endEditing:YES];
}

#pragma mark - Notifications

- (void)notificationNoteUpdated:(NSNotification *)notification
{
    DDLogVerbose(@"notificationNoteUpdated: %@", notification);
    
    NSDictionary *userInfo = notification.userInfo;
    Note *notificationNote = [userInfo objectForKey:kNoteNotificationInfoKeyNote];
    
    //If the notification is for the note we are currently displaying
    if ([notificationNote.remoteID isEqualToString:self.note.remoteID])
    {
        //and the note is not dirty
        if (![self.note readDirty])
        {
            //Update our display with the updated note
            [self.note readContent:^(NSString *content, NSError *error) {
                [UIView transitionWithView:self.view duration:kContentAnimationDuration options:UIViewAnimationOptionTransitionCrossDissolve animations:^{
                    //Don't update the title if it is being edited
                    if (!self.titleTextField.isFirstResponder)
                    {
                        self.titleTextField.text = self.note.title;
                    }
                    //Don't update the content if it is being edited
                    if (!self.textView.isFirstResponder)
                    {
                        self.textView.text = content;
                    }
                } completion:nil];
                if (error)
                {
                    DDLogError(@"Unable to read content of note '%@'. Error: %@", self.note, error);
                }
            }];
        }
    }
}

#pragma mark - Keyboard Handling

//Called when a UIKeyboardWillShowNotification is received
- (void)keyboardWillShow:(NSNotification *)aNotification
{
    NSDictionary *userInfo = [aNotification userInfo];
    NSTimeInterval duration = [[userInfo objectForKey:UIKeyboardAnimationDurationUserInfoKey] doubleValue];
    CGSize kbSize = [[userInfo objectForKey:UIKeyboardFrameBeginUserInfoKey] CGRectValue].size;
	UIViewAnimationCurve animationCurve = [[userInfo objectForKey:UIKeyboardAnimationCurveUserInfoKey] integerValue];
    //See: http://stackoverflow.com/a/19490788/397210
    animationCurve = animationCurve << 16;
    
    self.textViewBottomConstraint.constant = kbSize.height;
    [self updateViewConstraints];
    
    [UIView animateWithDuration:duration delay:0 options:(UIViewAnimationOptions)animationCurve animations:^{
        [self.view layoutIfNeeded];
    } completion:nil];
}

//Called when a UIKeyboardWillHideNotification is received
- (void)keyboardWillHide:(NSNotification *)aNotification
{
    NSDictionary *userInfo = [aNotification userInfo];
    NSTimeInterval duration = [[userInfo objectForKey:UIKeyboardAnimationDurationUserInfoKey] doubleValue];
	UIViewAnimationCurve animationCurve = [[userInfo objectForKey:UIKeyboardAnimationCurveUserInfoKey] integerValue];
    //See: http://stackoverflow.com/a/19490788/397210
    animationCurve = animationCurve << 16;
    
    self.textViewBottomConstraint.constant = 0.0f;
    [self updateViewConstraints];
    
    [UIView animateWithDuration:duration delay:0 options:(UIViewAnimationOptions)animationCurve animations:^{
        [self.view layoutIfNeeded];
    } completion:nil];
}

#pragma mark - UITextFieldDelegate

- (BOOL)textFieldShouldReturn:(UITextField *)textField
{
    NSString *newTitle = textField.text;
    NSError *error = [self.note updateTitle:newTitle];
    if (error)
    {
        NSString *message = NSLocalizedString(@"Please choose a different title for your note.", nil);
        if (newTitle.length == 0)
        {
            message = NSLocalizedString(@"Your note must have a title.", nil);
        }
        else
        {
            NSError *underlyingError = [error.userInfo objectForKey:NSUnderlyingErrorKey];
            if (underlyingError)
            {
                message = [underlyingError localizedDescription];
            }
        }

        UIAlertView *alert = [UIAlertView alertWithTitle:NSLocalizedString(@"Title Error", nil) message:message];
        [alert addButtonWithTitle:NSLocalizedString(@"Drat!", nil) handler:^{
            [textField becomeFirstResponder];
        }];
        [alert show];
    }
    else
    {
        [textField resignFirstResponder];
    }

    return YES;
}

#pragma mark - UITextViewDelegate

- (void)textViewDidChange:(UITextView *)textView
{
    if (!self.autosaveOperationQueue)
    {
        self.autosaveOperationQueue = [[NSOperationQueue alloc] init];
        [self.autosaveOperationQueue setMaxConcurrentOperationCount:1];
    }
    
    //Cancels all pending operations (but not the one executing). This drains the queue of obsolete save requests, since the new request will have the latest changes.
    [self.autosaveOperationQueue cancelAllOperations];
    
    //Grab the current text
    NSString *content = textView.text;
    //Create an operation to save the content
    [self.autosaveOperationQueue addOperationWithBlock:^{
        dispatch_group_t group = dispatch_group_create();
        dispatch_group_enter(group);
        [self.note writeContent:content completion:^(BOOL changed, NSString *content, NSError *error) {
            if (error)
            {
                DDLogError(@"Failed to write content for note '%@'. Error: %@", self.note, error);
            }
            else
            {
                DDLogVerbose(@"Content saved for note '%@'", self.note);
            }
            dispatch_group_leave(group);
        }];
        dispatch_group_wait(group, DISPATCH_TIME_FOREVER);
    }];
}

@end
