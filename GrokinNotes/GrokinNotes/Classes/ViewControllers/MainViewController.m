//
//  MainViewController.m
//  GrokinNotes
//
//  Created by Levi Brown on 1/16/14.
//  Copyright (c) 2014 Levi Brown. All rights reserved.
//

#import "MainViewController.h"
#import "NoteCell.h"
#import "NoteManager.h"
#import "UIAlertView+GRKAlertBlocks.h"
#import "NoteViewController.h"

static NSString * const kSegueNoteDetail = @"note_detail";

@interface MainViewController ()

@property (nonatomic,weak) IBOutlet UITableView *tableView;
@property (nonatomic,strong) UIRefreshControl *refreshControl;
@property (nonatomic,strong) NSMutableArray *notes;
@property (nonatomic,strong) Note *currentNote;
@property (nonatomic,assign) BOOL shouldEditNote;

- (IBAction)menuAction;
- (IBAction)addAction;

@end

@implementation MainViewController

#pragma mark - Lifecycle

- (void)dealloc
{
    //Remove ourselves as a notification observer
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    //Add the refresh control to the table view
    self.refreshControl = [[UIRefreshControl alloc] init];
    [self.refreshControl addTarget:self action:@selector(refreshTableView) forControlEvents:UIControlEventValueChanged];
    [self.tableView addSubview:self.refreshControl];
    self.tableView.alwaysBounceVertical = YES;
    self.notes = [NSMutableArray array];
    
    NoteManager *noteManager = [NoteManager shared];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(notificationNoteCreated:) name:kNoteNotificationNoteCreated object:noteManager];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(notificationNoteUpdated:) name:kNoteNotificationNoteUpdated object:noteManager];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(notificationNoteDeleted:) name:kNoteNotificationNoteDeleted object:noteManager];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    
    //Configure our shadow
    self.view.layer.shadowColor = [[UIColor blackColor] CGColor];
    self.view.layer.shadowOpacity = 0.5f;
    self.view.layer.shadowRadius = 8.0f;
    self.view.layer.shadowOffset = CGSizeZero;
    self.view.layer.shadowPath = [[UIBezierPath bezierPathWithRect:self.view.bounds] CGPath];

    //Kick off our note manager
    NoteManager *noteManager = [NoteManager shared];
    [noteManager startup:^(NSError *error) {
        if (error)
        {
            //TODO: Perhaps a better user experience here than just a dialog.
            UIAlertView *alert = [UIAlertView alertWithTitle:NSLocalizedString(@"Fatal Error", nil) message:[error localizedDescription]];
            [alert addButtonWithTitle:NSLocalizedString(@"Drat!", nil) handler:^{
                exit(EXIT_FAILURE);
            }];
            [alert show];
        }
        else
        {
            [self.notes removeAllObjects];
            NSArray *visibleNotes = [noteManager visibleNotes];
            [self.notes addObjectsFromArray:visibleNotes];
            [self.tableView reloadData];
        }
    }];
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    
    NoteManager *noteManager = [NoteManager shared];
    GoogleDriveManager *driveManager = noteManager.driveManager;
    if (driveManager.initialized)
    {
        if (![driveManager authorized])
        {
            GTMOAuth2ViewControllerTouch *authViewController = [driveManager createAuthControllerWithCompletion:^(GTMOAuth2ViewControllerTouch *viewController, NSError *error) {
                [self dismissViewControllerAnimated:YES completion:^{
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
}

#pragma mark - Segue

- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender
{
    NSString *identifier = segue.identifier;
    if ([identifier isEqual:kSegueNoteDetail])
    {
        //Get a reference to the detail view controller and configure it
        id obj = segue.destinationViewController;
        if ([obj isKindOfClass:NoteViewController.class])
        {
            NoteViewController *noteViewController = (NoteViewController *)obj;
            noteViewController.note = self.currentNote;
            noteViewController.shouldEdit = self.shouldEditNote;
        }
        else
        {
            DDLogError(@"Seque '%@' is of unexpected type: %@", identifier, obj);
        }
    }
}

#pragma mark - Actions

- (IBAction)menuAction
{
    DDLogVerbose(@"menuAction");
    if ([self.menuActionHandler respondsToSelector:@selector(handleMenuAction)])
    {
        [self.menuActionHandler handleMenuAction];
    }
}

- (IBAction)addAction
{
    DDLogVerbose(@"addAction");
    NoteManager *noteManager = [NoteManager shared];
    [noteManager createNewUniqueNote:^(Note *note, NSError *error) {
        if (note)
        {
            self.currentNote = note;
            self.shouldEditNote = YES;
            [self performSegueWithIdentifier:kSegueNoteDetail sender:self];
        }
        else
        {
            UIAlertView *alert = [UIAlertView alertWithTitle:NSLocalizedString(@"Sorry", nil) message:[error localizedDescription]];
            [alert addButtonWithTitle:NSLocalizedString(@"Drat!", nil) handler:nil];
            [alert show];
        }
    }];
}

#pragma mark - Notifications

- (void)notificationNoteCreated:(NSNotification *)notification
{
    DDLogVerbose(@"notificationNoteCreated: %@", notification);
    
    NSDictionary *userInfo = notification.userInfo;
    Note *note = [userInfo objectForKey:kNoteNotificationInfoKeyNote];
    if (note)
    {
        NoteManager *noteManager = [NoteManager shared];
        [self.notes removeAllObjects];
        NSArray *visibleNotes = [noteManager visibleNotes];
        [self.notes addObjectsFromArray:visibleNotes];

        NSUInteger index = [self.notes indexOfObject:note];
        if (index != NSNotFound)
        {
            NSIndexPath *indexPath = [NSIndexPath indexPathForRow:index inSection:0];
            [self.tableView beginUpdates];
            [self.tableView insertRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationAutomatic];
            [self.tableView endUpdates];
        }
    }
}

- (void)notificationNoteUpdated:(NSNotification *)notification
{
    DDLogVerbose(@"notificationNoteUpdated: %@", notification);
    
    NSDictionary *userInfo = notification.userInfo;
    Note *note = [userInfo objectForKey:kNoteNotificationInfoKeyNote];
    if (note)
    {
        NSUInteger index = [self.notes indexOfObject:note];
        if (index != NSNotFound)
        {
            NSIndexPath *indexPath = [NSIndexPath indexPathForRow:index inSection:0];
            [self.tableView beginUpdates];
            [self.tableView reloadRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationAutomatic];
            [self.tableView endUpdates];
        }
    }
}

- (void)notificationNoteDeleted:(NSNotification *)notification
{
    DDLogVerbose(@"notificationNoteDeleted: %@", notification);

    NSDictionary *userInfo = notification.userInfo;
    Note *note = [userInfo objectForKey:kNoteNotificationInfoKeyNote];
    if (note)
    {
        NSUInteger index = [self.notes indexOfObject:note];
        if (index != NSNotFound)
        {
            [self.notes removeObject:note];
            
            NSIndexPath *indexPath = [NSIndexPath indexPathForRow:index inSection:0];
            [self.tableView beginUpdates];
            [self.tableView deleteRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationAutomatic];
            [self.tableView endUpdates];
        }
    }
}

#pragma mark - Table View

//Called by the UIRefreshControl
- (void)refreshTableView
{
    DDLogVerbose(@"refreshTableView");
    
    NoteManager *noteManager = [NoteManager shared];
    [noteManager synchronize:^(NSError *error) {
        [self.refreshControl endRefreshing];
    }];
}

#pragma mark - UITableViewDataSource

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    NSInteger count = self.notes.count;
    return count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    NoteCell *cell = [tableView dequeueReusableCellWithIdentifier:NSStringFromClass(NoteCell.class) forIndexPath:indexPath];
    
    Note *note = [self.notes objectAtIndex:indexPath.row];
    
    //Configure cell
    cell.textLabel.text = note.title;
    
    return cell;
}

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath
{
    switch (editingStyle) {
        case UITableViewCellEditingStyleDelete:
        {
            //Handle delete
            Note *note = [self.notes objectAtIndex:indexPath.row];
            //Remove the note from the manager
            NoteManager *noteManager = [NoteManager shared];
            [noteManager markNoteAsDeleted:note];
            //Remove the note from our local array
            [self.notes removeObject:note];
            //Update the table view
            [tableView deleteRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationAutomatic];
            break;
        }
        default:
            DDLogError(@"Unhandled editing style '%ld'.", editingStyle);
            break;
    }
}

#pragma mark - UITableViewDelegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    DDLogVerbose(@"tableView:didSelectRowAtIndexPath: %@", indexPath);
    self.currentNote = [self.notes objectAtIndex:indexPath.row];
    self.shouldEditNote = NO;
    [self performSegueWithIdentifier:kSegueNoteDetail sender:self];
}

@end

