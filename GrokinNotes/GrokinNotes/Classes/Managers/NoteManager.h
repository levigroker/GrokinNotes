//
//  NoteManager.h
//  GrokinNotes
//
//  Created by Levi Brown on 1/22/14.
//  Copyright (c) 2014 Levi Brown. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "Note.h"
#import "GoogleDriveManager.h"

////
//// Errors
////

extern NSString * const NoteManagerErrorDomain;

typedef NS_ENUM(NSInteger, NoteManagerError) {
    NoteManagerErrorBadCreate = 1,
    NoteManagerErrorTooManyAttempts
};

////
//// Notifications
////

/**
 The name of the notification which is sent when a changes to are made which affect the visible notes.
 */
NSString * const kNoteNotificationNoteChanges;

////
//// Notification UserInfo Keys
////

/**
 The userInfo key, for a notification, which represents the array of notes which were deleted.
 */
NSString * const kNoteNotificationInfoKeyDeletedNotes;
/**
 The userInfo key, for a notification, which represents the array of notes which were updated.
 */
NSString * const kNoteNotificationInfoKeyUpdatedNotes;
/**
 The userInfo key, for a notification, which represents the array of notes which were added.
 */
NSString * const kNoteNotificationInfoKeyAddedNotes;

@interface NoteManager : NSObject

@property (nonatomic,readonly) GoogleDriveManager *driveManager;

/**
 The shared singleton instance of the NoteManager object to be used.
 
 @return The common instance of the NoteManager.
 */
+ (instancetype)shared;

/**
 Initalizes the manager with all locally stored Note information.
 
 @param completion Called once the startup proceedure completes, possibly with error.
 */
- (void)startup:(void(^)(NSError *error))completion;

/**
 Stops all recurring operations.
 */
- (void)shutdown;

/**
 Gets all notes which are currently visible to the User.
 
 @return An NSArray of Note objects to be presented to the user, in sorted order.
 */
- (NSArray *)visibleNotes;

/**
 Marks the given note as deleted and removes it from the visible notes.
 The note will be deleted from the filesystem at some time in the future.

 @param note The Note to mark as deleted.
 */
- (void)markNoteAsDeleted:(Note *)note;

/**
 Performs steps to synchronize with the remote.
 First, local changes are uploaded, then local deletes are processed, then changes from the remote are processed.
 Appropriate notifications are posted when changes to the local collections are made.
 This will also toggle the visibility of the UIApplication network activity indicator as needed.
 
 @param completion Called when the operation completes, with an array of NSError objects which may have occurred (the array will be `nil` if no errors occurred).
 */
- (void)synchronize:(void(^)(NSArray *errors))completion;

/**
 Refreshes the local notes with information from the server.
 
 @param completion Called once the refresh proceedure completes, with an array of NSError objects which may have occurred (the array will be `nil` if no errors occurred).
 @see synchronize: As the preferred option for keeping up to date with the remote since it also communicates local changes to the server.
 */
- (void)refreshFromRemote:(void(^)(NSArray *errors))completion;

/**
 Creates a new Note object with a unique title, and adds it to our internal store, sending out appropriate notifications.
 
 @param completion Called once the note is created, or error.
 */
- (void)createNewUniqueNote:(void(^)(Note *note, NSError *error))completion;

@end
