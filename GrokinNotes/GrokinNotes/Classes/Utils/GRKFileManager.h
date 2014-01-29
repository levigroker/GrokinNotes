//
//  GRKFileManager.h
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

#import <Foundation/Foundation.h>

extern NSString * const kDefaultPrivateDocumentsDirectoryName;

extern NSString * const GRKFileManagerErrorDomain;
extern NSString * const kGRKFileManagerErrorKeyErrno;
extern NSString * const kGRKFileManagerErrorKeyRestoreError;

/**
 Enum for errors returned by `GRKFileManager`.
 */
typedef NS_ENUM(NSInteger, GRKFileManagerError) {
    /**
     Underlying errors from the system errno global, whose value is available as an NSNumber stored in the user data with key `kGRKFileManagerErrorKeyErrno`.
     */
    GRKFileManagerErrorErrno = 1000,
    /**
     A file with a name collision exists.
     */
    GRKFileManagerErrorFileExists,
    /**
     The given parameter(s) could not be operated on.
     */
    GRKFileManagerErrorBadParameter,
    /**
     A temporary directory could not be created.
     */
    GRKFileManagerErrorNoTempDir
};

@interface GRKFileManager : NSObject

/**
 The instance of a NSFileManager used by all instances of GRKFileManager
 */
@property (nonatomic,readonly) NSFileManager *fileManager;

/**
 Sets a string value for a filesystem extended atribute on the given file.
 @param attributeName  The name of the extended attribute to set.
 @param fileURL        The fileURL representing the file on the filesystem whose extented attribute to set.
 @param attributeValue The string value to set for the extended attribute.
 @param error          A handle to an NSError object to recieve any error resulting from the operation. Can be nil.
 @return A boolean indicating if the operation was successful or not.
 */
+ (BOOL)setExtendedAttribute:(NSString *)attributeName forFile:(NSURL *)fileURL toValue:(NSString *)attributeValue error:(__autoreleasing NSError **)error;

/**
 Sets a boolean value for a filesystem extended atribute on the given file.
 @param attributeName  The name of the extended attribute to set.
 @param fileURL        The fileURL representing the file on the filesystem whose extented attribute to set.
 @param attributeValue The boolean value to set for the extended attribute.
 @param error          A handle to an NSError object to recieve any error resulting from the operation. Can be nil.
 @return A boolean indicating if the operation was successful or not.
 */
+ (BOOL)setExtendedAttribute:(NSString *)attributeName forFile:(NSURL *)fileURL toBool:(BOOL)attributeValue error:(__autoreleasing NSError **)error;

/**
 Sets the extended attribute indicating if the specified file should be skipped in a backup operation.
 @param skipBackup If `YES` the file will not be backed up when the device is backed up.
 @param fileURL    The fileURL representing the file on the filesystem whose extented attribute to set.
 @param error          A handle to an NSError object to recieve any error resulting from the operation. Can be nil.
 @return A boolean indicating if the operation was successful or not.
 */
+ (BOOL)setSkipBackup:(BOOL)skipBackup forFile:(NSURL *)fileURL error:(__autoreleasing NSError **)error;

/**
 Retrieves the string value associated with the given extended attribute.
 
 @param attributeName The name of the extended attribute to get.
 @param fileURL       The fileURL representing the file on the filesystem whose extented attribute to get.
 @param error         A handle to an NSError object to recieve any error resulting from the operation. Can be nil.
 
 @return An NSString with the value of the attribute, or `nil` if an error occurred.
 */
+ (NSString *)stringForExtendedAttribute:(NSString *)attributeName ofFile:(NSURL *)fileURL error:(__autoreleasing NSError **)error;

/**
 Retrieves the boolean value (as an NSNumber) associated with the given extended attribute.
 
 @param attributeName The name of the extended attribute to get.
 @param fileURL       The fileURL representing the file on the filesystem whose extented attribute to get.
 @param error         A handle to an NSError object to recieve any error resulting from the operation. Can be nil.
 
 @return An NSNumber representing a BOOL, or `nil` if an error occurred.
 */
+ (NSNumber *)boolForExtendedAttribute:(NSString *)attributeName ofFile:(NSURL *)fileURL error:(__autoreleasing NSError **)error;

/**
 Removes a specified filesystem extended atribute on the given file.
 @param attributeName  The name of the extended attribute to set.
 @param fileURL        The fileURL representing the file on the filesystem whose extented attribute to set.
 @param error          A handle to an NSError object to recieve any error resulting from the operation. Can be nil.
 @return A boolean indicating if the operation was successful or not.
 */
+ (BOOL)removeExtendedAttribute:(NSString *)attributeName ofFile:(NSURL *)fileURL error:(__autoreleasing NSError **)error;

/**
 Creates a unique directory for temporary file use.
 @return A fileURL to a newly created, unique, temporary directory.
 */
- (NSURL *)tempDirectory;

/**
 The Application's Documents directory (NSDocumentDirectory)
 @return A fileURL representing the current application's Documents directory.
 */
- (NSURL *)documentsDirectory;

/**
 Creates an appropriate, backed up, non-user exposed, location to store application data, or nil if an error occurred.
 @return The fileURL representing the appropriate directory to use for private documents, or `nil` if an error occurred.
 @see kDefaultPrivateDocumentsDirectoryName Which is used for the directory name.
 @see privateDocumentsDirectoryNamed:error:
 */
- (NSURL *)privateDocumentsDirectory;

/**
 Creates an appropriate, backed up, non-user exposed, location to store application data which should not be visible to the user.
 @param dirName The directory name for the private documents directory. If `nil` then `kDefaultPrivateDocumentsDirectoryName` will be used.
 @param error   If the directory could not be created.
 @return The fileURL representing the appropriate directory to use for private documents, or `nil` if an error occurred.
 @see kDefaultPrivateDocumentsDirectoryName Which is used for the directory name.
 @see privateDocumentsDirectory
 */
- (NSURL *)privateDocumentsDirectoryNamed:(NSString *)dirName error:(__autoreleasing NSError **)error;

/**
 Atomically replaces the given file with a new one.
 This will move the old file to a temporary location, move the new file into the old file's original location, and then delete the old file.
 If an issue occurs while moving the new file into position, an attempt will be made to restore the old file to its original location.
 This differs from NSFileManager's - (BOOL)replaceItemAtURL:withItemAtURL:backupItemName:options:resultingItemURL:error: in that the new file's name will be preserved if it differs from the old file.
 NOTE: the medatata associated with the new file is left intact and the old file metadata is discarded (this includes extended attributes).
 
 @param oldFile The file URL representing the file to be replaced.
 @param newFile The file URL representing the file to be moved into the location of the old file.
 @param error   The addres of an NSError* to receive any errors should they occur. Can be `nil`.

 @return Returns the file URL representing the new file in the destination location.
 */
- (NSURL *)replaceFile:(NSURL *)oldFile withFile:(NSURL *)newFile error:(__autoreleasing NSError **)error;

@end
