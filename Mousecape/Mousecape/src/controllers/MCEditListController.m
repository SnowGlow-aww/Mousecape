//
//  MCEditListController.m
//  Mousecape
//
//  Created by Alex Zielenski on 2/2/14.
//  Copyright (c) 2014 Alex Zielenski. All rights reserved.
//

#import "MCEditListController.h"
#import "NSOrderedSet+AZSortedInsert.h"

const char MCEditCursorsContext;
const char MCCursorNameContext;

static NSUserInterfaceItemIdentifier const MCEditCapeCellIdentifier   = @"MCEditCapeCell";
static NSUserInterfaceItemIdentifier const MCEditCursorCellIdentifier = @"MCEditCursorCell";

// The first frame of a cursor, scaled down to fit
@interface MCCursorThumbnailView : NSView
@property (nonatomic, strong) NSImage *image;
@property (nonatomic, assign) NSUInteger frameCount;
@end

@interface MCEditListController ()
@property (nonatomic, strong) NSMutableOrderedSet *cursors;
+ (NSComparator)sortComparator;
- (void)startObservingCursor:(MCCursor *)cursor;
- (void)stopObservingCursor:(MCCursor *)cursor;
@end

@implementation MCEditListController

- (void)awakeFromNib {
    [super awakeFromNib];

    // A sidebar list; on macOS 26 and later it sits on Liquid Glass
    self.tableView.style = NSTableViewStyleSourceList;
    self.tableView.backgroundColor = NSColor.clearColor;
    self.tableView.enclosingScrollView.drawsBackground = NO;
}

- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil {
    self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
    if (self) {
        [self addObserver:self forKeyPath:@"cursorLibrary.cursors" options:0 context:NULL];
    }
    return self;
}

- (id)initWithCoder:(NSCoder *)coder {
    if ((self = [super initWithCoder:coder])) {
        [self addObserver:self forKeyPath:@"cursorLibrary.cursors" options:NSKeyValueObservingOptionOld | NSKeyValueObservingOptionNew context:(void*)&MCEditCursorsContext];

    }
    return self;
}

- (void)dealloc {
    [self removeObserver:self forKeyPath:@"cursorLibrary.cursors" context:(void *)&MCEditCursorsContext];
    
    for (MCCursor *cursor in self.cursors) {
        [self stopObservingCursor:cursor];
    }
    
}

- (void)startObservingCursor:(MCCursor *)cursor {
    [cursor addObserver:self forKeyPath:@"name" options:0 context:(void *)&MCCursorNameContext];
}

- (void)stopObservingCursor:(MCCursor *)cursor {
    [cursor removeObserver:self forKeyPath:@"name" context:(void *)&MCCursorNameContext];
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    if (context == &MCEditCursorsContext) {
        NSKeyValueChange kind = [change[NSKeyValueChangeKindKey] integerValue];
        [self.tableView beginUpdates];
        
        if (kind == NSKeyValueChangeSetting) {
            id nextSet = change[NSKeyValueChangeNewKey];
            if ([nextSet isKindOfClass:[NSNull class]]) {
                self.cursors = [NSMutableOrderedSet orderedSet];
            } else {
                self.cursors = [NSMutableOrderedSet orderedSetWithSet:nextSet copyItems:NO];
                [self.cursors sortUsingComparator:self.class.sortComparator];
                for (MCCursor *cursor in self.cursors) {
                    [self startObservingCursor:cursor];
                }
            }
            
            [self.tableView reloadData];
            [self.tableView selectRowIndexes:[NSIndexSet indexSetWithIndex:0] byExtendingSelection:NO];
        } else if (kind == NSKeyValueChangeInsertion) {
            for (MCCursor *lib in change[NSKeyValueChangeNewKey]) {
                NSUInteger index = [self.cursors indexForInsertingObject:lib sortedUsingComparator:self.class.sortComparator];
                NSIndexSet *indices = [NSIndexSet indexSetWithIndex:index];

                [self willChange:NSKeyValueChangeInsertion valuesAtIndexes:indices forKey:@"cursors"];
                [self.cursors insertObject:lib atIndex:index];
                [self startObservingCursor:lib];
                [self didChange:NSKeyValueChangeInsertion valuesAtIndexes:indices forKey:@"cursors"];
                [self.tableView insertRowsAtIndexes:[NSIndexSet indexSetWithIndex:index + 1] withAnimation:NSTableViewAnimationSlideUp];
            }
        } else if (kind == NSKeyValueChangeRemoval) {
            for (MCCursor *lib in change[NSKeyValueChangeOldKey]) {
                NSUInteger index = [self.cursors indexOfObject:lib];
                
                if (index != NSNotFound) {
                    NSIndexSet *indices = [NSIndexSet indexSetWithIndex:index];
                    [self willChange:NSKeyValueChangeRemoval valuesAtIndexes:indices forKey:@"cursors"];
                    [self stopObservingCursor:lib];
                    [self.cursors removeObjectAtIndex:index];
                    [self didChange:NSKeyValueChangeRemoval valuesAtIndexes:indices forKey:@"cursors"];
                    [self.tableView removeRowsAtIndexes:[NSIndexSet indexSetWithIndex:index + 1] withAnimation:NSTableViewAnimationSlideUp | NSTableViewAnimationEffectFade];
                }
            }
        }
        [self.tableView endUpdates];
    } else if (context == &MCCursorNameContext) {
        // Reorder it
        MCCursorLibrary *cape = object;
        NSUInteger oldIndex = [self.cursors indexOfObject:cape];
        if (oldIndex != NSNotFound) {
            [self.cursors removeObjectAtIndex:oldIndex];
            NSUInteger newIndex = [self.cursors indexForInsertingObject:cape sortedUsingComparator:self.class.sortComparator];
            
            [self.cursors insertObject:cape atIndex:newIndex];
            [self.tableView moveRowAtIndex:oldIndex + 1 toIndex:newIndex + 1];
        }
    }
}

+ (NSComparator)sortComparator {
    static NSComparator sortComparator = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sortComparator = ^NSComparisonResult(id obj1, id obj2) {
            return [[obj1 valueForKey:@"name"] localizedCaseInsensitiveCompare:[obj2 valueForKey:@"name"]];
        };
    });
    
    return sortComparator;
}

- (IBAction)addAction:(id)sender {
    [self.cursorLibrary addCursor:[[MCCursor alloc] init]];
}

- (IBAction)removeAction:(NSMenuItem *)sender {
    NSInteger row = NSNotFound;
    if (sender.tag == -1)
        row = self.tableView.clickedRow;
    else
        row = self.tableView.selectedRow;
    
    if (row > 0)
        [self.cursorLibrary removeCursor:[[self.tableView viewAtColumn:0 row:row makeIfNecessary:NO] objectValue]];
}

- (IBAction)duplicateAction:(NSMenuItem *)sender {
    NSUInteger row = NSNotFound;
    if (sender.tag == -1)
        row = self.tableView.clickedRow;
    else
        row = self.tableView.selectedRow;
    
    if (row > 0) {
        MCCursor *cursor = [[[self.tableView viewAtColumn:0 row:row makeIfNecessary:NO] objectValue] copy];
        cursor.identifier = UUID();
        [self.cursorLibrary addCursor:cursor];
    }
}

#pragma mark - NSTableViewDelegate

- (void)tableViewSelectionDidChange:(NSNotification *)notification {
    NSInteger selectedRow = [(NSTableView *)self.view selectedRow];
    if (selectedRow == NSNotFound || selectedRow >= self.cursors.count + 1)
        return;
    
    if (selectedRow == 0)
        self.selectedObject = self.cursorLibrary;
    else
        self.selectedObject = [self.cursors objectAtIndex:selectedRow - 1];
}

- (CGFloat)tableView:(NSTableView *)tableView heightOfRow:(NSInteger)row {
    return 28.0;
}

// The first row edits the cape itself; the others are its cursors, each with a thumbnail
- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
    NSUserInterfaceItemIdentifier identifier = row == 0 ? MCEditCapeCellIdentifier : MCEditCursorCellIdentifier;
    NSTableCellView *cell = [tableView makeViewWithIdentifier:identifier owner:self];
    if (cell)
        return cell;

    cell = [[NSTableCellView alloc] init];
    cell.identifier = identifier;

    NSTextField *textField = [NSTextField labelWithString:@""];
    textField.lineBreakMode = NSLineBreakByTruncatingTail;
    [textField setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
    [textField bind:NSValueBinding toObject:cell withKeyPath:@"objectValue.name" options:nil];
    cell.textField = textField;

    NSView *icon;
    if (row == 0) {
        NSImageView *imageView = [NSImageView imageViewWithImage:[NSImage imageWithSystemSymbolName:@"info.circle" accessibilityDescription:nil]];
        imageView.symbolConfiguration = [NSImageSymbolConfiguration configurationWithPointSize:14 weight:NSFontWeightRegular];
        cell.imageView = imageView;
        textField.font = [NSFont systemFontOfSize:NSFont.systemFontSize weight:NSFontWeightSemibold];
        icon = imageView;
    } else {
        MCCursorThumbnailView *thumbnail = [[MCCursorThumbnailView alloc] init];
        [thumbnail bind:@"image" toObject:cell withKeyPath:@"objectValue.imageWithAllReps" options:nil];
        [thumbnail bind:@"frameCount" toObject:cell withKeyPath:@"objectValue.frameCount" options:nil];
        icon = thumbnail;
    }

    for (NSView *view in @[ icon, textField ]) {
        view.translatesAutoresizingMaskIntoConstraints = NO;
        [cell addSubview:view];
    }
    [NSLayoutConstraint activateConstraints:@[
        [icon.leadingAnchor constraintEqualToAnchor:cell.leadingAnchor constant:2],
        [icon.centerYAnchor constraintEqualToAnchor:cell.centerYAnchor],
        [icon.widthAnchor constraintEqualToConstant:20],
        [icon.heightAnchor constraintEqualToConstant:20],
        [textField.leadingAnchor constraintEqualToAnchor:icon.trailingAnchor constant:6],
        [textField.trailingAnchor constraintLessThanOrEqualToAnchor:cell.trailingAnchor constant:-2],
        [textField.centerYAnchor constraintEqualToAnchor:cell.centerYAnchor],
    ]];
    return cell;
}

#pragma mark - NSTableViewDataSource

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
    return self.cursors.count + 1;
}

- (id)tableView:(NSTableView *)tableView objectValueForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
    if (row == 0)
        return self.cursorLibrary;
    return [self.cursors objectAtIndex: row - 1];
}

@end

@implementation MCCursorThumbnailView

- (void)setImage:(NSImage *)image {
    _image = image;
    self.needsDisplay = YES;
}

- (void)setFrameCount:(NSUInteger)frameCount {
    _frameCount = frameCount;
    self.needsDisplay = YES;
}

// Bindings pass nil for a cursor without images
- (void)setNilValueForKey:(NSString *)key {
    if ([key isEqualToString:@"frameCount"])
        self.frameCount = 1;
    else
        [super setNilValueForKey:key];
}

- (void)drawRect:(NSRect)dirtyRect {
    NSImage *image = self.image;
    NSSize frame = NSMakeSize(image.size.width, image.size.height / MAX(self.frameCount, 1));
    if (frame.width <= 0 || frame.height <= 0)
        return;

    CGFloat scale = MIN(1.0, MIN(NSWidth(self.bounds) / frame.width, NSHeight(self.bounds) / frame.height));
    NSSize drawn = NSMakeSize(frame.width * scale, frame.height * scale);
    NSRect destination = NSMakeRect(NSMidX(self.bounds) - drawn.width / 2, NSMidY(self.bounds) - drawn.height / 2, drawn.width, drawn.height);

    // Frames are stacked from the top
    [image drawInRect:[self backingAlignedRect:destination options:NSAlignAllEdgesNearest]
             fromRect:NSMakeRect(0, image.size.height - frame.height, frame.width, frame.height)
            operation:NSCompositingOperationSourceOver
             fraction:1.0
       respectFlipped:YES
                hints:nil];
}

@end
