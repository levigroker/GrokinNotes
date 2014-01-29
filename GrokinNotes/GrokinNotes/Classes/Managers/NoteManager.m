//
//  NoteManager.m
//  GrokinNotes
//
//  Created by Levi Brown on 1/22/14.
//  Copyright (c) 2014 Levi Brown. All rights reserved.
//

#import "NoteManager.h"
#import "GRKFileManager.h"
#import "NSString+UUID.h"

NSString * const NoteManagerErrorDomain = @"NoteManagerErrorDomain";

//The name of the notification which is sent when a note is created
NSString * const kNoteNotificationNoteCreated = @"NoteManagerNoteCreated";
//The name of the notification which is sent when a note is updated
NSString * const kNoteNotificationNoteUpdated = @"NoteManagerNoteUpdated";
//The name of the notification which is sent when a note is deleted
NSString * const kNoteNotificationNoteDeleted = @"NoteManagerNoteDeleted";

//The userInfo key for notifications which represents the Note object
NSString * const kNoteNotificationInfoKeyNote = @"note";

//Delay between synchronization attempts
static NSTimeInterval const kSynchronizationInterval = 5.0f;

static NSString * const kDefaultsKeyGoogleDriveChangeID = @"google_drive_change_id";

static NSUInteger const kMaxUniqueFilenameAttempts = 1000;

@interface NoteManager ()

//All notes
@property (nonatomic,strong) NSMutableArray *notes;
@property (nonatomic,strong) NSMutableArray *mVisibleNotes;
@property (nonatomic,strong) NSMutableDictionary *notesByRemoteID;
@property (nonatomic,strong) NSMutableDictionary *notesByLocalID;
@property (nonatomic,strong) GRKFileManager *grkFileManager;
@property (nonatomic,strong,readwrite) GoogleDriveManager *driveManager;
@property (nonatomic,strong) NSNumber *lastGoogleDriveChangeID;
@property (nonatomic,assign) BOOL willSynchronize;

@end

@implementation NoteManager

#pragma Initialization

+ (instancetype)shared
{
    static dispatch_once_t onceQueue;
    static NoteManager *noteManager = nil;
    
    dispatch_once(&onceQueue, ^{ noteManager = [[self alloc] init]; });
    return noteManager;
}

- (id)init
{
    if ((self = [super init]))
    {
        self.grkFileManager = [[GRKFileManager alloc] init];
        self.driveManager = [[GoogleDriveManager alloc] init];
        self.notes = [NSMutableArray array];
        self.mVisibleNotes = [NSMutableArray array];
        self.notesByRemoteID = [NSMutableDictionary dictionary];
        self.notesByLocalID = [NSMutableDictionary dictionary];
    }
    
    return self;
}

#pragma mark - Implementation

- (void)startup:(void(^)(NSError *error))completion
{
    NSError *driveManagerError = [self.driveManager startup];
    
    //Fetch any stored Google Drive change ID
    self.lastGoogleDriveChangeID = [[NSUserDefaults standardUserDefaults] objectForKey:kDefaultsKeyGoogleDriveChangeID];
    
    //Update our knowlege of notes from the local file system
    [self updateNotesWithCompletion:^{
        
        if (!driveManagerError)
        {
            //Start ongoing synchronization operations
            [self startSynchronize];
        }
        
        completion(driveManagerError);
    }];
}

- (void)shutdown
{
    [self stopSynchronize];
}

- (NSArray *)visibleNotes
{
    if (!self.mVisibleNotes)
    {
        self.mVisibleNotes = [NSMutableArray array];
        for (Note *note in self.notes)
        {
            if (!note.deleted)
            {
                [self.mVisibleNotes addObject:note];
            }
        }
    }
    
    return [self.mVisibleNotes copy];
}

- (void)markNoteAsDeleted:(Note *)note
{
    [note writeDeleted:YES];
    if (self.mVisibleNotes)
    {
        [self.mVisibleNotes removeObject:note];
    }
}

- (void)synchronize:(void(^)(NSError *error))completion
{
    [[UIApplication sharedApplication] setNetworkActivityIndicatorVisible:YES];
    
    DDLogVerbose(@"Synchronize: Reaping deleted notes...");
    [self reapDeletedNotes:^{
        DDLogVerbose(@"Synchronize: Updating changes to remote...");
        [self updateDirtyNotes:^{
            DDLogVerbose(@"Synchronize: Refreshing with changes from remote...");
            [self refreshFromRemote:^(NSError *error) {
                [[UIApplication sharedApplication] setNetworkActivityIndicatorVisible:NO];
                if (error)
                {
                    DDLogError(@"Synchronize: Failed attempt with error: %@", error);
                }
                else
                {
                    DDLogVerbose(@"Synchronize: Complete.");
                }
                
                if (completion)
                {
                    completion(error);
                }
            }];
        }];
    }];
}

- (void)refreshFromRemote:(void(^)(NSError *error))completion
{
    NSNumber *startChangeID = nil;
    if (self.lastGoogleDriveChangeID)
    {
        //Increment the change ID to +1 so we start with new changes...
        startChangeID = [NSNumber numberWithLongLong:[self.lastGoogleDriveChangeID longLongValue] + 1];
    }
    
    [self.driveManager retrieveAllChangesSinceChangeID:startChangeID completion:^(NSArray *changes, NSNumber *largestChangeID, NSError *error) {
        if (largestChangeID)
        {
            self.lastGoogleDriveChangeID = largestChangeID;
            //Store the change ID so we only update deltas since last refresh
            [[NSUserDefaults standardUserDefaults]  setObject:self.lastGoogleDriveChangeID forKey:kDefaultsKeyGoogleDriveChangeID];
        }
        
        //Create a dispatch group to track all parts of the update to completion
        dispatch_group_t updateGroup = dispatch_group_create();
        
        for (GTLDriveChange *change in changes)
        {
            // The ID of the file associated with this change.
            NSString *fileID = change.fileId;
            
            BOOL deleted = [change.deleted boolValue];
            
            //Interact with notes from the main queue
            //Track this dispatch to completion
            dispatch_group_async(updateGroup, dispatch_get_main_queue(), ^{
                Note *note = [self.notesByRemoteID objectForKey:fileID];
                if (deleted)
                {
                    DDLogVerbose(@"Remote file deleted with ID '%@' local note: '%@'", fileID, note);
                    
                    //If the note is dirty locally, then we choose to restore the remote version, and let the remote note be updated with the local changes.
                    if (note.dirty)
                    {
                        DDLogWarn(@"Local note has changes. Ignoring update from remote.");
                        [self.driveManager restoreFileWithID:fileID completion:^(GTLDriveFile *file, NSError *error) {
                            if (error)
                            {
                                DDLogError(@"Unable to restore note: '%@'. Error: %@", note, error);
                            }
                        }];
                    }
                    else
                    {
                        //The local note is not dirty, so we can just delete it
                        //The note object may also just be nil (not tracked locally)
                        DDLogVerbose(@"Deleting note: '%@'", note);
                        if ([self deleteLocalFile:note.file])
                        {
                            [self.notes removeObject:note];
                            [self.mVisibleNotes removeObject:note];
                            if (note.remoteID)
                            {
                                [self.notesByRemoteID removeObjectForKey:note.remoteID];
                            }
                            if (note.localID)
                            {
                                [self.notesByLocalID removeObjectForKey:note.localID];
                            }
                            
                            if (note)
                            {
                                //Post a notification informing subscribers that the note has been deleted
                                NSMutableDictionary *userInfo = [NSMutableDictionary dictionaryWithCapacity:1];
                                [userInfo setObject:note forKey:kNoteNotificationInfoKeyNote];
                                [[NSNotificationCenter defaultCenter] postNotificationName:kNoteNotificationNoteDeleted object:self userInfo:userInfo];
                            }
                        }
                    }
                }
                else
                {
                    DDLogVerbose(@"Update avaialble from remote for remote file ID '%@'. Local note: '%@'", fileID, note);
                    
                    if (note.dirty)
                    {
                        DDLogWarn(@"Local note has changes. Ignoring update from remote.");
                    }
                    else
                    {
                        //The note has updates and there are no local changes (or no local note)...
                        
                        GTLDriveFile *file = change.file;
                        
                        //Only want text files
                        if ([file.mimeType isEqualToString:kMIMETypeTextPlain])
                        {
                            //Download the updated note into a temp directory
                            NSURL *tempDir = [self.grkFileManager tempDirectory];
                            [self.driveManager downloadFile:file toFolder:tempDir completion:^(GTLDriveFile *file, NSURL *fileURL, NSError *error) {
                                //Could have been made dirty while we were fetching changes
                                if (note.dirty)
                                {
                                    DDLogWarn(@"Local note has changes. Ignoring update from remote.");
                                    //Discard remote changes (still in temp dir, so we don't care if this fails)
                                    [self deleteLocalFile:fileURL];
                                }
                                else
                                {
                                    if (note)
                                    {
                                        DDLogVerbose(@"Existing note being updated: '%@'", note);
                                        
                                        //Move the note into place
                                        __autoreleasing NSError *error = nil;
                                        NSURL *resultingItemURL = [self.grkFileManager replaceFile:note.file withFile:fileURL error:&error];
                                        if (resultingItemURL)
                                        {
                                            //Save the note metadata, which is associated with the old file
                                            NSString *localID = note.localID;
                                            NSString *remoteID = note.remoteID;
                                            //Set the note's file to the new file (this will update the note's medatata with that from the file, which will not exist)
                                            note.file = resultingItemURL;
                                            //Repopulate the file's medatata
                                            [note writeLocalID:localID];
                                            [note writeRemoteID:remoteID];

                                            DDLogVerbose(@"Updated note: '%@'", note);

                                            //Post a notification informing subscribers that the note has been updated
                                            NSMutableDictionary *userInfo = [NSMutableDictionary dictionaryWithCapacity:1];
                                            [userInfo setObject:note forKey:kNoteNotificationInfoKeyNote];
                                            [[NSNotificationCenter defaultCenter] postNotificationName:kNoteNotificationNoteUpdated object:self userInfo:userInfo];
                                        }
                                        else
                                        {
                                            DDLogError(@"Unable to relocate updated note file to destination directory. Error: %@", error);
                                        }
                                    }
                                    else
                                    {
                                        //Move to background so sorting is off the main queue
                                        //Track this dispatch to completion
                                        dispatch_group_async(updateGroup, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                                            
                                            //We don't have the note locally yet, so create it.
                                            DDLogVerbose(@"No local note. Creating one from remote file: %@", file);

                                            //TODO: We are not paying attention to the driveFile's parent hierarchy, and simply flattenting the structure. We should create the needed hierarchy to correctly place the file locally.
                                            //NOTE: This assumes all notes are stored at the top level of the documents directory
                                            NSURL *documentsDir = [self.grkFileManager documentsDirectory];
                                            NSString *title = file.title;
                                            NSURL *noteFile = [documentsDir URLByAppendingPathComponent:title];

                                            //Move the note into place
                                            __autoreleasing NSError *error = nil;
                                            BOOL success = [self.grkFileManager.fileManager moveItemAtURL:fileURL toURL:noteFile error:&error];
                                            if (success)
                                            {
                                                Note *newNote = [[Note alloc] init];
                                                newNote.file = noteFile;
                                                [newNote writeLocalID:[NSString UUID]];
                                                [newNote writeRemoteID:file.identifier];
                                                
                                                DDLogVerbose(@"New note created locally: '%@'", newNote);

                                                NSMutableArray *notes = [NSMutableArray arrayWithArray:self.notes];
                                                [notes addObject:newNote];
                                                NSArray *updatedNotes = [self sortNotes:notes];

                                                //Interact with notes from the main queue
                                                //Track this dispatch to completion
                                                dispatch_group_async(updateGroup, dispatch_get_main_queue(), ^{
                                                    
                                                    [self.notes removeAllObjects];
                                                    [self.notes addObjectsFromArray:updatedNotes];
                                                    self.mVisibleNotes = nil;
                                                    if (newNote.remoteID)
                                                    {
                                                        [self.notesByRemoteID setObject:newNote forKey:newNote.remoteID];
                                                    }
                                                    if (newNote.localID)
                                                    {
                                                        [self.notesByLocalID setObject:newNote forKey:newNote.localID];
                                                    }
                                                    DDLogVerbose(@"Created note: '%@'", newNote);
                                                    
                                                    //Post a notification informing subscribers that the note has been created
                                                    NSMutableDictionary *userInfo = [NSMutableDictionary dictionaryWithCapacity:1];
                                                    [userInfo setObject:newNote forKey:kNoteNotificationInfoKeyNote];
                                                    [[NSNotificationCenter defaultCenter] postNotificationName:kNoteNotificationNoteCreated object:self userInfo:userInfo];
                                                });
                                            }
                                            else
                                            {
                                                DDLogError(@"Unable to relocate new note file to destination directory. Error: %@", error);
                                            }
                                        });
                                    }
                                }
                            }];
                        }
                        else
                        {
                            DDLogWarn(@"Remote file is of type '%@' (expecting '%@'). Ignoring update from remote. File: %@", file.mimeType, kMIMETypeTextPlain, file);
                        }
                    }
                }
            });
        }
        
        DDLogVerbose(@"Waiting for all refresh actions to complete...");
        dispatch_group_notify(updateGroup, dispatch_get_main_queue(), ^{
            DDLogVerbose(@"Completed refresh actions.");
            if (error)
            {
                DDLogError(@"Unable to retrieve changes from Google Drive. Error: %@", error);
            }
            if (completion)
            {
                completion(error);
            }
        });
    }];
}

- (void)createNewUniqueNote:(void(^)(Note *note, NSError *error))completion
{
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{

        //NOTE: This assumes all notes are stored at the top level of the documents directory
        NSURL *documentsDir = [self.grkFileManager documentsDirectory];
        __autoreleasing NSError *fileError = nil;
        NSURL *file = [self uniqueFileInDirectory:documentsDir error:&fileError];
        if (file)
        {
            Note *note = [[Note alloc] init];
            note.file = file;
            [note writeLocalID:[NSString UUID]];
            [note writeDirty:YES];

            NSMutableArray *notes = [NSMutableArray arrayWithArray:self.notes];
            [notes addObject:note];
            NSArray *updatedNotes = [self sortNotes:notes];
            
            //Interact with notes from the main queue
            dispatch_async(dispatch_get_main_queue(), ^{
                [self.notes removeAllObjects];
                [self.notes addObjectsFromArray:updatedNotes];
                self.mVisibleNotes = nil;
                if (note.remoteID)
                {
                    [self.notesByRemoteID setObject:note forKey:note.remoteID];
                }
                if (note.localID)
                {
                    [self.notesByLocalID setObject:note forKey:note.localID];
                }
                DDLogVerbose(@"Created new note: '%@'", note);
                
                dispatch_async(dispatch_get_main_queue(), ^{
                    //Post a notification informing subscribers that the note has been created
                    NSMutableDictionary *userInfo = [NSMutableDictionary dictionaryWithCapacity:1];
                    [userInfo setObject:note forKey:kNoteNotificationInfoKeyNote];
                    [[NSNotificationCenter defaultCenter] postNotificationName:kNoteNotificationNoteCreated object:self userInfo:userInfo];
                    
                    if (completion)
                    {
                        completion(note, nil);
                    }
                });
            });
        }
        else
        {
            if (completion)
            {
                NSMutableDictionary *userInfo = [NSMutableDictionary dictionaryWithCapacity:2];
                [userInfo setObject:NSLocalizedString(@"Odd, I could not create a new note for you.", nil) forKey:NSLocalizedDescriptionKey];
                [userInfo setValue:fileError forKey:NSUnderlyingErrorKey];
                NSError *error = [[NSError alloc] initWithDomain:NoteManagerErrorDomain code:NoteManagerErrorBadCreate userInfo:userInfo];
                
                dispatch_async(dispatch_get_main_queue(), ^{
                    completion(nil, error);
                });
            }
        }
    });
}

#pragma mark - Recurring Operations

- (void)startSynchronize
{
    if (!self.willSynchronize)
    {
        DDLogVerbose(@"Synchronize: Started recurring process.");
        self.willSynchronize = YES;
        [self recurringSynchronize];
    }
}

- (void)recurringSynchronize
{
    [self synchronize:^(NSError *error) {
        DDLogVerbose(@"Synchronize: Waiting (%.2f seconds) for next attempt.", kSynchronizationInterval);
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kSynchronizationInterval * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if (self.willSynchronize)
            {
                [self recurringSynchronize];
            }
            else
            {
                DDLogVerbose(@"Synchronize: Stopped recurring process.");
            }
        });
    }];
}

- (void)stopSynchronize
{
    self.willSynchronize = NO;
}

#pragma mark - Helpers

- (NSURL *)uniqueFileInDirectory:(NSURL *)directory error:(__autoreleasing NSError **)error
{
    NSURL *retVal = nil;

    NSString *content = [NSString string];
    NSData *data = [content dataUsingEncoding:NSUTF8StringEncoding];
    BOOL success = NO;
    NSUInteger i = 0;
    while (!success) {
        NSString *name = [NSString stringWithFormat:@"%@%@", NSLocalizedString(@"Untitled", nil), i++ == 0 ? @"" : [NSString stringWithFormat:@" %ld", i]];
        NSURL *file = [directory URLByAppendingPathComponent:name];
        __autoreleasing NSError *writeError = nil;
        success = [data writeToURL:file options:NSDataWritingWithoutOverwriting error:&writeError];
        if (success)
        {
            retVal = file;
        }
        else
        {
            if (i > kMaxUniqueFilenameAttempts)
            {
                if (error)
                {
                    NSMutableDictionary *userInfo = [NSMutableDictionary dictionaryWithCapacity:2];
                    [userInfo setObject:[NSString stringWithFormat:@"%@ (%ld) %@", NSLocalizedString(@"The maximum number of attempts", nil), kMaxUniqueFilenameAttempts, NSLocalizedString(@"was reached before success.", nil)] forKey:NSLocalizedDescriptionKey];
                    [userInfo setValue:writeError forKey:NSUnderlyingErrorKey];
                    *error = [[NSError alloc] initWithDomain:NoteManagerErrorDomain code:NoteManagerErrorTooManyAttempts userInfo:userInfo];
                }
                break;
            }
        }
    }

    return retVal;
}

- (void)updateNotesWithCompletion:(void(^)(void))completion
{
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        //NOTE: This assumes all notes are stored at the top level of the documents directory
        NSURL *documentsDir = [self.grkFileManager documentsDirectory];
        NSArray *notes = [self fetchNotesFromDirectory:documentsDir];
        
        notes = [self sortNotes:notes];

        NSMutableDictionary *notesByRemoteID = [NSMutableDictionary dictionary];
        NSMutableDictionary *notesByLocalID = [NSMutableDictionary dictionary];
        for (Note *note in notes)
        {
            //Update local ID note map
            NSString *localID = note.localID;
            if (localID)
            {
                [notesByLocalID setObject:note forKey:localID];
            }

            //Update remote ID note map
            NSString *remoteID = note.remoteID;
            if (remoteID)
            {
                [notesByRemoteID setObject:note forKey:remoteID];
            }
        }
        //Update our properties on the main queue
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.notes removeAllObjects];
            [self.notes addObjectsFromArray:notes];
            self.mVisibleNotes = nil;
            [self.notesByRemoteID removeAllObjects];
            [self.notesByRemoteID addEntriesFromDictionary:notesByRemoteID];
            [self.notesByLocalID removeAllObjects];
            [self.notesByLocalID addEntriesFromDictionary:notesByLocalID];
            if (completion)
            {
                completion();
            }
        });
    });
}

- (void)updateDirtyNotes:(void(^)(void))completion
{
    //Create a dispatch group to track all parts of the update to completion
    dispatch_group_t updateGroup = dispatch_group_create();

    //We ensure we interact with the note state from the main queue so we are sure to have the correct state
    //Track this dispatch to completion
    dispatch_group_async(updateGroup, dispatch_get_main_queue(), ^{
        for (Note *note in self.notes)
        {
            if (note.dirty)
            {
                DDLogVerbose(@"Processing locally dirty note: %@", note);

                //Track this dispatch to completion
                dispatch_group_enter(updateGroup);
                [self updateNote:note completion:^(Note *note) {
                    dispatch_group_leave(updateGroup);
                }];
            }
        }
    });
    
    DDLogVerbose(@"Waiting for all updateDirtyNotes actions to complete...");
    dispatch_group_notify(updateGroup, dispatch_get_main_queue(), ^{
        DDLogVerbose(@"Completed updateDirtyNotes actions.");
        if (completion)
        {
            completion();
        }
    });
}

- (void)updateNote:(Note *)note completion:(void(^)(Note *note))completion
{
    //Create a dispatch group to track all parts of the update to completion
    dispatch_group_t updateGroup = dispatch_group_create();

    //We ensure we interact with the note state from the main queue so we are sure to have the correct state
    //Track this dispatch to completion
    dispatch_group_async(updateGroup, dispatch_get_main_queue(), ^{
        //Capture the checksum before we attempt an update of the remote
        NSString *oldMD5 = [note updateMD5];

        if (note.remoteID)
        {
            DDLogVerbose(@"Updating existing remote note from local note %@", note);

            //Note exists remotely, so update it.
            GTLDriveFile *file = [GTLDriveFile object];
            file.identifier = note.remoteID;
            file.mimeType = kMIMETypeTextPlain;
            file.title = note.title;
            //Track this dispatch to completion
            dispatch_group_enter(updateGroup);
            [self.driveManager updateDriveFile:file fromFileURL:note.file completion:^(GTLDriveFile *updatedFile, NSError *error) {
                if (error)
                {
                    DDLogError(@"Unable to update remote file for note '%@'. Error: %@", note, error);
                }
                else
                {
                    //The note may have been modified locally while we were trying to update the remote, so compare checksums to see if the note should still be marked as dirty
                    NSString *newMD5 = [note updateMD5];
                    BOOL dirty = ![oldMD5 isEqualToString:newMD5];
                    [note writeDirty:dirty];

                    DDLogVerbose(@"Updated existing remote note from local note %@", note);
                }
                //Exit the dispatch group
                dispatch_group_leave(updateGroup);
            }];
        }
        else
        {
            DDLogVerbose(@"Creating new remote note from local note %@", note);

            //Note is only local, so create it remotely.
            //TODO: Specify a parent folder
            //Track this dispatch to completion
            dispatch_group_enter(updateGroup);
            [self.driveManager createFile:note.file withMIMEType:kMIMETypeTextPlain inFolder:nil completion:^(GTLDriveFile *createdFile, NSError *error) {
                if (error)
                {
                    DDLogError(@"Unable to create remote file for note '%@'. Error: %@", note, error);
                }
                else
                {
                    //Track the remote identifier
                    [note writeRemoteID:createdFile.identifier];
                    
                    //The note may have been modified locally while we were trying to update the remote, so compare checksums to see if the note should still be marked as dirty
                    NSString *newMD5 = [note updateMD5];
                    BOOL dirty = ![oldMD5 isEqualToString:newMD5];
                    [note writeDirty:dirty];

                    DDLogVerbose(@"Created new remote note from local note %@", note);
                }
                //Exit the dispatch group
                dispatch_group_leave(updateGroup);
            }];
        }
    });

    DDLogVerbose(@"Waiting for all updateNote actions to complete...");
    dispatch_group_notify(updateGroup, dispatch_get_main_queue(), ^{
        DDLogVerbose(@"Completed updateNote actions.");
        if (completion)
        {
            completion(note);
        }
    });
}

- (void)reapDeletedNotes:(void(^)(void))completion
{
    //Create a dispatch group to track all parts of the update to completion
    dispatch_group_t updateGroup = dispatch_group_create();

    //Copy our current note array in case it changes under us
    NSArray *notes = [self.notes copy];

    //Track this dispatch to completion
    dispatch_group_async(updateGroup, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        for (Note *note in notes)
        {
            if (note.deleted)
            {
                //Track this dispatch to completion
                dispatch_group_enter(updateGroup);
                [self deleteNote:note completion:^(Note *note, NSError *error) {
                    //Exit the dispatch group
                    dispatch_group_leave(updateGroup);
                }];
            }
        }
    });

    DDLogVerbose(@"Waiting for all reapDeletedNotes actions to complete...");
    dispatch_group_notify(updateGroup, dispatch_get_main_queue(), ^{
        DDLogVerbose(@"Completed reapDeletedNotes actions.");
        if (completion)
        {
            completion();
        }
    });
}

- (void)deleteNote:(Note *)note completion:(void(^)(Note *note, NSError *error))completion
{
    __block NSError *outerError = nil;
    
    //Create a dispatch group to track all parts of the update to completion
    dispatch_group_t updateGroup = dispatch_group_create();
    
//    //Track this dispatch to completion
//    dispatch_group_async(updateGroup, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        if (note.remoteID)
        {
            //The file exists remotely
            //Track this dispatch to completion
            dispatch_group_enter(updateGroup);
//            [self.driveManager trashFileWithID:note.remoteID completion:^(GTLDriveFile *file, NSError *error) {
            [self.driveManager retrieveAllChangesSinceChangeID:nil completion:^(NSArray *changes, NSNumber *largestChangeID, NSError *error) {
                if (error)
                {
                    DDLogError(@"Unable to move remote file to trash for note '%@'. Error: %@", note, error);
                    outerError = error;
                }
                else
                {
                    //Success, so delete the local note too
                    DDLogVerbose(@"Deleting note: '%@'", note);
                    if ([self deleteLocalFile:note.file])
                    {
                        //Update our properties on the main queue
                        //Track this dispatch to completion
                        dispatch_group_async(updateGroup, dispatch_get_main_queue(), ^{
                            [self.notes removeObject:note];
                            if (note.remoteID)
                            {
                                [self.notesByRemoteID removeObjectForKey:note.remoteID];
                            }
                            if (note.localID)
                            {
                                [self.notesByLocalID removeObjectForKey:note.localID];
                            }
                        });
                    }
                    else
                    {
                        //TODO
                    }
                }
                //Exit the dispatch group
                dispatch_group_leave(updateGroup);
            }];
        }
        else
        {
            //The note exists only locally, so delete it.
            DDLogVerbose(@"Deleting note: '%@'", note);
            if ([self deleteLocalFile:note.file])
            {
                //Update our properties on the main queue
                //Track this dispatch to completion
                dispatch_group_async(updateGroup, dispatch_get_main_queue(), ^{
                    [self.notes removeObject:note];
                    if (note.remoteID)
                    {
                        [self.notesByRemoteID removeObjectForKey:note.remoteID];
                    }
                    if (note.localID)
                    {
                        [self.notesByLocalID removeObjectForKey:note.localID];
                    }
                });
            }
            else
            {
                //TODO
            }
        }
//    });

    DDLogVerbose(@"Waiting for all deleteNote actions to complete...");
    dispatch_group_notify(updateGroup, dispatch_get_main_queue(), ^{
        DDLogVerbose(@"Completed deleteNote actions.");
        if (completion)
        {
            completion(note, outerError);
        }
    });
}

- (BOOL)deleteLocalFile:(NSURL *)file
{
    __autoreleasing NSError *error = nil;
    BOOL success = [self.grkFileManager.fileManager removeItemAtURL:file error:&error];
    if (!success)
    {
        DDLogError(@"Unable to delete local file '%@'. Error: %@", file, error);
    }
    return success;
}

- (NSArray *)sortNotes:(NSArray *)notes
{
    NSArray *retVal = [notes sortedArrayUsingComparator:^NSComparisonResult(Note *note1, Note *note2) {
        //Sort by note title, and fallback to note remoteID then localID
        NSComparisonResult retVal = [note1.title compare:note2.title];
        if (retVal == NSOrderedSame)
        {
            retVal = [note1.remoteID compare:note2.remoteID];
            if (retVal == NSOrderedSame)
            {
                retVal = [note1.localID compare:note2.localID];
            }
        }
        return retVal;
    }];

    return retVal;
}

/**
 Fetches Note objects from the given directory.
 @param directory The directory in which to locate notes.
 @return An NSArray of Note objects (or an empty NSArray if none were found).
 */
- (NSArray *)fetchNotesFromDirectory:(NSURL *)directory
{
    NSArray *retVal = nil;
    
    __autoreleasing NSError *error = nil;
    NSArray *items = [self.grkFileManager.fileManager contentsOfDirectoryAtURL:directory includingPropertiesForKeys:@[NSURLIsDirectoryKey, NSURLIsReadableKey, NSURLIsWritableKey, NSURLNameKey] options:NSDirectoryEnumerationSkipsSubdirectoryDescendants | NSDirectoryEnumerationSkipsPackageDescendants | NSDirectoryEnumerationSkipsHiddenFiles error:&error];
    
    if (items)
    {
        NSMutableArray *notes = [NSMutableArray array];
        for (NSURL *item in items)
        {
            NSNumber *isDirectoryValue;
            __autoreleasing NSError *directoryError = nil;
            BOOL directorySuccess = [item getResourceValue:&isDirectoryValue forKey:NSURLIsDirectoryKey error:&directoryError];
            if (!directorySuccess)
            {
                DDLogError(@"Unable to get NSURLIsDirectoryKey resource value for URL '%@'. Error: %@", item, directoryError);
                continue;
            }
            if ([isDirectoryValue boolValue])
            {
                DDLogVerbose(@"Item is a directory: '%@'", item);
                continue;
            }

            NSNumber *isReadableValue;
            __autoreleasing NSError *readableError = nil;
            BOOL readableSuccess = [item getResourceValue:&isReadableValue forKey:NSURLIsReadableKey error:&readableError];
            if (!readableSuccess)
            {
                DDLogError(@"Unable to get NSURLIsReadableKey resource value for URL '%@'. Error: %@", item, readableError);
                continue;
            }
            if (![isReadableValue boolValue])
            {
                DDLogVerbose(@"Item is not readable: '%@'", item);
                continue;
            }
            
            NSNumber *isWritableValue;
            __autoreleasing NSError *writableError = nil;
            BOOL writableSuccess = [item getResourceValue:&isWritableValue forKey:NSURLIsWritableKey error:&writableError];
            if (!writableSuccess)
            {
                DDLogError(@"Unable to get NSURLIsWritableKey resource value for URL '%@'. Error: %@", item, writableError);
                continue;
            }
            if (![isWritableValue boolValue])
            {
                DDLogVerbose(@"Item is not writable: '%@'", item);
                continue;
            }
            
            Note *note = [[Note alloc] init];
            note.file = item;
            [notes addObject:note];
        }
        
        retVal = notes;
    }
    else
    {
        DDLogError(@"Unable to list contents of directory '%@'. Error: %@", directory, error);
    }
    
    return retVal;
}


@end
