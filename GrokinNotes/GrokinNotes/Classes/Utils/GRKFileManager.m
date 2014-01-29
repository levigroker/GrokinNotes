//
//  GRKFileManager.m
//
//  Created by Levi Brown on 1/23/14.
//  Copyright (c) 2014 Levi Brown <mailto:levigroker@gmail.com>
//  This work is licensed under the Creative Commons Attribution 3.0
//  Unported License. To view a copy of this license, visit
//  http://creativecommons.org/licenses/by/3.0/ or send a letter to Creative
//  Commons, 444 Castro Street, Suite 900, Mountain View, California, 94041,
//  USA.
//
//  The above attribution and the included license must accompany any version
//  of the source code. Visible attribution in any binary distributable
//  including this work (or derivatives) is not required, but would be
//  appreciated.
//

#import "GRKFileManager.h"
#import "NSString+UUID.h"
#include <sys/xattr.h>

NSString * const GRKFileManagerErrorDomain = @"GRKFileManagerErrorDomain";
NSString * const kGRKFileManagerErrorKeyErrno = @"errno";
NSString * const kGRKFileManagerErrorKeyRestoreError = @"restoreError";

static NSString * const kExtendedAttributeKeyMobileBackup =  @"com.apple.MobileBackup";

NSString * const kDefaultPrivateDocumentsDirectoryName =  @"Private Documents";

@implementation GRKFileManager

#pragma mark - Class Level

+ (BOOL)setExtendedAttribute:(NSString *)attributeName forFile:(NSURL *)fileURL toValue:(NSString *)attributeValue error:(__autoreleasing NSError **)error
{
    const char *filePath = [fileURL fileSystemRepresentation];
    const char *nameStr = [attributeName cStringUsingEncoding:NSUTF8StringEncoding];
    const char *valueStr = [attributeValue cStringUsingEncoding:NSUTF8StringEncoding];
    int result = setxattr(filePath, nameStr, valueStr, strlen(valueStr), 0, 0);
    BOOL success = result == 0;
    
    if (!success)
    {
        //Handle error
        if (error)
        {
            NSString *message = [NSString stringWithFormat:@"%s", strerror(errno)];
            NSMutableDictionary *userInfo = [NSMutableDictionary dictionaryWithCapacity:1];
            [userInfo setObject:message forKey:NSLocalizedDescriptionKey];
            [userInfo setObject:[NSNumber numberWithInt:errno] forKey:kGRKFileManagerErrorKeyErrno];
            *error = [NSError errorWithDomain:GRKFileManagerErrorDomain code:GRKFileManagerErrorErrno userInfo:userInfo];
        }
    }
    
    return success;
}

+ (BOOL)setExtendedAttribute:(NSString *)attributeName forFile:(NSURL *)fileURL toBool:(BOOL)attributeValue error:(__autoreleasing NSError **)error
{
    const char *filePath = [fileURL fileSystemRepresentation];
    const char *nameStr = [attributeName cStringUsingEncoding:NSUTF8StringEncoding];
    u_int8_t attrValue = attributeValue ? 1 : 0;
    int result = setxattr(filePath, nameStr, &attrValue, sizeof(attrValue), 0, 0);
    BOOL success = result == 0;
    
    if (!success)
    {
        //Handle error
        if (error)
        {
            NSString *message = [NSString stringWithFormat:@"%s", strerror(errno)];
            NSMutableDictionary *userInfo = [NSMutableDictionary dictionaryWithCapacity:1];
            [userInfo setObject:message forKey:NSLocalizedDescriptionKey];
            [userInfo setObject:[NSNumber numberWithInt:errno] forKey:kGRKFileManagerErrorKeyErrno];
            *error = [NSError errorWithDomain:GRKFileManagerErrorDomain code:GRKFileManagerErrorErrno userInfo:userInfo];
        }
    }

    return success;
}

+ (BOOL)setSkipBackup:(BOOL)skipBackup forFile:(NSURL *)fileURL error:(__autoreleasing NSError **)error
{
    BOOL success = [self setExtendedAttribute:kExtendedAttributeKeyMobileBackup forFile:fileURL toBool:skipBackup error:error];
    return success;
}

+ (NSString *)stringForExtendedAttribute:(NSString *)attributeName ofFile:(NSURL *)fileURL error:(__autoreleasing NSError **)error
{
    NSString *retVal = nil;
    
    const char *filePath = [fileURL fileSystemRepresentation];
    const char *nameStr = [attributeName cStringUsingEncoding:NSUTF8StringEncoding];
    
    //Fetch the size of the buffer we need
    ssize_t bufferLength = getxattr(filePath, nameStr, NULL, 0, 0, 0);
    if (bufferLength < 0)
    {
        //Handle error
        if (error)
        {
            NSString *message = [NSString stringWithFormat:@"%s", strerror(errno)];
            NSMutableDictionary *userInfo = [NSMutableDictionary dictionaryWithCapacity:1];
            [userInfo setObject:message forKey:NSLocalizedDescriptionKey];
            [userInfo setObject:[NSNumber numberWithInt:errno] forKey:kGRKFileManagerErrorKeyErrno];
            *error = [NSError errorWithDomain:GRKFileManagerErrorDomain code:GRKFileManagerErrorErrno userInfo:userInfo];
        }
    }
    else
    {
        //Create our receiving buffer
        char *buffer = malloc(bufferLength);
        
        // now actually get the attribute string
        ssize_t result = getxattr(filePath, nameStr, buffer, bufferLength, 0, 0);
        if (result < 0)
        {
            //Handle error
            if (error)
            {
                NSString *message = [NSString stringWithFormat:@"%s", strerror(errno)];
                NSMutableDictionary *userInfo = [NSMutableDictionary dictionaryWithCapacity:1];
                [userInfo setObject:message forKey:NSLocalizedDescriptionKey];
                [userInfo setObject:[NSNumber numberWithInt:errno] forKey:kGRKFileManagerErrorKeyErrno];
                *error = [NSError errorWithDomain:GRKFileManagerErrorDomain code:GRKFileManagerErrorErrno userInfo:userInfo];
            }
        }
        else
        {
            retVal = [[NSString alloc] initWithBytes:buffer length:bufferLength encoding:NSUTF8StringEncoding];
        }

        free(buffer);
    }
    
    return retVal;
}

+ (NSNumber *)boolForExtendedAttribute:(NSString *)attributeName ofFile:(NSURL *)fileURL error:(__autoreleasing NSError **)error
{
    NSNumber *retVal = nil;
    
    const char *filePath = [fileURL fileSystemRepresentation];
    const char *nameStr = [attributeName cStringUsingEncoding:NSUTF8StringEncoding];
    
    u_int8_t attrValue = 0;
    ssize_t result = getxattr(filePath, nameStr, &attrValue, sizeof(attrValue), 0, 0);
    if (result < 0)
    {
        //Handle error
        if (error)
        {
            NSString *message = [NSString stringWithFormat:@"%s", strerror(errno)];
            NSMutableDictionary *userInfo = [NSMutableDictionary dictionaryWithCapacity:1];
            [userInfo setObject:message forKey:NSLocalizedDescriptionKey];
            [userInfo setObject:[NSNumber numberWithInt:errno] forKey:kGRKFileManagerErrorKeyErrno];
            *error = [NSError errorWithDomain:GRKFileManagerErrorDomain code:GRKFileManagerErrorErrno userInfo:userInfo];
        }
    }
    else
    {
        retVal = [[NSNumber alloc] initWithUnsignedChar:attrValue];
    }
    
    return retVal;
}

+ (BOOL)removeExtendedAttribute:(NSString *)attributeName ofFile:(NSURL *)fileURL error:(__autoreleasing NSError **)error
{
    const char *filePath = [fileURL fileSystemRepresentation];
    const char *nameStr = [attributeName cStringUsingEncoding:NSUTF8StringEncoding];

    int result = removexattr(filePath, nameStr, 0);
    BOOL success = result == 0;
    
    if (!success)
    {
        //Handle error
        if (error)
        {
            NSString *message = [NSString stringWithFormat:@"%s", strerror(errno)];
            NSMutableDictionary *userInfo = [NSMutableDictionary dictionaryWithCapacity:1];
            [userInfo setObject:message forKey:NSLocalizedDescriptionKey];
            [userInfo setObject:[NSNumber numberWithInt:errno] forKey:kGRKFileManagerErrorKeyErrno];
            *error = [NSError errorWithDomain:GRKFileManagerErrorDomain code:GRKFileManagerErrorErrno userInfo:userInfo];
        }
    }
    
    return success;
}

#pragma mark - Accessors

- (NSFileManager *)fileManager
{
    //Create one NSFileManager for all instances of GRKFileManager
    static dispatch_once_t onceQueue;
    static NSFileManager *fileManager = nil;
    
    dispatch_once(&onceQueue, ^{ fileManager = [[NSFileManager alloc] init]; });
    return fileManager;
}

#pragma mark - Implementation

//Modified from: http://cocoawithlove.com/2009/07/temporary-files-and-folders-in-cocoa.html
- (NSURL *)tempDirectory
{
    NSURL *retVal = nil;

    NSString *tempDirectoryTemplate = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString UUID]];
    const char *tempDirectoryTemplateCString = [tempDirectoryTemplate fileSystemRepresentation];
    char *tempDirectoryNameCString = (char *)malloc(strlen(tempDirectoryTemplateCString) + 1);
    strcpy(tempDirectoryNameCString, tempDirectoryTemplateCString);

    char *result = mkdtemp(tempDirectoryNameCString);
    if (result)
    {
        NSString *path = [self.fileManager stringWithFileSystemRepresentation:tempDirectoryNameCString length:strlen(result)];
        retVal = [NSURL fileURLWithPath:path isDirectory:YES];
    }

    free(tempDirectoryNameCString);

    return retVal;
}

- (NSURL *)documentsDirectory
{
    NSURL *retVal = [[self.fileManager URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask] lastObject];
    return retVal;
}

- (NSURL *)privateDocumentsDirectory
{
    return [self privateDocumentsDirectoryNamed:nil error:nil];
}

/**
 * http://stackoverflow.com/questions/3864823/hide-core-data-sqlite-file-when-itunes-file-sharing-is-enabled
 * http://developer.apple.com/library/ios/#qa/qa1699
 * @return The appropriate, backed up, non-user exposed, location to store application data, or nil if an error occurred.
 */
- (NSURL *)privateDocumentsDirectoryNamed:(NSString *)dirName error:(__autoreleasing NSError **)error
{
    NSURL *retVal = nil;
    dirName = dirName ?: kDefaultPrivateDocumentsDirectoryName;
    NSString *libraryPath = [NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES) lastObject];
    NSString *docPath = [libraryPath stringByAppendingPathComponent:dirName];
    
    BOOL isDirectory = NO;
    if ([self.fileManager fileExistsAtPath:docPath isDirectory:&isDirectory])
    {
        //The file exists; let's make sure it's a directory and not some random file...
        if (isDirectory)
        {
            retVal = [NSURL fileURLWithPath:docPath];
        }
        else
        {
            if (error)
            {
                NSString *message = [NSString stringWithFormat:@"%@ '%@'", NSLocalizedString(@"Existing non-directory file found at", nil), docPath];
                NSMutableDictionary *userInfo = [NSMutableDictionary dictionaryWithCapacity:1];
                [userInfo setObject:message forKey:NSLocalizedDescriptionKey];
                *error = [NSError errorWithDomain:GRKFileManagerErrorDomain code:GRKFileManagerErrorFileExists userInfo:userInfo];
            }
        }
    }
    else
    {
        //No existing directory, so we create it...
        if ([self.fileManager createDirectoryAtPath:docPath withIntermediateDirectories:YES attributes:nil error:error])
        {
            retVal = [NSURL fileURLWithPath:docPath];
        }
    }
    
    return retVal;
}

- (NSURL *)replaceFile:(NSURL *)oldFile withFile:(NSURL *)newFile error:(__autoreleasing NSError **)error
{
    NSURL *retVal = nil;
    
    if (oldFile && newFile)
    {
    
        NSURL *tempDir = [self tempDirectory];
        if (tempDir)
        {
            //First move the old file to the temp directory
            
            NSURL *tempFile = [tempDir URLByAppendingPathComponent:[oldFile lastPathComponent]];
            __autoreleasing NSError *oldMoveError = nil;
            BOOL success = [self.fileManager moveItemAtURL:oldFile toURL:tempFile error:&oldMoveError];
            if (success)
            {
                //Now move the new file into place
                __autoreleasing NSError *newMoveError = nil;
                NSURL *positionedNewFile = [[oldFile URLByDeletingLastPathComponent] URLByAppendingPathComponent:[newFile lastPathComponent]];
                success = [self.fileManager moveItemAtURL:newFile toURL:positionedNewFile error:&newMoveError];
                if (success)
                {
                    retVal = positionedNewFile;
                    //Now remove the temp dir and old file
                    __autoreleasing NSError *removeError = nil;
                    success = [self.fileManager removeItemAtURL:tempDir error:&removeError];
                    if (!success)
                    {
                        DDLogError(@"Unable to clean up temporary directory '%@'. Error: %@", tempDir, removeError);
                    }
                }
                else
                {
                    //Failing to move the new file into place, we restore the old file
                    __autoreleasing NSError *restoreError = nil;
                    success = [self.fileManager moveItemAtURL:tempFile toURL:oldFile error:&restoreError];
                    if (error)
                    {
                        if (success)
                        {
                            *error = newMoveError;
                        }
                        else
                        {
                            NSString *message = NSLocalizedString(@"Unable to move new file into position, and unable to restore original. See userInfo `NSUnderlyingErrorKey` for details on the new file relocation issue, and `kGRKFileManagerErrorKeyRestoreError` for the restore issue details.", nil);
                            NSMutableDictionary *userInfo = [NSMutableDictionary dictionaryWithCapacity:3];
                            [userInfo setObject:message forKey:NSLocalizedDescriptionKey];
                            [userInfo setObject:restoreError forKey:kGRKFileManagerErrorKeyRestoreError];
                            [userInfo setObject:newMoveError forKey:NSUnderlyingErrorKey];
                            *error = [NSError errorWithDomain:GRKFileManagerErrorDomain code:GRKFileManagerErrorBadParameter userInfo:userInfo];
                        }
                    }
                }
            }
            else
            {
                if (error)
                {
                    *error = oldMoveError;
                }
            }
        }
        else
        {
            if (error)
            {
                NSString *message = NSLocalizedString(@"Unable to create a temporary directory", nil);
                NSMutableDictionary *userInfo = [NSMutableDictionary dictionaryWithCapacity:1];
                [userInfo setObject:message forKey:NSLocalizedDescriptionKey];
                *error = [NSError errorWithDomain:GRKFileManagerErrorDomain code:GRKFileManagerErrorNoTempDir userInfo:userInfo];
            }
        }
    }
    else
    {
        if (error)
        {
            NSString *message = [NSString stringWithFormat:@"%@ oldFile: '%@', newFile: '%@'", NSLocalizedString(@"Given parameters could not be operated upon:", nil), oldFile, newFile];
            NSMutableDictionary *userInfo = [NSMutableDictionary dictionaryWithCapacity:1];
            [userInfo setObject:message forKey:NSLocalizedDescriptionKey];
            *error = [NSError errorWithDomain:GRKFileManagerErrorDomain code:GRKFileManagerErrorBadParameter userInfo:userInfo];
        }
    }
    
    return retVal;
}

@end
