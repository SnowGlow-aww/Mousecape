//
//  MCLibraryViewController.h
//  Mousecape
//
//  Created by Alex Zielenski on 2/2/14.
//  Copyright (c) 2014 Alex Zielenski. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "MCLibraryController.h"

@interface MCLibraryViewController : NSViewController <NSTableViewDelegate, NSTableViewDataSource>
@property (assign) IBOutlet NSMenu *contextMenu;
@property (assign) IBOutlet NSTableView *tableView;
@property (strong, readonly) MCLibraryController *libraryController;
@property (weak) MCCursorLibrary *editingCape;
@property (weak) MCCursorLibrary *selectedCape;
@property (weak) MCCursorLibrary *clickedCape;
// The first row stands for the cursors macOS has when no cape is applied
@property (readonly) BOOL selectedDefault;
@property (readonly) BOOL clickedDefault;

- (void)editCape:(MCCursorLibrary *)library;
// Imports capes and Windows cursor themes, then selects the last one added
- (void)importURLs:(NSArray<NSURL *> *)urls;
@end

@interface MCLibraryController (Properties)
@property (readonly, strong) NSOrderedSet *capes;
@end
