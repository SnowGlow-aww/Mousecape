//
//  MCLibraryViewController.m
//  Mousecape
//
//  Created by Alex Zielenski on 2/2/14.
//  Copyright (c) 2014 Alex Zielenski. All rights reserved.
//

#import "MCLibraryViewController.h"
#import "MCCapeCellView.h"
#import "NSFileManager+DirectoryLocations.h"
#import "MCEditWindowController.h"
#import "NSOrderedSet+AZSortedInsert.h"

const char MCLibraryCapesContext;
const char MCLibraryNameContext;

// One of the cursors macOS draws, in the shape the row's previews read
@interface MCSystemCursorPreview : NSObject
@property (copy) NSString *name;
@property (strong) NSImage *imageWithAllReps;
@property (assign) NSUInteger frameCount;
@property (assign) CGFloat frameDuration;
@end

@implementation MCSystemCursorPreview
@end

// The first row of the library: what you get back by resetting
@interface MCSystemDefaultCape : NSObject
@property (readonly) NSString *name;
@property (readonly) NSString *author;
@property (readonly) BOOL hiDPI;
@property (readonly) NSSet *cursors;
@end

@implementation MCSystemDefaultCape

- (instancetype)init {
    if ((self = [super init])) {
        _name = NSLocalizedString(@"macOS Default", @"Library row for the system cursors");
        _author = @"Apple";
        _hiDPI = YES;

        NSDictionary *cursors = @{
            @"Arrow": NSCursor.arrowCursor, @"Copy": NSCursor.dragCopyCursor, @"Link": NSCursor.dragLinkCursor,
            @"Forbidden": NSCursor.operationNotAllowedCursor, @"Contextual Menu": NSCursor.contextualMenuCursor,
            @"IBeam": NSCursor.IBeamCursor, @"Pointing Hand": NSCursor.pointingHandCursor,
            @"Open Hand": NSCursor.openHandCursor, @"Closed Hand": NSCursor.closedHandCursor,
            @"Crosshair": NSCursor.crosshairCursor,
        };
        NSMutableSet *previews = [NSMutableSet set];
        [cursors enumerateKeysAndObjectsUsingBlock:^(NSString *name, NSCursor *cursor, BOOL *stop) {
            MCSystemCursorPreview *preview = [[MCSystemCursorPreview alloc] init];
            preview.name = name;
            // Drawn on demand at its point size; some system cursor images report a scale the
            // preview's layer takes for 1x and show at double size
            NSImage *source = cursor.image;
            preview.imageWithAllReps = [NSImage imageWithSize:source.size flipped:NO drawingHandler:^BOOL(NSRect rect) {
                [source drawInRect:rect];
                return YES;
            }];
            preview.frameCount = 1;
            preview.frameDuration = 1;
            [previews addObject:preview];
        }];
        _cursors = previews;
    }
    return self;
}

@end

@interface MCLibraryViewController ()
@property (strong) MCEditWindowController *editWindowController;
@property (strong) MCSystemDefaultCape *systemDefault;
@property (readwrite, strong) NSMutableOrderedSet *capes;
@property (strong, readwrite) MCLibraryController *libraryController;
- (void)setupEnvironment;
- (void)doubleClick:(id)sender;
+ (NSString *)capesPath;
+ (NSComparator)sortComparator;
@end

@implementation MCLibraryViewController
@dynamic clickedCape, selectedCape, editingCape;

+ (NSComparator)sortComparator {
    static NSComparator sortComparator = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sortComparator = ^NSComparisonResult(id obj1, id obj2) {
            // The default row stays first
            if ([obj1 isKindOfClass:[MCSystemDefaultCape class]] || [obj2 isKindOfClass:[MCSystemDefaultCape class]])
                return obj1 == obj2 ? NSOrderedSame : [obj1 isKindOfClass:[MCSystemDefaultCape class]] ? NSOrderedAscending : NSOrderedDescending;

            NSComparisonResult result = [[obj1 valueForKey:@"name"] localizedCaseInsensitiveCompare:[obj2 valueForKey:@"name"]];
            if (result == NSOrderedSame)
                result = [[obj1 valueForKey:@"author"] localizedCaseInsensitiveCompare:[obj2 valueForKey:@"author"]];
            return result;
        };
    });
    
    return sortComparator;
}

- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil {
    if ((self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil])) {
        [self setupEnvironment];
    }
    return self;
}

- (id)initWithCoder:(NSCoder *)coder {
    if ((self = [super initWithCoder:coder])) {
        [self setupEnvironment];
    }
        
    return self;
}

- (void)dealloc {
    [self.libraryController removeObserver:self forKeyPath:@"appliedCape"];
    
    for (MCCursorLibrary *library in self.capes) {
        if (library != (id)self.systemDefault)
            [library removeObserver:self forKeyPath:@"name" context:(void *)&MCLibraryNameContext];
    }
    
}

+ (NSString *)capesPath {
    return [[NSFileManager defaultManager] findOrCreateDirectory:NSApplicationSupportDirectory inDomain:NSUserDomainMask appendPathComponent:@"Mousecape/capes" error:NULL];
}

- (void)awakeFromNib {
    if (self.tableView.style == NSTableViewStyleInset)
        return;

    self.tableView.doubleAction = @selector(doubleClick:);
    self.tableView.target       = self;

    // Rounded rows over the window background, which scrolls under the toolbar
    self.tableView.style = NSTableViewStyleInset;
    self.tableView.usesAlternatingRowBackgroundColors = NO;
    self.tableView.backgroundColor = NSColor.clearColor;
    self.tableView.enclosingScrollView.drawsBackground = NO;
    self.tableView.headerView = nil;
    self.tableView.intercellSpacing = NSMakeSize(0, 6);
    self.tableView.rowSizeStyle = NSTableViewRowSizeStyleCustom;
    self.tableView.rowHeight = MCCapeCellView.rowHeight;
}

- (void)setupEnvironment {
    [self addObserver:self forKeyPath:@"libraryController.capes" options:NSKeyValueObservingOptionNew | NSKeyValueObservingOptionOld context:(void *)&MCLibraryCapesContext];
    self.libraryController = [[MCLibraryController alloc] initWithURL:[NSURL fileURLWithPath:self.class.capesPath]];

    [self setRepresentedObject:self.libraryController];
    [self.libraryController addObserver:self forKeyPath:NSStringFromSelector(@selector(appliedCape)) options:0 context:NULL];
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    if ([keyPath isEqualToString:NSStringFromSelector(@selector(appliedCape))]) {
        for (NSUInteger x = 0; x < self.tableView.numberOfRows; x++) {
            MCCapeCellView *cv = [self.tableView viewAtColumn:0 row:x makeIfNecessary:NO];
            cv.applied = [self isApplied:cv.objectValue];
        }
        
    } else if (context == &MCLibraryCapesContext) {
        NSKeyValueChange kind = [change[NSKeyValueChangeKindKey] integerValue];
        [self.tableView beginUpdates];

        if (kind ==  NSKeyValueChangeInsertion || kind == NSKeyValueChangeSetting) {
            
            if (kind == NSKeyValueChangeSetting) {
                if (!self.systemDefault)
                    self.systemDefault = [[MCSystemDefaultCape alloc] init];
                self.capes = [NSMutableOrderedSet orderedSetWithObject:self.systemDefault];
            }
                
            for (MCCursorLibrary *lib in change[NSKeyValueChangeNewKey]) {
                NSUInteger index = [self.capes indexForInsertingObject:lib sortedUsingComparator:self.class.sortComparator];
                NSIndexSet *indices = [NSIndexSet indexSetWithIndex:index];
                
                [self willChange:NSKeyValueChangeInsertion valuesAtIndexes:indices forKey:@"capes"];
                [lib addObserver:self forKeyPath:@"name" options:0 context:(void *)&MCLibraryNameContext];
                [self.capes insertObject:lib atIndex:index];
                [self didChange:NSKeyValueChangeInsertion valuesAtIndexes:indices forKey:@"capes"];
                [self.tableView insertRowsAtIndexes:indices withAnimation:NSTableViewAnimationSlideUp];
            }

        } else if (kind ==  NSKeyValueChangeRemoval) {
            for (MCCursorLibrary *lib in change[NSKeyValueChangeOldKey]) {
                NSUInteger index = [self.capes indexOfObject:lib];
                NSIndexSet *indices = [NSIndexSet indexSetWithIndex:index];
                [self willChange:NSKeyValueChangeRemoval valuesAtIndexes:indices forKey:@"capes"];
                [lib removeObserver:self forKeyPath:@"name" context:(void *)&MCLibraryNameContext];
                [self.capes removeObjectAtIndex:index];
                [self didChange:NSKeyValueChangeRemoval valuesAtIndexes:indices forKey:@"capes"];
                
                [self.tableView removeRowsAtIndexes:indices withAnimation:NSTableViewAnimationSlideUp | NSTableViewAnimationEffectFade];

                if (self.editWindowController.cursorLibrary == lib) {
                    self.editWindowController.cursorLibrary = nil;
                    [self.editWindowController close];
                }
            }
        }
        
        [self.tableView endUpdates];

    } else if (context == &MCLibraryNameContext) {
        // Reoder it
        MCCursorLibrary *cape = object;
        NSUInteger oldIndex = [self.capes indexOfObject:cape];
        if (oldIndex != NSNotFound) {
            [self.capes removeObjectAtIndex:oldIndex];
            NSUInteger newIndex = [self.capes indexForInsertingObject:cape sortedUsingComparator:self.class.sortComparator];
            [self.capes insertObject:cape atIndex:newIndex];
            [self.tableView moveRowAtIndex:oldIndex toIndex:newIndex];
        }
    } else
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];

}

- (void)doubleClick:(NSTableView *)sender {
    if (self.clickedDefault) {
        if ([[NSUserDefaults standardUserDefaults] integerForKey:MCPreferencesDoubleActionKey] == 0)
            [self.libraryController restoreCape];
        return;
    }

    MCCursorLibrary *library = [self capeAtRow:sender.clickedRow];
    if (!library)
        return;
    if ([[NSUserDefaults standardUserDefaults] integerForKey:MCPreferencesDoubleActionKey] == 0)
        [self.libraryController applyCape:library];
    else {
        [self editCape:library];
    }
}

#pragma mark - Editing

+ (NSSet *)keyPathsForValuesAffectingEditingCape {
    return [NSSet setWithObject:@"editWindowController.cursorLibrary"];
}

// Straight from the data; asking the table for a row's view throws when no row is clicked.
// The default row has no cape.
- (MCCursorLibrary *)capeAtRow:(NSInteger)row {
    id object = row >= 0 && row < (NSInteger)self.capes.count ? self.capes[row] : nil;
    return [object isKindOfClass:[MCCursorLibrary class]] ? object : nil;
}

- (BOOL)selectedDefault {
    return self.tableView.selectedRow == 0 && self.systemDefault;
}

- (BOOL)clickedDefault {
    return self.tableView.clickedRow == 0 && self.systemDefault;
}

- (BOOL)isApplied:(id)object {
    if (object == self.systemDefault)
        return self.libraryController.appliedCape == nil;
    return object == self.libraryController.appliedCape;
}

- (MCCursorLibrary *)selectedCape {
    return [self capeAtRow:self.tableView.selectedRow];
}

- (MCCursorLibrary *)clickedCape {
    return [self capeAtRow:self.tableView.clickedRow];
}

- (MCCursorLibrary *)editingCape {
    return self.editWindowController.cursorLibrary;
}

- (void)editCape:(MCCursorLibrary *)library {
    if (!library)
        return;
    
    if (!self.editWindowController) {
        self.editWindowController = [[MCEditWindowController alloc] initWithWindowNibName:@"Edit"];
        [self.editWindowController loadWindow];
    }
    self.editWindowController.cursorLibrary = library;
    [self.editWindowController showWindow:self];
}

#pragma mark - NSTableViewDelegate

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
    return self.capes.count;
}

- (id)tableView:(NSTableView *)tableView objectValueForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
    return self.capes[row];
}

#pragma mark - NSTableViewDelegate

- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
    MCCapeCellView *cellView = [tableView makeViewWithIdentifier:MCCapeCellIdentifier owner:self];
    if (!cellView)
        cellView = [[MCCapeCellView alloc] initWithFrame:NSMakeRect(0, 0, NSWidth(tableView.bounds), tableView.rowHeight)];
    cellView.applied = [self isApplied:[self.capes objectAtIndex:row]];
    return cellView;
}

// The toolbar's cape actions depend on the selection
- (void)tableViewSelectionDidChange:(NSNotification *)notification {
    [self.view.window.toolbar validateVisibleItems];
}

- (CGFloat)tableView:(NSTableView *)tableView heightOfRow:(NSInteger)row {
    return MCCapeCellView.rowHeight;
}

//- (NSTableRowView *)tableView:(NSTableView *)tableView rowViewForRow:(NSInteger)row {
//    return nil;
//}

@end
