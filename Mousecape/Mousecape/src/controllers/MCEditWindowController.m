//
//  MCEditWindowController.m
//  Mousecape
//
//  Created by Alex Zielenski on 2/2/14.
//  Copyright (c) 2014 Alex Zielenski. All rights reserved.
//

#import "MCEditWindowController.h"
#import "MCLibraryController.h"

static NSToolbarItemIdentifier const MCEditToolbarSaveIdentifier  = @"MCEditToolbarSave";
static NSToolbarItemIdentifier const MCEditToolbarApplyIdentifier = @"MCEditToolbarApply";

@interface MCEditWindowController ()
- (void)_setCurrentViewController:(NSViewController *)vc;
- (BOOL)promptSaveForLibrary:(MCCursorLibrary *)nextLibrary;
- (void)setUpWindow;
@end

@implementation MCEditWindowController
@dynamic cursorLibrary;

- (id)initWithWindow:(NSWindow *)window {
    if ((self = [super initWithWindow:window])) {
        // Initialization code here.
    }
    return self;
}

- (void)loadWindow {
    [super loadWindow];
    [self windowDidLoad];
}

+ (NSSet *)keyPathsForValuesAffectingCursorLibrary {
    return [NSSet setWithObject:@"editListController.cursorLibrary"];
}

- (MCCursorLibrary *)cursorLibrary {
    return self.editListController.cursorLibrary;
}

- (void)setCursorLibrary:(MCCursorLibrary *)cursorLibrary {
    [self promptSaveForLibrary:cursorLibrary];
}

- (BOOL)promptSaveForLibrary:(MCCursorLibrary *)nextLibrary {
    if (!self.window.isDocumentEdited) {
        self.editListController.cursorLibrary = nextLibrary;
        return NO;
    }
    
    NSBeginAlertSheet(
                      NSLocalizedString(@"Do you want to save your changes?", "Save Prompt Title"),
                      NSLocalizedString(@"Save", "Save Prompt Button"),
                      NSLocalizedString(@"Cancel", "Save Prompt Button"),
                      NSLocalizedString(@"Discard Changes", "Save Prompt Button"),
                      self.window,
                      self,
                      NULL,
                      @selector(sheetDidDismiss:returnCode:contextInfo:),
                      (__bridge void *)nextLibrary,
                      NSLocalizedString(@"Your changes will be discarded if you don't save them.", "Save prompt threat"));
    return YES;
}

- (void)windowDidLoad {
    [super windowDidLoad];    
    [self setUpWindow];
    [self.editListController addObserver:self forKeyPath:@"selectedObject" options:0 context:nil];
    [self _setCurrentViewController:self.editCapeController];
    
    [self.window bind:@"documentEdited" toObject:self withKeyPath:@"cursorLibrary.dirty" options:nil];
}

- (void)dealloc {
    [self.editListController removeObserver:self forKeyPath:@"selectedObject"];
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    if ([keyPath isEqualToString:@"selectedObject"]) {
        [self _changeEditViewsForSelection];
        [self.window.toolbar validateVisibleItems];
    }
}

- (BOOL)windowShouldClose:(NSWindow *)window {
    return ![self promptSaveForLibrary:nil];
}

- (NSUndoManager *)windowWillReturnUndoManager:(NSWindow *)window {
    return self.cursorLibrary.undoManager;
}

- (void)sheetDidDismiss:(NSWindow *)sheet returnCode:(NSInteger)returnCode contextInfo:(MCCursorLibrary *)contextInfo {
    if (returnCode == 0) { // cancel
       // do nothing
    } else if (returnCode == 1) { // save
        NSError *error = [self.cursorLibrary save];
        if (!error) {
            self.editListController.cursorLibrary = contextInfo;
        
            if (!contextInfo)
                [self.window close];
        } else {
            [NSApp presentError:error modalForWindow:self.window delegate:nil didPresentSelector:NULL contextInfo:nil];
        }
    } else if (returnCode == -1) { // discard changes
        [self.cursorLibrary revertToSaved];
        self.editListController.cursorLibrary = contextInfo;
        
        if (!contextInfo)
            [self.window close];
    }
}

#pragma mark - Menu Actions

- (IBAction)applyCape:(id)sender {
    [self.cursorLibrary.library applyCape:self.cursorLibrary];
}

- (IBAction)duplicateCape:(id)sender {
    [self.cursorLibrary.library importCape:self.cursorLibrary.copy];
}

- (IBAction)checkCape:(id)sender {
    
}

- (IBAction)saveDocument:(id)sender {
    NSError *error = [self.cursorLibrary save];
    if (error)
        [self presentError:error modalForWindow:self.window delegate:nil didPresentSelector:NULL contextInfo:NULL];
}

- (IBAction)revertDocumentToSaved:(id)sender {
    [self.cursorLibrary revertToSaved];
}

- (IBAction)showCape:(id)sender {
    [[NSWorkspace sharedWorkspace] activateFileViewerSelectingURLs:@[ self.cursorLibrary.fileURL ]];
}

- (NSError *)willPresentError:(NSError *)error {
    return [NSError errorWithDomain:error.domain code:error.code userInfo:@{
                                                                            NSLocalizedDescriptionKey: error.localizedDescription ?: @"",
                                                                            NSLocalizedRecoverySuggestionErrorKey: error.localizedFailureReason ?: @""
                                                                            }];
}

#pragma mark - View Changing

- (void)_changeEditViewsForSelection {
    BOOL capeEditor = [self.editListController.selectedObject isKindOfClass:[MCCursorLibrary class]];
    if (capeEditor) {
        [self _setCurrentViewController:self.editCapeController];
        self.editCapeController.cursorLibrary = self.editListController.selectedObject;
    } else {
        [self _setCurrentViewController:self.editDetailController];
        self.editDetailController.cursor = self.editListController.selectedObject;
    }
}

- (void)_setCurrentViewController:(NSViewController *)vc {
    if ([self.detailView.subviews containsObject:vc.view])
        return;
    
    [self.detailView setSubviews:@[]];
    [self.detailView removeConstraints:self.detailView.constraints];
    
    NSRect frame  = self.detailView.bounds;
    vc.view.frame = frame;
    
    // Fill superview with subview
    [vc.view setTranslatesAutoresizingMaskIntoConstraints:YES];
    [vc.view setAutoresizingMask:NSViewHeightSizable | NSViewWidthSizable | NSViewMinYMargin | NSViewMinXMargin];
    
    [self.detailView addSubview:vc.view];
}

#pragma mark - Window

// The nib's split view becomes a split view controller, which gives the cursor list a real sidebar
// (Liquid Glass on macOS 26 and later) and lets both panes run under a unified toolbar
- (void)setUpWindow {
    NSWindow *window = self.window;
    NSSplitView *oldSplitView = (NSSplitView *)self.detailView.superview;
    if (![oldSplitView isKindOfClass:[NSSplitView class]])
        return;

    NSRect frame = window.frame;
    NSView *listPane = oldSplitView.subviews.firstObject;
    [listPane removeFromSuperview];
    [self.detailView removeFromSuperview];
    [oldSplitView removeFromSuperview];
    [self setUpListPane:listPane];

    NSViewController *sidebarController = [[NSViewController alloc] init];
    sidebarController.view = listPane;

    // Keep the editors below the toolbar
    NSView *contentView = [[NSView alloc] init];
    self.detailView.translatesAutoresizingMaskIntoConstraints = NO;
    [contentView addSubview:self.detailView];
    NSLayoutGuide *safeArea = contentView.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [self.detailView.topAnchor constraintEqualToAnchor:safeArea.topAnchor],
        [self.detailView.bottomAnchor constraintEqualToAnchor:safeArea.bottomAnchor],
        [self.detailView.leadingAnchor constraintEqualToAnchor:safeArea.leadingAnchor],
        [self.detailView.trailingAnchor constraintEqualToAnchor:safeArea.trailingAnchor],
    ]];
    NSViewController *contentController = [[NSViewController alloc] init];
    contentController.view = contentView;

    NSSplitViewItem *sidebarItem = [NSSplitViewItem sidebarWithViewController:sidebarController];
    sidebarItem.minimumThickness = 180;
    sidebarItem.maximumThickness = 300;
    sidebarItem.canCollapse = NO;
    NSSplitViewItem *contentItem = [NSSplitViewItem splitViewItemWithViewController:contentController];
    contentItem.minimumThickness = 380;

    NSSplitViewController *splitViewController = [[NSSplitViewController alloc] init];
    [splitViewController addSplitViewItem:sidebarItem];
    [splitViewController addSplitViewItem:contentItem];

    window.styleMask |= NSWindowStyleMaskFullSizeContentView;
    window.toolbarStyle = NSWindowToolbarStyleUnified;
    window.contentViewController = splitViewController;

    NSToolbar *toolbar = [[NSToolbar alloc] initWithIdentifier:@"MCEditToolbar"];
    toolbar.delegate = self;
    toolbar.displayMode = NSToolbarDisplayModeIconOnly;
    toolbar.allowsUserCustomization = NO;
    window.toolbar = toolbar;

    window.contentMinSize = NSMakeSize(580, 340);
    frame.size.width = MAX(NSWidth(frame), 640);
    frame.size.height = MAX(NSHeight(frame), 400);
    [window setFrame:frame display:NO];
}

// Borderless add and remove buttons, clear of the sidebar's rounded corners
- (void)setUpListPane:(NSView *)listPane {
    NSScrollView *scrollView = nil;
    NSMutableArray *buttons = [NSMutableArray array];
    for (NSView *view in listPane.subviews.copy) {
        if ([view isKindOfClass:[NSScrollView class]])
            scrollView = (NSScrollView *)view;
        else if ([view isKindOfClass:[NSButton class]])
            [buttons addObject:view];
        else if ([view isKindOfClass:[NSBox class]])
            [view removeFromSuperview];
    }
    if (!scrollView)
        return;

    NSMutableArray *oldConstraints = [NSMutableArray array];
    for (NSLayoutConstraint *constraint in listPane.constraints) {
        BOOL aboutButtons = [buttons containsObject:constraint.firstItem] || [buttons containsObject:constraint.secondItem];
        BOOL scrollViewBottom = (constraint.firstItem == scrollView && constraint.firstAttribute == NSLayoutAttributeBottom) ||
                                (constraint.secondItem == scrollView && constraint.secondAttribute == NSLayoutAttributeBottom);
        if (aboutButtons || scrollViewBottom)
            [oldConstraints addObject:constraint];
    }
    [NSLayoutConstraint deactivateConstraints:oldConstraints];

    [buttons sortUsingComparator:^NSComparisonResult(NSButton *a, NSButton *b) {
        return a.action == @selector(addAction:) ? NSOrderedAscending : NSOrderedDescending;
    }];
    for (NSButton *button in buttons) {
        [NSLayoutConstraint deactivateConstraints:button.constraints];
        NSString *symbol = button.action == @selector(addAction:) ? @"plus" : @"minus";
        button.image = [NSImage imageWithSystemSymbolName:symbol accessibilityDescription:button.action == @selector(addAction:) ?
                        NSLocalizedString(@"Add Cursor", @"Editor sidebar button") : NSLocalizedString(@"Remove Cursor", @"Editor sidebar button")];
        button.bordered = NO;
        button.imagePosition = NSImageOnly;
        button.contentTintColor = NSColor.secondaryLabelColor;
        [button.widthAnchor constraintEqualToConstant:24].active = YES;
        [button.heightAnchor constraintEqualToConstant:22].active = YES;
    }

    NSStackView *buttonBar = [NSStackView stackViewWithViews:buttons];
    buttonBar.spacing = 2;
    buttonBar.translatesAutoresizingMaskIntoConstraints = NO;
    [listPane addSubview:buttonBar];
    [NSLayoutConstraint activateConstraints:@[
        [buttonBar.leadingAnchor constraintEqualToAnchor:listPane.leadingAnchor constant:12],
        [buttonBar.bottomAnchor constraintEqualToAnchor:listPane.safeAreaLayoutGuide.bottomAnchor constant:-10],
        [scrollView.bottomAnchor constraintEqualToAnchor:buttonBar.topAnchor constant:-6],
    ]];
}

#pragma mark - NSToolbarDelegate

- (NSArray<NSToolbarItemIdentifier> *)toolbarDefaultItemIdentifiers:(NSToolbar *)toolbar {
    return @[ NSToolbarSidebarTrackingSeparatorItemIdentifier, NSToolbarFlexibleSpaceItemIdentifier,
              MCEditToolbarSaveIdentifier, MCEditToolbarApplyIdentifier ];
}

- (NSArray<NSToolbarItemIdentifier> *)toolbarAllowedItemIdentifiers:(NSToolbar *)toolbar {
    return [self toolbarDefaultItemIdentifiers:toolbar];
}

- (NSToolbarItem *)toolbar:(NSToolbar *)toolbar itemForItemIdentifier:(NSToolbarItemIdentifier)identifier willBeInsertedIntoToolbar:(BOOL)flag {
    NSString *label, *symbol;
    SEL action;
    if ([identifier isEqualToString:MCEditToolbarSaveIdentifier]) {
        label = NSLocalizedString(@"Save", @"Editor toolbar item");
        symbol = @"square.and.arrow.down";
        action = @selector(saveDocument:);
    } else if ([identifier isEqualToString:MCEditToolbarApplyIdentifier]) {
        label = NSLocalizedString(@"Apply", @"Editor toolbar item");
        symbol = @"checkmark.circle";
        action = @selector(applyCape:);
    } else {
        return nil;
    }

    NSToolbarItem *item = [[NSToolbarItem alloc] initWithItemIdentifier:identifier];
    item.label = label;
    item.paletteLabel = label;
    item.toolTip = label;
    item.image = [NSImage imageWithSystemSymbolName:symbol accessibilityDescription:label];
    item.action = action;
    item.target = self;
    item.bordered = YES;
    return item;
}

- (BOOL)validateUserInterfaceItem:(id <NSValidatedUserInterfaceItem>)item {
    if (item.action == @selector(saveDocument:) || item.action == @selector(revertDocumentToSaved:))
        return self.window.isDocumentEdited;
    if (item.action == @selector(applyCape:))
        return self.cursorLibrary != nil;
    return YES;
}

- (BOOL)validateToolbarItem:(NSToolbarItem *)item {
    return [self validateUserInterfaceItem:item];
}

- (BOOL)validateMenuItem:(NSMenuItem *)menuItem {
    return [self validateUserInterfaceItem:menuItem];
}

@end
