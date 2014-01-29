//
//  GoogleDriveManager.h
//  GrokinNotes
//
//  Created by Levi Brown on 1/16/14.
//  Copyright (c) 2014 Levi Brown. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "GTLDrive.h"
#import "GTMOAuth2ViewControllerTouch.h"

extern NSString * const GoogleDriveManagerErrorDomain;

typedef NS_ENUM(NSInteger, GoogleDriveManagerError) {
    GoogleDriveManagerErrorNoConfig = 1,
    GoogleDriveManagerErrorBadConfig,
    GoogleDriveManagerErrorNotInitialized,
    GoogleDriveManagerErrorNotAuthorized,
    GoogleDriveManagerErrorBadParameter
};

NSString * const kMIMETypeTextPlain;

@interface GoogleDriveManager : NSObject

/**
 Has the manager been initialized?
 @see startup
 */
@property (nonatomic,assign,readonly) BOOL initialized;

/**
 Creates the needed resources and configures the manager for use
 @see initialized
 @return If an error occurred on startup, it will be returned.
 */
- (NSError *)startup;

/**
 Do we have an authorized session for the user?
 
 @return `YES` indicates we have valid authorization credentials.
 */
- (BOOL)authorized;

/**
 Signs the user out from Google Drive and removes locally stored credentials.
 */
- (void)signout;

/**
 Creates the auth controller for authorizing access to Google Drive.
 
 @param completion A block which will be executed once the user dismisses the view controller which was presented.
 
 @return A new GTMOAuth2ViewControllerTouch view controller to be presented to the user.
 */
- (GTMOAuth2ViewControllerTouch *)createAuthControllerWithCompletion:(void(^)(GTMOAuth2ViewControllerTouch *viewController, NSError *error))completion;

/**
 Creates a folder in Google Drive.
 
 @param name       The name of the folder which will be created.
 @param folder     The parent directory to place the new folder (if `nil` the folder will be created at root level).
 @param completion Called once the operation completes, with the metadata about the created folder, or error.
 */
- (void)createFolderNamed:(NSString *)name inFolder:(GTLDriveFile *)folder completion:(void(^)(GTLDriveFile *updatedFile, NSError *error))completion;

/**
 Gets a listing of all files of the given MIME type in the given parent directory.
 
 @param folder     The parent directory to get a file listing for (if `nil` the root directory will be queried).
 @param mimeType   The MIME type used to filter the listing. If `nil` all contents of the parent directory will be listed.
 @param completion Called once the operation completes, with the array of `GTLDriveFile` objects representing the contents of the parent directory, or error.
 */
- (void)fileListingForFolder:(GTLDriveFile *)folder filesOfMIMEType:(NSString *)mimeType completion:(void(^)(NSArray *files, NSError *error))completion;

/**
 Gets a listing of all files of the given MIME type in the given parent directory.
 
 @param folder     The parent directory to get a file listing for (if `nil` the root directory will be queried).
 @param mimeType   The MIME type used to filter the listing. If `nil` all contents of the parent directory will be listed.
 @param completion Called once the operation completes, with the `GTLDriveFileList` object representing the contents of the parent directory, or error.
 */
- (void)listingForFolder:(GTLDriveFile *)folder filesOfMIMEType:(NSString *)mimeType completion:(void(^)(GTLDriveFileList *files, NSError *error))completion;

//Assumes the given file is a file (not a folder) and the given folder is appropriate (not nil, and represents a writable location in the filesystem)
/**
 Downloads the specified file from Google Drive to the specified local directory.
 
 @param file       The `GTLDriveFile` representing the file on Google Drive to download.
 @param folder     A URL representing the local destination parent directory.
 @param completion Called once the operation completes, with the `GTLDriveFile` representing the downloaded file, the fileURL representing the local file which was downloaded, or error.
 */
- (void)downloadFile:(GTLDriveFile *)file toFolder:(NSURL *)folder completion:(void(^)(GTLDriveFile *file, NSURL *fileURL, NSError *error))completion;

/**
 Creates a file in Google Drive in the specified parent folder and with the given MIME type.
 
 @param file       The URL representing the local file content to create on Google Drive.
 @param mimeType   The MIME type to upload the file as.
 @param folder     The `GTLDriveFile` representing the parent directory to receive the uploaded file (if `nil` the file will be uploaded to the root directory).
 @param completion Called once the operation completes, with the `GTLDriveFile` representing the uploaded/updated file, or error.
 */
- (void)createFile:(NSURL *)file withMIMEType:(NSString *)mimeType inFolder:(GTLDriveFile *)folder completion:(void(^)(GTLDriveFile *createdFile, NSError *error))completion;

/**
 Updates an existing file on Google Drive with new content from the specified local file.
 
 @param driveFile  The `GTLDriveFile` representing the existing file to be updated.
 @param fileURL    A URL specifying the local file whose contents to use to update the existing Google Drive file.
 @param completion Called once the operation completes, with the `GTLDriveFile` representing the uploaded/updated file, or error.
 */
- (void)updateDriveFile:(GTLDriveFile *)driveFile fromFileURL:(NSURL *)fileURL completion:(void(^)(GTLDriveFile *updatedFile, NSError *error))completion;

/**
 Creates or updates a file on Google Drive.
 
 @param file       A URL representing the file to be uploaded to/updated on Google Drive.
 @param mimeType   The MIME type to upload the file as.
 @param folder     The `GTLDriveFile` representing the parent directory to receive the uploaded file (if `nil` the file will be uploaded to the root directory).
 @param completion Called once the operation completes, with the `GTLDriveFile` representing the uploaded/updated file, or error.
 */
- (void)uploadFile:(NSURL *)file withMIMEType:(NSString *)mimeType toFolder:(GTLDriveFile *)folder completion:(void(^)(GTLDriveFile *updatedFile, NSError *error))completion;

/**
 Moves the specified file to Google Drive trash.
 
 @param file       The `GTLDriveFile` to be moved to the trash.
 @param completion Called once the operation completes, with the `GTLDriveFile` representing the file which was trashed, or error.
 */
- (void)trashFileWithID:(NSString *)fileID completion:(void(^)(GTLDriveFile *file, NSError *error))completion;

/**
 Restores the specified file from the Google Drive trash.
 
 @param file       The `GTLDriveFile` to be restored from the trash.
 @param completion Called once the operation completes, with the `GTLDriveFile` representing the file which was restored, or error.
 */
- (void)restoreFileWithID:(NSString *)fileID completion:(void(^)(GTLDriveFile *file, NSError *error))completion;

/**
 Retrieves a list of changes since the given change ID.
 
 @param startChangeID An NSNumber representing a long long identifying the change ID to start with when performing the query. If `nil` all changes will be returned.
 @param completion    Called once the operation completes, with `changes` an NSArray of `GTLDriveChange` objects representing the changed items, `largestChangeID` an NSNumber representing a long long which identifies the ending change ID.
 */
- (void)retrieveAllChangesSinceChangeID:(NSNumber *)startChangeID completion:(void (^)(NSArray *changes, NSNumber *largestChangeID, NSError *error))completion;

@end
