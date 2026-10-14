//
//  MCCapeCellView.h
//  Mousecape
//
//  Created by Alex Zielenski on 2/2/14.
//  Copyright (c) 2014 Alex Zielenski. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "MMAnimatingImageView.h"

extern NSUserInterfaceItemIdentifier const MCCapeCellIdentifier;

// One cape in the library: its name and author, badges for whether it is applied and whether it
// has Retina images, and a strip previewing its cursors
@interface MCCapeCellView : NSTableCellView
@property (nonatomic, assign, getter=isApplied) BOOL applied;
+ (CGFloat)rowHeight;
@end
