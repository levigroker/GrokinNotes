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

////
//// Notifications
////

/**
 The name of the notification which is sent when a changes to are made which affect the visible notes.
 */
NSString * const kNoteNotificationNoteChanges = @"NoteNotificationNoteChanges";

////
//// Notification UserInfo Keys
////

/**
 The userInfo key, for a notification, which represents the array of notes which were deleted.
 */
NSString * const kNoteNotificationInfoKeyDeletedNotes = @"NoteNotificationInfoKeyDeletedNotes";
/**
 The userInfo key, for a notification, which represents the array of notes which were updated.
 */
NSString * const kNoteNotificationInfoKeyUpdatedNotes = @"NoteNotificationInfoKeyUpdatedNotes";
/**
 The userInfo key, for a notification, which represents the array of notes which were added.
 */
NSString * const kNoteNotificationInfoKeyAddedNotes = @"NoteNotificationInfoKeyAddedNotes";

//Internals

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

    //Post a notification informing subscribers that the note has been deleted
    NSMutableDictionary *userInfo = [NSMutableDictionary dictionaryWithCapacity:1];
    [userInfo setObject:@[note] forKey:kNoteNotificationInfoKeyDeletedNotes];
    [[NSNotificationCenter defaultCenter] postNotificationName:kNoteNotificationNoteChanges object:self userInfo:userInfo];
}

- (void)synchronize:(void(^)(NSArray *errors))completion
{
    NSMutableArray *allErrors = [NSMutableArray array];
    
    [[UIApplication sharedApplication] setNetworkActivityIndicatorVisible:YES];

    DDLogVerbose(@"Synchronize: Reaping deleted notes...");
    [self reapDeletedNotes:^(NSArray *errors) {
        DDLogVerbose(@"Synchronize: Updating changes to remote...");
        [allErrors addObjectsFromArray:errors];
        [self updateDirtyNotes:^(NSArray *errors) {
            [allErrors addObjectsFromArray:errors];
            DDLogVerbose(@"Synchronize: Refreshing with changes from remote...");
            [self refreshFromRemote:^(NSArray *errors) {
                [allErrors addObjectsFromArray:errors];
                [[UIApplication sharedApplication] setNetworkActivityIndicatorVisible:NO];
                if (errors)
                {
                    DDLogError(@"Synchronize: Failed attempt with %@ error%@: %@", @(errors.count), errors.count == 1 ? @"" : @"s", errors);
                }
                else
                {
                    DDLogVerbose(@"Synchronize: Complete.");
                }
                
                if (completion)
                {
                    completion(errors);
                }
            }];
        }];
    }];
}

- (void)refreshFromRemote:(void(^)(NSArray *errors))completion
{
    //Ensure we are on the main queue
    dispatch_async(dispatch_get_main_queue(), ^{

        NSNumber *startChangeID = nil;
        if (self.lastGoogleDriveChangeID)
        {
            //Increment the change ID to +1 so we start with new changes...
            startChangeID = [NSNumber numberWithLongLong:[self.lastGoogleDriveChangeID longLongValue] + 1];
        }
    
        [self.driveManager retrieveAllChangesSinceChangeID:startChangeID completion:^(NSArray *changes, NSNumber *largestChangeID, NSError *error) {

            NSMutableArray *errors = [NSMutableArray array];
            if (error)
            {
                [errors addObject:error];
            }
            
            //Create a dispatch group to track subtask completion
            dispatch_group_t updateGroup = dispatch_group_create();

            NSMutableArray *deletedNotes = [NSMutableArray array];
            NSMutableArray *newNotes = [NSMutableArray array];
            NSMutableArray *updatedNotes = [NSMutableArray array];
            
            //Iterate over the changes in order, since they will be returned in the order they occurred
            for (GTLDriveChange *change in changes)
            {
                //The ID of the file associated with this change.
                NSString *fileID = change.fileId;
                //The actual file (if it is available (i.e. not deleted))
                GTLDriveFile *file = change.file;
                //Look up our local note by ID
                Note *note = [self.notesByRemoteID objectForKey:fileID];
                
                BOOL deleted = [change.deleted boolValue];
                BOOL trashed = [file.labels.trashed boolValue];
                
                if (deleted || trashed)
                {
                    DDLogVerbose(@"Remote file %@ with ID '%@' local note: '%@'", deleted ? @"deleted" : @"trashed", fileID, note);
                    
                    //If the note is dirty locally.
                    if (note.dirty)
                    {
                        DDLogWarn(@"Local note has changes. Ignoring update from remote.");
                        if (trashed)
                        {
                            //We choose to restore the remote version, and let the remote note be updated with the local changes
                            [self.driveManager restoreFileWithID:fileID completion:^(GTLDriveFile *file, NSError *error) {
                                if (error)
                                {
                                    DDLogError(@"Unable to restore note: '%@'. Error: %@", note, error);
                                }
                            }];
                        }
                    }
                    else
                    {
                        //The local note is not dirty, so we can just delete it
                        //The note object may also just be nil (not tracked locally)
                        if (note)
                        {
                            //Attempt to delete the local file (if this fails, we sill remove the note from our data structures)
                            [self deleteLocalFile:note.file];
                            
                            //Track the deleted note for additional processing
                            [deletedNotes addObject:note];
                            
                            DDLogVerbose(@"Deleted note: '%@'", note);
                        }
                    }
                }
                else
                {
                    //The note has updates and there are no local changes (or no local note)...
                    
                    //Only want text files
                    if ([file.mimeType isEqualToString:kMIMETypeTextPlain])
                    {
                        DDLogVerbose(@"Update avaialble from remote for remote file ID '%@'. Local note: '%@'", fileID, note);
                        
                        if (note.dirty)
                        {
                            DDLogWarn(@"Local note has changes. Ignoring update from remote.");
                        }
                        else
                        {
                            NSString *remoteMD5 = file.md5Checksum;
                            NSString *localMD5 = nil;
                            BOOL contentMatch = (remoteMD5 && (localMD5 = [note MD5]) && [remoteMD5 isEqualToString:localMD5]);
                            
                            if (contentMatch)
                            {
                                //If the content is the same, there's no need to download the file.
                                DDLogVerbose(@"Remote content matches local content (checksums: remote: '%@' local: '%@').", remoteMD5, localMD5);
                                
                                BOOL titleMatch = [note.title isEqualToString:file.title];
                                if (!titleMatch)
                                {
                                    DDLogVerbose(@"Remote title '%@' differs from local title '%@'", file.title, note.title);

                                    //Update the local title
                                    NSURL *newFile = [[note.file URLByDeletingLastPathComponent] URLByAppendingPathComponent:file.title];
                                    __autoreleasing NSError *error = nil;
                                    BOOL success = [self.grkFileManager.fileManager moveItemAtURL:note.file toURL:newFile error:&error];
                                    if (success)
                                    {
                                        note.file = newFile;
                                        //Track the updated note for additional processing
                                        [updatedNotes addObject:note];
                                    }
                                    else
                                    {
                                        //TODO: Assuming the error is due to a name conflic, we could possibly retry renaming with a unique name.
                                        //This is problematic, however, since Google Drive allows for files with the same title, and we are trying
                                        //to retain title to file name parody. If we want to allow for localID as filename (with title as an attribute)
                                        //then this would be a non-issue (except the user might be presented with the localID filename in the app
                                        //documents directory which is not ideal).
                                        [errors addObject:error];
                                    }
                                }
                            }
                            else
                            {
                                //Download the updated note into a temp directory
                                NSURL *tempDir = [self.grkFileManager tempDirectory];
                                //Track this dispatch to completion
                                dispatch_group_enter(updateGroup);
                                [self.driveManager downloadFile:file toFolder:tempDir completion:^(GTLDriveFile *file, NSURL *fileURL, NSError *error) {
                                    if (error)
                                    {
                                        [errors addObject:error];
                                    }

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

                                                //Track the updated note for additional processing
                                                [updatedNotes addObject:note];

                                                DDLogVerbose(@"Updated note: '%@'", note);
                                            }
                                            else
                                            {
                                                DDLogError(@"Unable to relocate updated note file to destination directory. Error: %@", error);
                                                if (error)
                                                {
                                                    [errors addObject:error];
                                                }
                                            }
                                        }
                                        else
                                        {
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
                                                
                                                //Track the new note for additional processing
                                                [newNotes addObject:newNote];

                                                DDLogVerbose(@"Created note: '%@'", newNote);
                                            }
                                            else
                                            {
                                                DDLogError(@"Unable to relocate new note file to destination directory. Error: %@", error);
                                                if (error)
                                                {
                                                    [errors addObject:error];
                                                }
                                            }
                                        }
                                    }
                                    
                                    //Exit the dispatch group
                                    dispatch_group_leave(updateGroup);
                                    
                                }]; //end downloadFile
                            } //end else if contentMatch
                        }
                    }
                    else
                    {
                        DDLogVerbose(@"Ignoring update from remote file (of type '%@' (expecting '%@')). File: %@", file.mimeType, kMIMETypeTextPlain, file);
                    }
                }
            } //end change for loop
            
            DDLogVerbose(@"Waiting for refresh action to complete...");
            dispatch_group_notify(updateGroup, dispatch_get_main_queue(), ^{
                DDLogVerbose(@"Completed refresh actions.");
                if (errors.count > 0)
                {
                    DDLogError(@"%@ (%@) occurred during the refresh process. %@", errors.count == 1 ? @"An error" : @"Errors", @(errors.count), errors);
                }
                else
                {
                    //We only want to save the updated ID if successfull, so we can try again to get the changes
                    if (largestChangeID)
                    {
                        self.lastGoogleDriveChangeID = largestChangeID;
                        //Store the change ID so we only update deltas since last refresh
                        [[NSUserDefaults standardUserDefaults]  setObject:self.lastGoogleDriveChangeID forKey:kDefaultsKeyGoogleDriveChangeID];
                    }
                }

                //Update our data structures with the changes
                
                BOOL deletes = deletedNotes.count > 0;
                BOOL updates = updatedNotes.count > 0;
                BOOL additions = newNotes.count > 0;
                
                //Deletes
                if (deletes)
                {
                    [self.notes removeObjectsInArray:deletedNotes];
                    [self.notesByRemoteID removeObjectsForKeys:[deletedNotes valueForKey:@"remoteID"]];
                    [self.notesByLocalID removeObjectsForKeys:[deletedNotes valueForKey:@"localID"]];
                    //Only need to manage the removal of notes from mVisibleNotes if we have no additions (if we have additions, the mVisibleNotes array will be discarded).
                    if (!additions)
                    {
                        [self.mVisibleNotes removeObjectsInArray:deletedNotes];
                    }
                }
                
                //Additions
                if (additions)
                {
                    self.mVisibleNotes = nil; //Cause the visible note array to be rebuilt, since we are adding new items (may change sort order)
                    [self.notes addObjectsFromArray:newNotes];
                    [self sortNotes:self.notes];
                    for (Note *note in newNotes)
                    {
                        if (note.remoteID)
                        {
                            [self.notesByRemoteID setObject:note forKey:note.remoteID];
                        }
                        if (note.localID)
                        {
                            [self.notesByLocalID setObject:note forKey:note.localID];
                        }
                    }
                }
                
                if (deletes || updates || additions)
                {
                    //Post a notification informing subscribers that there are changes for the notes
                    NSMutableDictionary *userInfo = [NSMutableDictionary dictionaryWithCapacity:3];
                    [userInfo setValue:deletedNotes forKey:kNoteNotificationInfoKeyDeletedNotes];
                    [userInfo setValue:updatedNotes forKey:kNoteNotificationInfoKeyUpdatedNotes];
                    [userInfo setValue:newNotes forKey:kNoteNotificationInfoKeyAddedNotes];
                    [[NSNotificationCenter defaultCenter] postNotificationName:kNoteNotificationNoteChanges object:self userInfo:userInfo];
                }

                if (completion)
                {
                    completion(errors.count > 0 ? errors : nil);
                }
            }); //End group notify
            
        }]; //End of retrieve
    });
}

- (void)createNewUniqueNote:(void(^)(Note *note, NSError *error))completion
{
    //Ensure we are on the main queue
    dispatch_async(dispatch_get_main_queue(), ^{

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

            [self.notes addObject:note];
            [self sortNotes:self.notes];
            self.mVisibleNotes = nil; //Cause our visible notes to be rebuilt since the sort order may have changed.
            
            if (note.remoteID)
            {
                [self.notesByRemoteID setObject:note forKey:note.remoteID];
            }
            if (note.localID)
            {
                [self.notesByLocalID setObject:note forKey:note.localID];
            }
            DDLogVerbose(@"Created new note: '%@'", note);
            
            //Post a notification informing subscribers that the note has been created
            NSMutableDictionary *userInfo = [NSMutableDictionary dictionaryWithCapacity:1];
            [userInfo setObject:@[note] forKey:kNoteNotificationInfoKeyAddedNotes];
            [[NSNotificationCenter defaultCenter] postNotificationName:kNoteNotificationNoteChanges object:self userInfo:userInfo];
                
            if (completion)
            {
                completion(note, nil);
            }
        }
        else
        {
            if (completion)
            {
                NSMutableDictionary *userInfo = [NSMutableDictionary dictionaryWithCapacity:2];
                [userInfo setObject:NSLocalizedString(@"Odd, I could not create a new note for you.", nil) forKey:NSLocalizedDescriptionKey];
                [userInfo setValue:fileError forKey:NSUnderlyingErrorKey];
                NSError *error = [[NSError alloc] initWithDomain:NoteManagerErrorDomain code:NoteManagerErrorBadCreate userInfo:userInfo];
                
                completion(nil, error);
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
    [self synchronize:^(NSArray *errors) {
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
        NSString *name = [NSString stringWithFormat:@"%@%@", NSLocalizedString(@"Untitled", nil), i++ == 0 ? @"" : [NSString stringWithFormat:@" %@", @(i)]];
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
                    [userInfo setObject:[NSString stringWithFormat:@"%@ (%@) %@", NSLocalizedString(@"The maximum number of attempts", nil), @(kMaxUniqueFilenameAttempts), NSLocalizedString(@"was reached before success.", nil)] forKey:NSLocalizedDescriptionKey];
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
        NSMutableArray *notes = [NSMutableArray arrayWithArray:[self fetchNotesFromDirectory:documentsDir]];
        
        [self sortNotes:notes];

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

- (void)updateDirtyNotes:(void(^)(NSArray *errors))completion
{
    //Ensure we are on the main queue
    dispatch_async(dispatch_get_main_queue(), ^{
        //Create a dispatch group to track all parts of the update to completion
        dispatch_group_t updateGroup = dispatch_group_create();
        
        NSMutableArray *errors = [NSMutableArray array];
        
        for (Note *note in self.notes)
        {
            if (note.dirty)
            {
                DDLogVerbose(@"Processing locally dirty note: %@", note);
                
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
                            [errors addObject:error];
                        }
                        else
                        {
                            //Is the title different?
                            BOOL dirty = ![note.title isEqualToString:updatedFile.title];
                            if (!dirty)
                            {
                                //Compare checksums (file content)
                                NSString *newMD5 = [note updateMD5];
                                dirty = ![oldMD5 isEqualToString:newMD5];
                            }
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
                            [errors addObject:error];
                        }
                        else
                        {
                            //Track the remote identifier
                            NSString *remoteID = createdFile.identifier;
                            [note writeRemoteID:remoteID];
                            [self.notesByRemoteID setObject:note forKey:remoteID];
                            
                            //The note may have been modified locally while we were trying to update the remote
                            
                            //Is the title different?
                            BOOL dirty = ![note.title isEqualToString:createdFile.title];
                            if (!dirty)
                            {
                                //Compare checksums (file content)
                                NSString *newMD5 = [note updateMD5];
                                dirty = ![oldMD5 isEqualToString:newMD5];
                            }
                            [note writeDirty:dirty];
                            
                            DDLogVerbose(@"Created new remote note from local note %@", note);
                        }
                        //Exit the dispatch group
                        dispatch_group_leave(updateGroup);
                    }];
                }
            }
        }
        
        DDLogVerbose(@"Waiting for all updateDirtyNotes actions to complete...");
        dispatch_group_notify(updateGroup, dispatch_get_main_queue(), ^{
            DDLogVerbose(@"Completed updateDirtyNotes actions.");
            if (completion)
            {
                completion(errors.count > 0 ? errors : nil);
            }
        });
    });
}

- (void)reapDeletedNotes:(void(^)(NSArray *errors))completion
{
    //Ensure we are on the main queue
    dispatch_async(dispatch_get_main_queue(), ^{
        //Create a dispatch group to track all parts of the update to completion
        dispatch_group_t updateGroup = dispatch_group_create();
        
        NSMutableArray *errors = [NSMutableArray array];
        
        //Copy our current note array in case it changes under us
        NSArray *notes = [self.notes copy];
        
        NSMutableArray *deletedNotes = [NSMutableArray array];
        
        for (Note *note in notes)
        {
            if (note.deleted)
            {
                if (note.remoteID)
                {
                    //The file exists remotely
                    //Track this dispatch to completion
                    dispatch_group_enter(updateGroup);
                    [self.driveManager trashFileWithID:note.remoteID completion:^(GTLDriveFile *file, NSError *error) {
                        if (error)
                        {
                            DDLogError(@"Unable to move remote file to trash for note '%@'. Error: %@", note, error);
                            [errors addObject:error];
                        }
                        else
                        {
                            //Success, so delete the local note too
                            
                            //Attempt to delete the local file (if this fails, we sill remove the note from our data structures)
                            [self deleteLocalFile:note.file];
                            
                            //NOTE: We don't send out a notification here since the note should have already been removed from the visibleNotes which the UI cares about.
                            
                            [deletedNotes addObject:note];
                            
                            DDLogVerbose(@"Deleted note: '%@'", note);
                        }
                        //Exit the dispatch group
                        dispatch_group_leave(updateGroup);
                    }];
                }
                else
                {
                    //The note exists only locally, so delete it.
                    
                    //Attempt to delete the local file (if this fails, we sill remove the note from our data structures)
                    [self deleteLocalFile:note.file];
                    
                    [deletedNotes addObject:note];
                    
                    //NOTE: We don't send out a notification here since the note should have already been removed from the visibleNotes which the UI cares about.
                    
                    DDLogVerbose(@"Deleted note: '%@'", note);
                }
            }
        }
        
        DDLogVerbose(@"Waiting for all reapDeletedNotes actions to complete...");
        dispatch_group_notify(updateGroup, dispatch_get_main_queue(), ^{
            DDLogVerbose(@"Completed reapDeletedNotes actions.");
            
            if (deletedNotes.count > 0)
            {
                [self.notes removeObjectsInArray:deletedNotes];
                [self.notesByRemoteID removeObjectsForKeys:[deletedNotes valueForKey:@"remoteID"]];
                [self.notesByLocalID removeObjectsForKeys:[deletedNotes valueForKey:@"localID"]];
                [self.mVisibleNotes removeObjectsInArray:deletedNotes];
            }
            
            if (completion)
            {
                completion(errors.count > 0 ? errors : nil);
            }
        });
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

- (void)sortNotes:(NSMutableArray *)notes
{
    [notes sortUsingComparator:^NSComparisonResult(Note *note1, Note *note2) {
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
