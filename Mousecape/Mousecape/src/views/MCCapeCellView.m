//
//  MCCapeCellView.m
//  Mousecape
//
//  Created by Alex Zielenski on 2/2/14.
//  Copyright (c) 2014 Alex Zielenski. All rights reserved.
//

#import "MCCapeCellView.h"
#import "MCCapePreviewItem.h"

NSUserInterfaceItemIdentifier const MCCapeCellIdentifier = @"MCCapeCell";

@interface MCSortValueTransformer : NSValueTransformer
@end

// HD or SD, for the badge
@interface MCResolutionValueTransformer : NSValueTransformer
@end

// A small rounded label. Its colors follow the row: tinted normally, white on a selected row.
@interface MCBadgeView : NSView
@property (nonatomic, strong) NSColor *tintColor;
@property (nonatomic, assign) BOOL emphasized;
@property (nonatomic, strong, readonly) NSTextField *label;
@property (nonatomic, strong, readonly) NSImageView *imageView;
- (instancetype)initWithSymbolName:(NSString *)symbolName tintColor:(NSColor *)tintColor;
@end

// The rounded tray the cursor previews sit in
@interface MCPreviewWellView : NSView
@property (nonatomic, assign) BOOL emphasized;
@end

@interface MCCapeCellView ()
@property (nonatomic, strong) NSTextField *authorField;
@property (nonatomic, strong) MCBadgeView *appliedBadge;
@property (nonatomic, strong) MCBadgeView *resolutionBadge;
@property (nonatomic, strong) MCPreviewWellView *previewWell;
@property (nonatomic, strong) NSCollectionView *collectionView;
@end

@implementation MCCapeCellView

- (instancetype)initWithFrame:(NSRect)frameRect {
    if ((self = [super initWithFrame:frameRect])) {
        self.identifier = MCCapeCellIdentifier;

        NSTextField *nameField = [NSTextField labelWithString:@""];
        nameField.font = [NSFont systemFontOfSize:15 weight:NSFontWeightSemibold];
        nameField.textColor = NSColor.labelColor;
        nameField.lineBreakMode = NSLineBreakByTruncatingTail;
        [nameField setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
        [nameField bind:NSValueBinding toObject:self withKeyPath:@"objectValue.name" options:nil];
        self.textField = nameField;

        NSTextField *authorField = [NSTextField labelWithString:@""];
        authorField.font = [NSFont systemFontOfSize:12];
        authorField.textColor = NSColor.secondaryLabelColor;
        authorField.lineBreakMode = NSLineBreakByTruncatingTail;
        [authorField setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow - 1 forOrientation:NSLayoutConstraintOrientationHorizontal];
        [authorField bind:@"displayPatternValue1" toObject:self withKeyPath:@"objectValue.author" options:@{
            NSDisplayPatternBindingOption: NSLocalizedString(@"by %{value1}@", @"Cape author in the library, eg: by Max Rudberg")
        }];
        self.authorField = authorField;

        // A darker green in light mode, where system green is hard to read on a gray selection
        NSColor *green = [NSColor colorWithName:nil dynamicProvider:^NSColor *(NSAppearance *appearance) {
            BOOL dark = [appearance bestMatchFromAppearancesWithNames:@[ NSAppearanceNameAqua, NSAppearanceNameDarkAqua ]] == NSAppearanceNameDarkAqua;
            return dark ? NSColor.systemGreenColor : [NSColor.systemGreenColor blendedColorWithFraction:0.3 ofColor:NSColor.blackColor];
        }];
        self.appliedBadge = [[MCBadgeView alloc] initWithSymbolName:@"checkmark.circle.fill" tintColor:green];
        self.appliedBadge.label.stringValue = NSLocalizedString(@"Applied", @"Badge on the applied cape in the library");
        self.appliedBadge.hidden = YES;

        self.resolutionBadge = [[MCBadgeView alloc] initWithSymbolName:nil tintColor:NSColor.secondaryLabelColor];
        [self.resolutionBadge.label bind:NSValueBinding toObject:self withKeyPath:@"objectValue.hiDPI" options:@{
            NSValueTransformerBindingOption: [MCResolutionValueTransformer new]
        }];

        NSStackView *header = [NSStackView stackViewWithViews:@[ nameField, authorField ]];
        header.alignment = NSLayoutAttributeFirstBaseline;
        header.spacing = 6;
        [header setHuggingPriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];

        NSStackView *badges = [NSStackView stackViewWithViews:@[ self.appliedBadge, self.resolutionBadge ]];
        badges.spacing = 6;
        badges.detachesHiddenViews = YES;

        self.collectionView = [[NSCollectionView alloc] initWithFrame:NSMakeRect(0, 0, 400, 40)];
        self.collectionView.itemPrototype = [MCCapePreviewItem new];
        self.collectionView.backgroundColors = @[ NSColor.clearColor ];
        self.collectionView.selectable = NO;
        self.collectionView.maxNumberOfRows = 1;
        self.collectionView.minItemSize = self.collectionView.itemPrototype.view.frame.size;
        self.collectionView.maxItemSize = self.collectionView.minItemSize;
        self.collectionView.autoresizingMask = NSViewWidthSizable;
        [self.collectionView bind:NSContentBinding toObject:self withKeyPath:@"objectValue.cursors" options:@{
            NSValueTransformerBindingOption: [MCSortValueTransformer new]
        }];

        NSScrollView *scrollView = [[NSScrollView alloc] init];
        scrollView.drawsBackground = NO;
        scrollView.borderType = NSNoBorder;
        scrollView.hasVerticalScroller = NO;
        scrollView.hasHorizontalScroller = NO;
        scrollView.verticalScrollElasticity = NSScrollElasticityNone;
        scrollView.horizontalScrollElasticity = NSScrollElasticityNone;
        scrollView.documentView = self.collectionView;
        scrollView.translatesAutoresizingMaskIntoConstraints = NO;

        self.previewWell = [[MCPreviewWellView alloc] init];
        self.previewWell.translatesAutoresizingMaskIntoConstraints = NO;
        [self.previewWell addSubview:scrollView];

        for (NSView *view in @[ header, badges, self.previewWell ]) {
            view.translatesAutoresizingMaskIntoConstraints = NO;
            [self addSubview:view];
        }

        CGFloat itemHeight = self.collectionView.minItemSize.height;
        [NSLayoutConstraint activateConstraints:@[
            [header.topAnchor constraintEqualToAnchor:self.topAnchor constant:12],
            [header.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:14],
            [badges.leadingAnchor constraintGreaterThanOrEqualToAnchor:header.trailingAnchor constant:12],
            [badges.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-14],
            [badges.centerYAnchor constraintEqualToAnchor:nameField.centerYAnchor],

            [self.previewWell.topAnchor constraintEqualToAnchor:header.bottomAnchor constant:10],
            [self.previewWell.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:10],
            [self.previewWell.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-10],

            [scrollView.leadingAnchor constraintEqualToAnchor:self.previewWell.leadingAnchor constant:8],
            [scrollView.trailingAnchor constraintEqualToAnchor:self.previewWell.trailingAnchor constant:-8],
            [scrollView.centerYAnchor constraintEqualToAnchor:self.previewWell.centerYAnchor],
            [scrollView.heightAnchor constraintEqualToConstant:itemHeight],
            [self.previewWell.heightAnchor constraintEqualToConstant:itemHeight + 12],
        ]];
    }
    return self;
}

- (void)dealloc {
    [self.collectionView unbind:NSContentBinding];
    [self.textField unbind:NSValueBinding];
    [self.authorField unbind:@"displayPatternValue1"];
    [self.resolutionBadge.label unbind:NSValueBinding];
}

// The height a row needs for this layout
+ (CGFloat)rowHeight {
    return 12 + 19 + 10 + 40 + 12 + 10;
}

- (void)setApplied:(BOOL)applied {
    _applied = applied;
    self.appliedBadge.hidden = !applied;
}

- (void)setBackgroundStyle:(NSBackgroundStyle)backgroundStyle {
    [super setBackgroundStyle:backgroundStyle];

    BOOL emphasized = backgroundStyle == NSBackgroundStyleEmphasized;
    self.textField.textColor = emphasized ? NSColor.alternateSelectedControlTextColor : NSColor.labelColor;
    self.authorField.textColor = emphasized ? [NSColor.alternateSelectedControlTextColor colorWithAlphaComponent:0.8] : NSColor.secondaryLabelColor;
    self.appliedBadge.emphasized = emphasized;
    self.resolutionBadge.emphasized = emphasized;
    self.previewWell.emphasized = emphasized;
}

@end

@implementation MCBadgeView

- (instancetype)initWithSymbolName:(NSString *)symbolName tintColor:(NSColor *)tintColor {
    if ((self = [super initWithFrame:NSZeroRect])) {
        self.wantsLayer = YES;
        self.layer.cornerCurve = kCACornerCurveContinuous;
        _tintColor = tintColor;

        _label = [NSTextField labelWithString:@""];
        _label.font = [NSFont systemFontOfSize:11 weight:NSFontWeightSemibold];

        NSMutableArray *views = [NSMutableArray array];
        if (symbolName) {
            NSImage *image = [NSImage imageWithSystemSymbolName:symbolName accessibilityDescription:nil];
            _imageView = [NSImageView imageViewWithImage:[image imageWithSymbolConfiguration:[NSImageSymbolConfiguration configurationWithPointSize:11 weight:NSFontWeightSemibold]]];
            [views addObject:_imageView];
        }
        [views addObject:_label];

        NSStackView *stack = [NSStackView stackViewWithViews:views];
        stack.spacing = 3;
        stack.edgeInsets = NSEdgeInsetsMake(2, symbolName ? 5 : 7, 2, 7);
        stack.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:stack];
        [NSLayoutConstraint activateConstraints:@[
            [stack.topAnchor constraintEqualToAnchor:self.topAnchor],
            [stack.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
            [stack.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [stack.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        ]];
        [self updateColors];
    }
    return self;
}

- (void)setEmphasized:(BOOL)emphasized {
    _emphasized = emphasized;
    [self updateColors];
}

- (void)updateColors {
    NSColor *color = self.emphasized ? NSColor.alternateSelectedControlTextColor : self.tintColor;
    self.label.textColor = color;
    self.imageView.contentTintColor = color;
    self.needsDisplay = YES;
}

- (BOOL)wantsUpdateLayer {
    return YES;
}

- (void)updateLayer {
    // Resolved here so the fill follows light and dark mode
    NSColor *fill = self.emphasized ? NSColor.alternateSelectedControlTextColor : self.tintColor;
    self.layer.backgroundColor = [fill colorWithAlphaComponent:self.emphasized ? 0.22 : 0.16].CGColor;
    self.layer.cornerRadius = NSHeight(self.bounds) / 2;
}

- (void)layout {
    [super layout];
    self.needsDisplay = YES;
}

@end

@implementation MCPreviewWellView

- (instancetype)initWithFrame:(NSRect)frameRect {
    if ((self = [super initWithFrame:frameRect])) {
        self.wantsLayer = YES;
        self.layer.cornerRadius = 10;
        self.layer.cornerCurve = kCACornerCurveContinuous;
    }
    return self;
}

- (void)setEmphasized:(BOOL)emphasized {
    _emphasized = emphasized;
    self.needsDisplay = YES;
}

- (BOOL)wantsUpdateLayer {
    return YES;
}

- (void)updateLayer {
    NSColor *fill = self.emphasized ? NSColor.alternateSelectedControlTextColor : NSColor.labelColor;
    self.layer.backgroundColor = [fill colorWithAlphaComponent:self.emphasized ? 0.14 : 0.05].CGColor;
}

@end

@implementation MCSortValueTransformer

+ (Class)transformedValueClass {
    return [NSSet class];
}

- (NSArray *)transformedValue:(NSSet *)value {
    return [value sortedArrayUsingDescriptors: @[ [NSSortDescriptor sortDescriptorWithKey:@"name" ascending:YES selector:@selector(caseInsensitiveCompare:)] ]];
}

@end

@implementation MCResolutionValueTransformer

+ (Class)transformedValueClass {
    return [NSString class];
}

- (NSString *)transformedValue:(NSNumber *)value {
    return value.boolValue ? NSLocalizedString(@"HD", @"Badge for capes with Retina images") : NSLocalizedString(@"SD", @"Badge for capes without Retina images");
}

@end
