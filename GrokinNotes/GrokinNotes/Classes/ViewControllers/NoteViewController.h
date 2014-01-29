//
//  NoteViewController.h
//  GrokinNotes
//
//  Created by Levi Brown on 1/22/14.
//  Copyright (c) 2014 Levi Brown. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "Note.h"

@interface NoteViewController : UIViewController <UITextFieldDelegate>

@property (nonatomic,strong) Note *note;
@property (nonatomic,assign) BOOL shouldEdit;

@end
