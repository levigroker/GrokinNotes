//
//  Note.m
//  GrokinNotes
//
//  Created by Levi Brown on 1/22/14.
//  Copyright (c) 2014 Levi Brown. All rights reserved.
//

#import "Note.h"
#import "FileMD5Hash.h"
#import "GRKFileManager.h"

static NSString * const kExtendedAttributeKeyRemoteID = @"com.levigroker.remote.id";
static NSString * const kExtendedAttributeKeyLocalID = @"com.levigroker.local.id";
static NSString * const kExtendedAttributeKeyDeleted = @"com.levigroker.local.deleted";
static NSString * const kExtendedAttributeKeyDirty = @"com.levigroker.local.dirty";

@interface Note ()

@property (nonatomic,copy,readwrite) NSString *remoteID;
@property (nonatomic,copy,readwrite) NSString *localID;
@property (nonatomic,copy,readwrite) NSString *MD5;
@property (nonatomic,assign,readwrite) BOOL deleted;
@property (nonatomic,assign,readwrite) BOOL dirty;

@end

@implementation Note

#pragma mark - Accessors

- (void)setFile:(NSURL *)file
{
    _file = file;
    
    [self readLocalID];
    [self readRemoteID];
    [self updateMD5];
    [self readDeleted];
    [self readDirty];

    NSString *nameValue;
    __autoreleasing NSError *nameError = nil;
    BOOL nameSuccess = [file getResourceValue:&nameValue forKey:NSURLNameKey error:&nameError];
    if (nameSuccess)
    {
        self.title = nameValue;
    }
    else
    {
        DDLogError(@"Unable to get NSURLNameKey resource value for URL '%@'. Error: %@", file, nameError);
    }
}

- (void)setTitle:(NSString *)title
{
    [self updateTitle:title];
}

#pragma mark - Implementation

- (NSString *)updateMD5
{
    NSString *retVal = nil;
    
    if (self.file)
    {
        CFStringRef filePath = (__bridge CFStringRef)[self.file path];
        CFStringRef md5value = FileMD5HashCreateWithPath(filePath, FileHashDefaultChunkSizeForReadingData);
        retVal = (NSString *)CFBridgingRelease(md5value);
    }
    
    self.MD5 = retVal;
    
    return retVal;
}

- (NSError *)updateTitle:(NSString *)title
{
    __autoreleasing NSError *error = nil;

    if (self.file)
    {
        GRKFileManager *grkFileManager = [[GRKFileManager alloc] init];
        NSURL *from = self.file;
        NSURL *to = [[self.file URLByDeletingLastPathComponent] URLByAppendingPathComponent:title];
        BOOL success = [from isEqual:to] || [grkFileManager.fileManager moveItemAtURL:from toURL:to error:&error];
        if (success)
        {
            _title = [title copy];

            //Save the existing metadata
            NSString *localID = self.localID;
            NSString *remoteID = self.remoteID;
            
            //Update the reference to our file
            _file = to;
            
            //Write out the local and remote IDs since the actual underlying file has changed (and the extended attributes may have been clobbered).
            if (localID)
            {
                [self writeLocalID:localID];
            }
            if (remoteID)
            {
                [self writeRemoteID:remoteID];
            }

            //Mark ourselves as dirty, if indeed we changed
            BOOL changed = ![[from lastPathComponent] isEqualToString:title];
            if (changed)
            {
                [self writeDirty:YES];
            }
        }
        else
        {
            DDLogError(@"Unable to rename file from '%@' to '%@'. Error: %@", from, to, error);
        }
    }
    else
    {
        _title = [title copy];
    }
    
    return error;
}

- (void)writeRemoteID:(NSString *)remoteID
{
    __autoreleasing NSError *error = nil;
    BOOL success = [GRKFileManager setExtendedAttribute:kExtendedAttributeKeyRemoteID forFile:self.file toValue:remoteID error:&error];
    if (success)
    {
        self.remoteID = remoteID;
    }
    else
    {
        DDLogError(@"Unable to write 'remoteID' as extented attribute. Error: %@", error);
    }
}

- (NSString *)readRemoteID
{
    NSString *retVal = nil;
    
    __autoreleasing NSError *error = nil;
    retVal = [GRKFileManager stringForExtendedAttribute:kExtendedAttributeKeyRemoteID ofFile:self.file error:&error];
    if (retVal)
    {
        self.remoteID = retVal;
    }
    else
    {
        //If we get anything besides ENOATTR (the attribute doesn't exist) then log a warning
        NSNumber *errnoValue = [error.userInfo objectForKey:kGRKFileManagerErrorKeyErrno];
        if (!errnoValue || [errnoValue intValue] != ENOATTR)
        {
            DDLogWarn(@"Unable to read 'remoteID' as extented attribute. Error: %@", error);
        }
    }
    
    return retVal;
}

- (void)writeLocalID:(NSString *)localID
{
    __autoreleasing NSError *error = nil;
    BOOL success = [GRKFileManager setExtendedAttribute:kExtendedAttributeKeyLocalID forFile:self.file toValue:localID error:&error];
    if (success)
    {
        self.localID = localID;
    }
    else
    {
        DDLogError(@"Unable to write 'localID' as extented attribute. Error: %@", error);
    }
}

- (NSString *)readLocalID
{
    NSString *retVal = nil;
    
    __autoreleasing NSError *error = nil;
    retVal = [GRKFileManager stringForExtendedAttribute:kExtendedAttributeKeyLocalID ofFile:self.file error:&error];
    if (retVal)
    {
        self.localID = retVal;
    }
    else
    {
        //If we get anything besides ENOATTR (the attribute doesn't exist) then log a warning
        NSNumber *errnoValue = [error.userInfo objectForKey:kGRKFileManagerErrorKeyErrno];
        if (!errnoValue || [errnoValue intValue] != ENOATTR)
        {
            DDLogWarn(@"Unable to read 'localID' as extented attribute. Error: %@", error);
        }
    }
    
    return retVal;
}

- (void)writeDeleted:(BOOL)deleted
{
    __autoreleasing NSError *error = nil;
    BOOL success = [GRKFileManager setExtendedAttribute:kExtendedAttributeKeyDeleted forFile:self.file toBool:deleted error:&error];
    if (success)
    {
        self.deleted = deleted;
    }
    else
    {
        DDLogError(@"Unable to write 'deleted' as extented attribute. Error: %@", error);
    }
}

- (NSNumber *)readDeleted
{
    NSNumber *retVal = nil;
    
    __autoreleasing NSError *error = nil;
    retVal = [GRKFileManager boolForExtendedAttribute:kExtendedAttributeKeyDeleted ofFile:self.file error:&error];
    if (retVal)
    {
        self.deleted = [retVal boolValue];
    }
    else
    {
        //If we get anything besides ENOATTR (the attribute doesn't exist) then log a warning
        NSNumber *errnoValue = [error.userInfo objectForKey:kGRKFileManagerErrorKeyErrno];
        if (!errnoValue || [errnoValue intValue] != ENOATTR)
        {
            DDLogWarn(@"Unable to read 'deleted' as extented attribute. Error: %@", error);
        }
    }
    
    return retVal;
}

- (void)writeDirty:(BOOL)dirty
{
    __autoreleasing NSError *error = nil;
    BOOL success = [GRKFileManager setExtendedAttribute:kExtendedAttributeKeyDirty forFile:self.file toBool:dirty error:&error];
    if (success)
    {
        self.dirty = dirty;
    }
    else
    {
        DDLogError(@"Unable to write 'dirty' as extented attribute. Error: %@", error);
    }
}

- (NSNumber *)readDirty
{
    NSNumber *retVal = nil;
    
    __autoreleasing NSError *error = nil;
    retVal = [GRKFileManager boolForExtendedAttribute:kExtendedAttributeKeyDirty ofFile:self.file error:&error];
    if (retVal)
    {
        self.dirty = [retVal boolValue];
    }
    else
    {
        //If we get anything besides ENOATTR (the attribute doesn't exist) then log a warning
        NSNumber *errnoValue = [error.userInfo objectForKey:kGRKFileManagerErrorKeyErrno];
        if (!errnoValue || [errnoValue intValue] != ENOATTR)
        {
            DDLogWarn(@"Unable to read 'dirty' as extented attribute. Error: %@", error);
        }
    }
    
    return retVal;
}

- (void)readContent:(void(^)(NSString *content, NSError *error))completion
{
    if (completion)
    {
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            NSError *error = nil;
            NSString *content = [NSString stringWithContentsOfURL:self.file encoding:NSUTF8StringEncoding error:&error];
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(content, error);
            });
        });
    }
}

- (void)writeContent:(NSString *)content completion:(void(^)(BOOL changed, NSString *content, NSError *error))completion
{
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSString *priorChecksum = [self updateMD5];
        NSError *error = nil;
        NSString *contentObj = content ?: [NSString string];
        BOOL success = [contentObj writeToURL:self.file atomically:YES encoding:NSUTF8StringEncoding error:&error];
        if (completion)
        {
            BOOL changed = NO;
            if (success)
            {
                //Write out the local and remote IDs since the actual underlying file has changed (and the extended attributes have been clobbered).
                if (self.localID)
                {
                    [self writeLocalID:self.localID];
                }
                if (self.remoteID)
                {
                    [self writeRemoteID:self.remoteID];
                }
                
                NSString *currentChecksum = [self updateMD5];
                changed = ![currentChecksum isEqualToString:priorChecksum];
                if (changed)
                {
                    [self writeDirty:YES];
                }
            }
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(changed, content, error);
            });
        }
    });
}

#pragma mark - Overrides

- (NSString *)description
{
    
    return [NSString stringWithFormat:@"[%@ <%p> title: \"%@\", dirty: %@, deleted: %@, localID \"%@\", remoteID \"%@\"]", [self class],
            self, self.title, self.dirty ? @"YES" : @"NO", self.deleted ? @"YES" : @"NO", self.localID, self.remoteID];
}

@end
