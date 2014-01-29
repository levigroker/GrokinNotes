//
//  Note.h
//  GrokinNotes
//
//  Created by Levi Brown on 1/22/14.
//  Copyright (c) 2014 Levi Brown. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface Note : NSObject

@property (nonatomic,copy) NSString *title;
@property (nonatomic,strong) NSURL *file;
@property (nonatomic,copy,readonly) NSString *remoteID;
@property (nonatomic,copy,readonly) NSString *localID;
@property (nonatomic,copy,readonly) NSString *MD5;
@property (nonatomic,assign,readonly) BOOL deleted;
@property (nonatomic,assign,readonly) BOOL dirty;

- (NSString *)updateMD5;

- (NSError *)updateTitle:(NSString *)title;

- (void)writeRemoteID:(NSString *)remoteID;
- (NSString *)readRemoteID;

- (void)writeLocalID:(NSString *)localID;
- (NSString *)readLocalID;

- (void)writeDeleted:(BOOL)deleted;
- (NSNumber *)readDeleted;

- (void)writeDirty:(BOOL)dirty;
- (NSNumber *)readDirty;

- (void)readContent:(void(^)(NSString *content, NSError *error))completion;
- (void)writeContent:(NSString *)content completion:(void(^)(BOOL changed, NSString *content, NSError *error))completion;

@end
