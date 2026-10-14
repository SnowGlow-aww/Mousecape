//
//  MCLbraryWindowController.m
//  Mousecape
//
//  Created by Alex Zielenski on 2/2/14.
//  Copyright (c) 2014 Alex Zielenski. All rights reserved.
//

#import "MCLibraryWindowController.h"

static NSToolbarItemIdentifier const MCToolbarNewIdentifier    = @"MCToolbarNew";
static NSToolbarItemIdentifier const MCToolbarImportIdentifier = @"MCToolbarImport";
static NSToolbarItemIdentifier const MCToolbarEditIdentifier   = @"MCToolbarEdit";
static NSToolbarItemIdentifier const MCToolbarApplyIdentifier  = @"MCToolbarApply";
static NSToolbarItemIdentifier const MCToolbarResetIdentifier  = @"MCToolbarReset";

@interface MCLibraryWindowController () <NSToolbarDelegate>
- (void)setUpWindow;
@end

@implementation MCLibraryWindowController

// The app delegate loads the window itself, which skips windowDidLoad
- (void)awakeFromNib {
    [self setUpWindow];
}

- (id)initWithWindow:(NSWindow *)window {
    if ((self = [super initWithWindow:window])) {
        
    }
    return self;
}

- (void)windowDidLoad {
    [super windowDidLoad];
    [self setUpWindow];
}

- (NSString *)windowNibName {
    return @"Library";
}

- (void)setUpWindow {
    NSWindow *window = self.window;
    if (window.toolbar)
        return;

    // Let the list run under the toolbar; on macOS 26 and later the toolbar's controls are
    // Liquid Glass and the list blurs out beneath them as it scrolls
    window.styleMask |= NSWindowStyleMaskFullSizeContentView;
    window.toolbarStyle = NSWindowToolbarStyleUnified;

    NSToolbar *toolbar = [[NSToolbar alloc] initWithIdentifier:@"MCLibraryToolbar"];
    toolbar.delegate = self;
    toolbar.displayMode = NSToolbarDisplayModeIconOnly;
    toolbar.allowsUserCustomization = NO;
    window.toolbar = toolbar;

    [window bind:@"subtitle" toObject:self withKeyPath:@"libraryViewController.libraryController.appliedCape.name" options:@{
        NSValueTransformerNameBindingOption: @"MCAppliedCapeValueTransformer"
    }];
}

#pragma mark - NSToolbarDelegate

- (NSArray<NSToolbarItemIdentifier> *)toolbarDefaultItemIdentifiers:(NSToolbar *)toolbar {
    return @[ NSToolbarFlexibleSpaceItemIdentifier,
              MCToolbarNewIdentifier, MCToolbarImportIdentifier,
              NSToolbarSpaceItemIdentifier,
              MCToolbarEditIdentifier, MCToolbarApplyIdentifier, MCToolbarResetIdentifier ];
}

- (NSArray<NSToolbarItemIdentifier> *)toolbarAllowedItemIdentifiers:(NSToolbar *)toolbar {
    return [self toolbarDefaultItemIdentifiers:toolbar];
}

- (NSToolbarItem *)toolbar:(NSToolbar *)toolbar itemForItemIdentifier:(NSToolbarItemIdentifier)identifier willBeInsertedIntoToolbar:(BOOL)flag {
    NSDictionary *items = @{
        MCToolbarNewIdentifier:    @[ NSLocalizedString(@"New Cape", @"Toolbar item"), @"plus", NSStringFromSelector(@selector(newDocument:)) ],
        MCToolbarImportIdentifier: @[ NSLocalizedString(@"Import", @"Toolbar item"), @"square.and.arrow.down", NSStringFromSelector(@selector(openDocument:)) ],
        MCToolbarEditIdentifier:   @[ NSLocalizedString(@"Edit", @"Toolbar item"), @"pencil", NSStringFromSelector(@selector(editCapeAction:)) ],
        MCToolbarApplyIdentifier:  @[ NSLocalizedString(@"Apply", @"Toolbar item"), @"checkmark.circle", NSStringFromSelector(@selector(applyCapeAction:)) ],
        MCToolbarResetIdentifier:  @[ NSLocalizedString(@"Reset to Default", @"Toolbar item"), @"arrow.counterclockwise", NSStringFromSelector(@selector(restoreCape:)) ],
    };
    NSArray *info = items[identifier];
    if (!info)
        return nil;

    NSToolbarItem *item = [[NSToolbarItem alloc] initWithItemIdentifier:identifier];
    item.label = info[0];
    item.paletteLabel = info[0];
    item.toolTip = info[0];
    item.image = [NSImage imageWithSystemSymbolName:info[1] accessibilityDescription:info[0]];
    item.action = NSSelectorFromString(info[2]);
    item.bordered = YES;
    // Cape actions belong to this window; the rest go to the app delegate
    if ([self respondsToSelector:item.action])
        item.target = self;
    return item;
}

// Actions on a cape need one to act on
- (BOOL)validateUserInterfaceItem:(id <NSValidatedUserInterfaceItem>)item {
    SEL action = item.action;
    if (action == @selector(applyCapeAction:) || action == @selector(editCapeAction:) ||
        action == @selector(removeCapeAction:) || action == @selector(duplicateCapeAction:) ||
        action == @selector(showCapeAction:)) {
        return (item.tag == -1 ? self.libraryViewController.clickedCape : self.libraryViewController.selectedCape) != nil;
    }
    return YES;
}

- (BOOL)validateMenuItem:(NSMenuItem *)menuItem {
    return [self validateUserInterfaceItem:menuItem];
}

- (BOOL)validateToolbarItem:(NSToolbarItem *)item {
    return [self validateUserInterfaceItem:item];
}

- (NSUndoManager *)windowWillReturnUndoManager:(NSWindow *)window {
    return self.libraryViewController.libraryController.undoManager;
}

#pragma mark - Menu Actions

- (IBAction)applyCapeAction:(NSMenuItem *)sender {
    MCCursorLibrary *cape = nil;
    if (sender.tag == -1)
        cape = self.libraryViewController.clickedCape;
    else
        cape = self.libraryViewController.selectedCape;
    
    [self.libraryViewController.libraryController applyCape:cape];
}

- (IBAction)editCapeAction:(NSMenuItem *)sender {
    MCCursorLibrary *cape = nil;
    if (sender.tag == -1)
        cape = self.libraryViewController.clickedCape;
    else
        cape = self.libraryViewController.selectedCape;
    
    [self.libraryViewController editCape:cape];
}

- (IBAction)removeCapeAction:(NSMenuItem *)sender {
    MCCursorLibrary *cape = nil;
    if (sender.tag == -1)
        cape = self.libraryViewController.clickedCape;
    else
        cape = self.libraryViewController.selectedCape;
    
    if (cape != self.libraryViewController.editingCape) {
        [self.libraryViewController.libraryController removeCape:cape];
    } else {
        [[NSSound soundNamed:@"Funk"] play];
        [self.libraryViewController editCape:self.libraryViewController.editingCape];
    }
}

- (IBAction)duplicateCapeAction:(NSMenuItem *)sender {
    MCCursorLibrary *cape = nil;
    if (sender.tag == -1)
        cape = self.libraryViewController.clickedCape;
    else
        cape = self.libraryViewController.selectedCape;
    
    [self.libraryViewController.libraryController importCape:cape.copy];
}

- (IBAction)checkCapeAction:(NSMenuItem *)sender {
    
}

- (IBAction)showCapeAction:(NSMenuItem *)sender {
    MCCursorLibrary *cape = nil;
    if (sender.tag == -1)
        cape = self.libraryViewController.clickedCape;
    else
        cape = self.libraryViewController.selectedCape;
    
    [[NSWorkspace sharedWorkspace] activateFileViewerSelectingURLs:@[ cape.fileURL ]];
}

- (IBAction)dumpCapeAction:(NSMenuItem *)sender {
    [self.window beginSheet:self.progressBar.window completionHandler:nil];
    __weak MCLibraryWindowController *weakSelf = self;
    self.progressBar.doubleValue = 0.0;
    [self.progressBar setIndeterminate:NO];
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{
        [weakSelf.libraryViewController.libraryController dumpCursorsWithProgressBlock:^BOOL (NSUInteger current, NSUInteger total) {
            dispatch_sync(dispatch_get_main_queue(), ^{
                weakSelf.progressField.stringValue = [NSString stringWithFormat:@"%lu %@ %lu", (unsigned long)current, NSLocalizedString(@"of", @"Dump cursor progress separator (eg: 5 of 129)"), (unsigned long)total];
                weakSelf.progressBar.minValue = 0;
                weakSelf.progressBar.maxValue = total;
                weakSelf.progressBar.doubleValue = current;
            });
            return YES;
        }];

        dispatch_sync(dispatch_get_main_queue(), ^{
            [weakSelf.window endSheet:self.progressBar.window];
            [[NSCursor arrowCursor] set];
        });
    });

}

@end

@implementation MCAppliedCapeValueTransformer

+ (Class)transformedValueClass {
    return [NSString class];
}

- (id)transformedValue:(id)value {
    if (!value)
        return NSLocalizedString(@"No Cape Applied", @"Window subtitle when no cape is applied");
    return [NSString stringWithFormat:NSLocalizedString(@"Applied: %@", @"Window subtitle naming the applied cape"), value];
}

@end
