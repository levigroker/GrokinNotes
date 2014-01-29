//
//  MainViewController.h
//  GrokinNotes
//
//  Created by Levi Brown on 1/16/14.
//  Copyright (c) 2014 Levi Brown. All rights reserved.
//

#import <UIKit/UIKit.h>

@protocol MenuActionHanlder <NSObject>

- (void)handleMenuAction;

@end

@interface MainViewController : UIViewController <UITableViewDataSource, UITableViewDelegate>

@property (nonatomic,weak) id<MenuActionHanlder> menuActionHandler;

@end
