//
//  GoogleDriveManager.m
//  GrokinNotes
//
//  Created by Levi Brown on 1/16/14.
//  Copyright (c) 2014 Levi Brown. All rights reserved.
//

#import "GoogleDriveManager.h"

NSString * const GoogleDriveManagerErrorDomain = @"GoogleDriveManager";

NSString * const kMIMETypeTextPlain = @"text/plain";

static NSString * const kGoogleKeychainItemName = @"drive_notes_google_authentication";
static NSString * const kGoogleConfigurationPList = @"GoogleConfiguration";
static NSString * const kGoogleConfigurationKeyClientID = @"client_id";
static NSString * const kGoogleConfigurationKeyClientSecret = @"client_secret";

static NSString * const kGoogleMIMETypeFolder = @"application/vnd.google-apps.folder";

static NSString * const kGoogleDriveRootFolderID = @"root";

@interface GoogleDriveManager ()

@property (nonatomic,assign) BOOL initialized;
@property (nonatomic,strong) GTLServiceDrive *driveService;
@property (nonatomic,copy) NSString *clientID;
@property (nonatomic,copy) NSString *clientSecrect;

@end

@implementation GoogleDriveManager

#pragma mark - Implementation

- (NSError *)startup
{
    NSError *retVal = nil;
    
    if (!self.initialized)
    {
        NSString *configPath = [[NSBundle mainBundle] pathForResource:kGoogleConfigurationPList ofType:@"plist"];
        if (configPath.length > 0)
        {
            DDLogVerbose(@"Found Google configuration.");

            NSDictionary *config = [NSDictionary dictionaryWithContentsOfFile:configPath];
            NSString *clientID = [config valueForKey:kGoogleConfigurationKeyClientID];
            NSString *clientSecret = [config valueForKey:kGoogleConfigurationKeyClientSecret];
            if (clientID.length > 0 && clientSecret.length > 0)
            {
                self.clientID = clientID;
                self.clientSecrect = clientSecret;
                
                //Initialize the drive service & load existing credentials from the keychain if available
                self.driveService = [[GTLServiceDrive alloc] init];
                self.driveService.authorizer = [GTMOAuth2ViewControllerTouch authForGoogleFromKeychainForName:kGoogleKeychainItemName clientID:self.clientID clientSecret:self.clientSecrect];
                //Fetch all pages of items.
                //NOTE: This could be a performance concern moving forward, but hadling pages of content is currently out of scope.
                self.driveService.shouldFetchNextPages = YES;
                self.initialized = YES;
            }
            else
            {
                NSString *message = [NSString stringWithFormat:@"Unable to read needed configuration from '%@.plist' in main bundle. Please be sure the file is present and has values specified for the '%@' and '%@' top level keys.", kGoogleConfigurationPList, kGoogleConfigurationKeyClientID, kGoogleConfigurationKeyClientSecret];
                DDLogError(@"%@", message);
                NSMutableDictionary *userInfo = [NSMutableDictionary dictionaryWithCapacity:1];
                [userInfo setObject:message forKey:NSLocalizedDescriptionKey];
                retVal = [NSError errorWithDomain:GoogleDriveManagerErrorDomain code:GoogleDriveManagerErrorBadConfig userInfo:userInfo];
            }
        }
        else
        {
            NSString *message = [NSString stringWithFormat:@"No Google configuration plist ('%@.plist') found in the main bundle.", kGoogleConfigurationPList];
            DDLogError(@"%@", message);
            NSMutableDictionary *userInfo = [NSMutableDictionary dictionaryWithCapacity:1];
            [userInfo setObject:message forKey:NSLocalizedDescriptionKey];
            retVal = [NSError errorWithDomain:GoogleDriveManagerErrorDomain code:GoogleDriveManagerErrorNoConfig userInfo:userInfo];
        }
    }
    
    if (retVal)
    {
        self.clientID = nil;
        self.clientSecrect = nil;
        self.initialized = NO;
    }
    
    return retVal;
}

- (BOOL)authorized
{
    BOOL retVal = [((GTMOAuth2Authentication *)self.driveService.authorizer) canAuthorize];
    return retVal;
}

- (void)signout
{
    [GTMOAuth2ViewControllerTouch removeAuthFromKeychainForName:kGoogleKeychainItemName];
    self.driveService.authorizer = nil;
}

// Creates the auth controller for authorizing access to Google Drive.
- (GTMOAuth2ViewControllerTouch *)createAuthControllerWithCompletion:(void(^)(GTMOAuth2ViewControllerTouch *viewController, NSError *error))completion
{
    GTMOAuth2ViewControllerTouch *authController = [GTMOAuth2ViewControllerTouch controllerWithScope:kGTLAuthScopeDriveFile clientID:self.clientID clientSecret:self.clientSecrect keychainItemName:kGoogleKeychainItemName completionHandler:^(GTMOAuth2ViewControllerTouch *viewController, GTMOAuth2Authentication *auth, NSError *error) {
        //Make sure we are on the main queue
        dispatch_async(dispatch_get_main_queue(), ^{
            //Handle completion of the authorization process, and updates the Drive service with the new credentials.
            self.driveService.authorizer = error ? nil : auth;

            //Call any passed in completion handler
            if (completion)
            {
                completion(viewController, error);
            }
        });
    }];

    return authController;
}

- (void)createFolderNamed:(NSString *)name inFolder:(GTLDriveFile *)folder completion:(void(^)(GTLDriveFile *updatedFile, NSError *error))completion
{
    if (self.initialized)
    {
        NSString *parentID = folder.identifier ?: kGoogleDriveRootFolderID;
        GTLDriveParentReference *parent = [GTLDriveParentReference object];
        parent.identifier = parentID;

        GTLDriveFile *folder = [GTLDriveFile object];
        folder.title = name;
        folder.mimeType = kGoogleMIMETypeFolder;
        folder.parents = @[parent];

        GTLQueryDrive *query = [GTLQueryDrive queryForFilesInsertWithObject:folder uploadParameters:nil];
        [self.driveService executeQuery:query completionHandler:^(GTLServiceTicket *ticket, GTLDriveFile *updatedFile, NSError *error) {
            if (completion)
            {
                completion(updatedFile, error);
            }
        }];
    }
    else
    {
        NSString *message = @"Drive services not initialized.";
        DDLogError(@"%@", message);
        if (completion)
        {
            NSMutableDictionary *userInfo = [NSMutableDictionary dictionaryWithCapacity:1];
            [userInfo setObject:message forKey:NSLocalizedDescriptionKey];
            NSError *error = [NSError errorWithDomain:GoogleDriveManagerErrorDomain code:GoogleDriveManagerErrorNotInitialized userInfo:userInfo];
            completion(nil, error);
        }
    }
}

- (void)fileListingForFolder:(GTLDriveFile *)folder filesOfMIMEType:(NSString *)mimeType completion:(void(^)(NSArray *files, NSError *error))completion
{
    if (self.initialized)
    {
        if (completion)
        {
            [self listingForFolder:folder filesOfMIMEType:mimeType completion:^(GTLDriveFileList *files, NSError *error) {
                NSArray *items = files.items;
                completion(items, error);
            }];
        }
    }
    else
    {
        NSString *message = @"Drive services not initialized.";
        DDLogError(@"%@", message);
        if (completion)
        {
            NSMutableDictionary *userInfo = [NSMutableDictionary dictionaryWithCapacity:1];
            [userInfo setObject:message forKey:NSLocalizedDescriptionKey];
            NSError *error = [NSError errorWithDomain:GoogleDriveManagerErrorDomain code:GoogleDriveManagerErrorNotInitialized userInfo:userInfo];
            completion(nil, error);
        }
    }
}

- (void)listingForFolder:(GTLDriveFile *)folder filesOfMIMEType:(NSString *)mimeType completion:(void(^)(GTLDriveFileList *files, NSError *error))completion
{
    if (self.initialized)
    {
        if (completion)
        {
            NSString *parentID = folder.identifier ?: kGoogleDriveRootFolderID;
            
            GTLQueryDrive *query = [GTLQueryDrive queryForFilesList];
            query.q = [NSString stringWithFormat:@"'%@' in parents", parentID];
            if (mimeType.length > 0)
            {
                query.q = [query.q stringByAppendingFormat:@" and mimeType = '%@'", mimeType];
            }
            [self.driveService executeQuery:query completionHandler:^(GTLServiceTicket *ticket, GTLDriveFileList *files, NSError *error) {
                completion(files, error);
            }];
        }
    }
    else
    {
        NSString *message = @"Drive services not initialized.";
        DDLogError(@"%@", message);
        if (completion)
        {
            NSMutableDictionary *userInfo = [NSMutableDictionary dictionaryWithCapacity:1];
            [userInfo setObject:message forKey:NSLocalizedDescriptionKey];
            NSError *error = [NSError errorWithDomain:GoogleDriveManagerErrorDomain code:GoogleDriveManagerErrorNotInitialized userInfo:userInfo];
            completion(nil, error);
        }
    }
}

//Assumes the given file is a file (not a folder) and the given folder is appropriate (not nil, and represents a writable location in the filesystem)
- (void)downloadFile:(GTLDriveFile *)file toFolder:(NSURL *)folder completion:(void(^)(GTLDriveFile *file, NSURL *fileURL, NSError *error))completion
{
    if (file && folder)
    {
        NSURL *fileURL = [folder URLByAppendingPathComponent:file.title];

        if (self.initialized)
        {
            GTMHTTPFetcher *fetcher = [self.driveService.fetcherService fetcherWithURLString:file.downloadUrl];
            fetcher.retryEnabled = YES;
            fetcher.shouldFetchInBackground = YES;
            fetcher.downloadPath = [fileURL path];
            [fetcher beginFetchWithCompletionHandler:^(NSData *data, NSError *error) {
                if (completion)
                {
                    completion(file, fileURL, error);
                }
            }];
        }
        else
        {
            NSString *message = @"Drive services not initialized.";
            DDLogError(@"%@", message);
            if (completion)
            {
                NSMutableDictionary *userInfo = [NSMutableDictionary dictionaryWithCapacity:1];
                [userInfo setObject:message forKey:NSLocalizedDescriptionKey];
                NSError *error = [NSError errorWithDomain:GoogleDriveManagerErrorDomain code:GoogleDriveManagerErrorNotInitialized userInfo:userInfo];
                completion(file, fileURL, error);
            }
        }
    }
    else
    {
        NSString *message = [NSString stringWithFormat:@"Given file was '%@' and destination folder was '%@'.", file, folder];
        DDLogError(@"%@", message);
        if (completion)
        {
            NSMutableDictionary *userInfo = [NSMutableDictionary dictionaryWithCapacity:1];
            [userInfo setObject:message forKey:NSLocalizedDescriptionKey];
            NSError *error = [NSError errorWithDomain:GoogleDriveManagerErrorDomain code:GoogleDriveManagerErrorBadParameter userInfo:userInfo];
            completion(file, nil, error);
        }
    }
}

- (void)createFile:(NSURL *)file withMIMEType:(NSString *)mimeType inFolder:(GTLDriveFile *)folder completion:(void(^)(GTLDriveFile *createdFile, NSError *error))completion
{
    if (self.initialized)
    {
        GTLDriveFile *metadata = [GTLDriveFile object];
        metadata.title = [file lastPathComponent];
        
        //Setup the parent relationship
        if (folder)
        {
            GTLDriveParentReference *parent = [GTLDriveParentReference object];
            parent.identifier = folder.identifier;
            metadata.parents = @[parent];
        }
        
        //Default MIME type
        NSString *targetMIMEType = mimeType;
        if (mimeType.length == 0)
        {
            targetMIMEType = kMIMETypeTextPlain;
        }
        
        __autoreleasing NSError *fileError = nil;
        NSFileHandle *fileHandle = [NSFileHandle fileHandleForReadingFromURL:file error:&fileError];
        if (fileHandle)
        {
            GTLUploadParameters *uploadParameters = [GTLUploadParameters uploadParametersWithFileHandle:fileHandle MIMEType:targetMIMEType];
            
            GTLQueryDrive *query = [GTLQueryDrive queryForFilesInsertWithObject:metadata uploadParameters:uploadParameters];
            
            [self.driveService executeQuery:query completionHandler:^(GTLServiceTicket *ticket, GTLDriveFile *createdFile, NSError *error) {
                if (completion)
                {
                    completion(createdFile, error);
                }
            }];
        }
        else
        {
            if (completion)
            {
                completion(nil, fileError);
            }
        }
    }
    else
    {
        NSString *message = @"Drive services not initialized.";
        DDLogError(@"%@", message);
        if (completion)
        {
            NSMutableDictionary *userInfo = [NSMutableDictionary dictionaryWithCapacity:1];
            [userInfo setObject:message forKey:NSLocalizedDescriptionKey];
            NSError *error = [NSError errorWithDomain:GoogleDriveManagerErrorDomain code:GoogleDriveManagerErrorNotInitialized userInfo:userInfo];
            completion(nil, error);
        }
    }
}

- (void)updateDriveFile:(GTLDriveFile *)driveFile fromFileURL:(NSURL *)fileURL completion:(void(^)(GTLDriveFile *updatedFile, NSError *error))completion
{
    if (self.initialized)
    {
        __autoreleasing NSError *fileError = nil;
        NSFileHandle *fileHandle = [NSFileHandle fileHandleForReadingFromURL:fileURL error:&fileError];
        if (fileHandle)
        {
            GTLUploadParameters *uploadParameters = [GTLUploadParameters uploadParametersWithFileHandle:fileHandle MIMEType:driveFile.mimeType];
            
            GTLQueryDrive *query = [GTLQueryDrive queryForFilesUpdateWithObject:driveFile fileId:driveFile.identifier uploadParameters:uploadParameters];

            
            [self.driveService executeQuery:query completionHandler:^(GTLServiceTicket *ticket, GTLDriveFile *updatedFile, NSError *error) {
                if (completion)
                {
                    completion(updatedFile, error);
                }
            }];
        }
        else
        {
            if (completion)
            {
                completion(nil, fileError);
            }
        }
    }
    else
    {
        NSString *message = @"Drive services not initialized.";
        DDLogError(@"%@", message);
        if (completion)
        {
            NSMutableDictionary *userInfo = [NSMutableDictionary dictionaryWithCapacity:1];
            [userInfo setObject:message forKey:NSLocalizedDescriptionKey];
            NSError *error = [NSError errorWithDomain:GoogleDriveManagerErrorDomain code:GoogleDriveManagerErrorNotInitialized userInfo:userInfo];
            completion(nil, error);
        }
    }
}

- (void)uploadFile:(NSURL *)file withMIMEType:(NSString *)mimeType toFolder:(GTLDriveFile *)folder completion:(void(^)(GTLDriveFile *updatedFile, NSError *error))completion
{
    if (self.initialized)
    {
        //Check to see if the file already exists, or not, in the parent folder
        [self listingForFolder:folder filesOfMIMEType:mimeType completion:^(GTLDriveFileList *files, NSError *error) {
            NSArray *items = files.items;
            if (items)
            {
                GTLDriveFile *metadata = [GTLDriveFile object];
                metadata.title = [file lastPathComponent];
                
                //Setup the parent relationship
                if (folder)
                {
                    GTLDriveParentReference *parent = [GTLDriveParentReference object];
                    parent.identifier = folder.identifier;
                    metadata.parents = @[parent];
                }
                
                //Default MIME type
                NSString *targetMIMEType = mimeType;
                if (mimeType.length == 0)
                {
                    targetMIMEType = kMIMETypeTextPlain;
                }
                
                __autoreleasing NSError *fileError = nil;
                NSFileHandle *fileHandle = [NSFileHandle fileHandleForReadingFromURL:file error:&fileError];
                if (fileHandle)
                {
                    GTLUploadParameters *uploadParameters = [GTLUploadParameters uploadParametersWithFileHandle:fileHandle MIMEType:targetMIMEType];

                    BOOL exists = NO;
                    GTLQueryDrive *query;
                    
                    for (GTLDriveFile *item in items)
                    {
                        if ([item.title isEqualToString:metadata.title])
                        {
                            exists = YES;
                            metadata = item;
                            break;
                        }
                    }
                    
                    if (exists)
                    {
                        query = [GTLQueryDrive queryForFilesUpdateWithObject:metadata fileId:metadata.identifier uploadParameters:uploadParameters];
                    }
                    else
                    {
                        query = [GTLQueryDrive queryForFilesInsertWithObject:metadata uploadParameters:uploadParameters];
                    }

                    [self.driveService executeQuery:query completionHandler:^(GTLServiceTicket *ticket, GTLDriveFile *updatedFile, NSError *error) {
                        if (completion)
                        {
                            completion(updatedFile, error);
                        }
                    }];
                }
                else
                {
                    if (completion)
                    {
                        completion(nil, fileError);
                    }
                }
            }
            else
            {
                if (completion)
                {
                    completion(nil, error);
                }
            }
        }];
    }
    else
    {
        NSString *message = @"Drive services not initialized.";
        DDLogError(@"%@", message);
        if (completion)
        {
            NSMutableDictionary *userInfo = [NSMutableDictionary dictionaryWithCapacity:1];
            [userInfo setObject:message forKey:NSLocalizedDescriptionKey];
            NSError *error = [NSError errorWithDomain:GoogleDriveManagerErrorDomain code:GoogleDriveManagerErrorNotInitialized userInfo:userInfo];
            completion(nil, error);
        }
    }
}

- (void)trashFileWithID:(NSString *)fileID completion:(void(^)(GTLDriveFile *file, NSError *error))completion
{
    if (self.initialized)
    {
        GTLQueryDrive *query = [GTLQueryDrive queryForFilesTrashWithFileId:fileID];
        [self.driveService executeQuery:query completionHandler:^(GTLServiceTicket *ticket, GTLDriveFile *file, NSError *error) {
            if (completion)
            {
                completion(file, error);
            }
        }];
    }
    else
    {
        NSString *message = @"Drive services not initialized.";
        DDLogError(@"%@", message);
        if (completion)
        {
            NSMutableDictionary *userInfo = [NSMutableDictionary dictionaryWithCapacity:1];
            [userInfo setObject:message forKey:NSLocalizedDescriptionKey];
            NSError *error = [NSError errorWithDomain:GoogleDriveManagerErrorDomain code:GoogleDriveManagerErrorNotInitialized userInfo:userInfo];
            completion(nil, error);
        }
    }
}

- (void)restoreFileWithID:(NSString *)fileID completion:(void(^)(GTLDriveFile *file, NSError *error))completion
{
    if (self.initialized)
    {
        GTLQueryDrive *query = [GTLQueryDrive queryForFilesUntrashWithFileId:fileID];
        [self.driveService executeQuery:query completionHandler:^(GTLServiceTicket *ticket, GTLDriveFile *file, NSError *error) {
            if (completion)
            {
                completion(file, error);
            }
        }];
    }
    else
    {
        NSString *message = @"Drive services not initialized.";
        DDLogError(@"%@", message);
        if (completion)
        {
            NSMutableDictionary *userInfo = [NSMutableDictionary dictionaryWithCapacity:1];
            [userInfo setObject:message forKey:NSLocalizedDescriptionKey];
            NSError *error = [NSError errorWithDomain:GoogleDriveManagerErrorDomain code:GoogleDriveManagerErrorNotInitialized userInfo:userInfo];
            completion(nil, error);
        }
    }
}

- (void)retrieveAllChangesSinceChangeID:(NSNumber *)startChangeID completion:(void (^)(NSArray *changes, NSNumber *largestChangeID, NSError *error))completion
{
    if (self.initialized)
    {
        if (completion)
        {
            //TODO: Receives all changes to the entire drive since the change ID. It would be nice to be able to limit this to files of a particular type, and/or specific directories.
            GTLQueryDrive *query = [GTLQueryDrive queryForChangesList];
            if (startChangeID)
            {
                query.startChangeId = [startChangeID longLongValue];
            }
            
            [self.driveService executeQuery:query completionHandler:^(GTLServiceTicket *ticket, GTLDriveChangeList *changeList, NSError *error) {
                completion(changeList.items, changeList.largestChangeId, error);
            }];
        }
    }
    else
    {
        NSString *message = @"Drive services not initialized.";
        DDLogError(@"%@", message);
        if (completion)
        {
            NSMutableDictionary *userInfo = [NSMutableDictionary dictionaryWithCapacity:1];
            [userInfo setObject:message forKey:NSLocalizedDescriptionKey];
            NSError *error = [NSError errorWithDomain:GoogleDriveManagerErrorDomain code:GoogleDriveManagerErrorNotInitialized userInfo:userInfo];
            completion(nil, nil, error);
        }
    }
}

@end
