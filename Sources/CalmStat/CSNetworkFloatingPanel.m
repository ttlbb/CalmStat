#import "CSNetworkFloatingPanel.h"

#import "CSFormatter.h"

static NSString *const CSFloatingPanelXKey = @"floatingNetworkPanelX";
static NSString *const CSFloatingPanelYKey = @"floatingNetworkPanelY";

@interface CSDraggableEffectView : NSVisualEffectView
@end

@implementation CSDraggableEffectView

- (BOOL)mouseDownCanMoveWindow {
    return YES;
}

@end

@interface CSPassthroughTintView : NSView
@end

@implementation CSPassthroughTintView

- (nullable NSView *)hitTest:(NSPoint)point {
    (void)point;
    return nil;
}

@end

@interface CSNetworkFloatingPanel () <NSWindowDelegate>

@property(nonatomic, strong) NSView *tintView;
@property(nonatomic, strong) NSTextField *downloadLabel;
@property(nonatomic, strong) NSTextField *uploadLabel;

@end

@implementation CSNetworkFloatingPanel

- (instancetype)init {
    NSRect frame = NSMakeRect(0, 0, 220, 34);
    self = [super initWithContentRect:frame
                           styleMask:NSWindowStyleMaskBorderless | NSWindowStyleMaskNonactivatingPanel
                             backing:NSBackingStoreBuffered
                               defer:NO];
    if (self) {
        self.opaque = NO;
        self.backgroundColor = NSColor.clearColor;
        self.hasShadow = YES;
        self.level = NSStatusWindowLevel;
        self.hidesOnDeactivate = NO;
        self.movableByWindowBackground = YES;
        self.releasedWhenClosed = NO;
        self.animationBehavior = NSWindowAnimationBehaviorUtilityWindow;
        self.collectionBehavior =
            NSWindowCollectionBehaviorCanJoinAllSpaces |
            NSWindowCollectionBehaviorFullScreenAuxiliary;
        self.delegate = self;

        [self configureContent];
        [self restorePosition];
    }
    return self;
}

- (BOOL)canBecomeKeyWindow {
    return NO;
}

- (BOOL)canBecomeMainWindow {
    return NO;
}

- (void)configureContent {
    CSDraggableEffectView *background =
        [[CSDraggableEffectView alloc] initWithFrame:self.contentView.bounds];
    background.translatesAutoresizingMaskIntoConstraints = NO;
    background.material = NSVisualEffectMaterialHUDWindow;
    background.blendingMode = NSVisualEffectBlendingModeBehindWindow;
    background.state = NSVisualEffectStateActive;
    background.wantsLayer = YES;
    background.layer.cornerRadius = 9;
    background.layer.masksToBounds = YES;
    self.contentView = background;

    self.tintView = [[CSPassthroughTintView alloc] init];
    self.tintView.translatesAutoresizingMaskIntoConstraints = NO;
    self.tintView.wantsLayer = YES;
    self.tintView.layer.cornerRadius = 9;
    self.tintView.layer.backgroundColor = NSColor.clearColor.CGColor;
    [background addSubview:self.tintView];

    self.downloadLabel = [self rateLabelWithPrefix:@"↓"];
    self.uploadLabel = [self rateLabelWithPrefix:@"↑"];

    NSStackView *stack = [NSStackView stackViewWithViews:@[
        self.downloadLabel,
        self.uploadLabel,
    ]];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    stack.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    stack.alignment = NSLayoutAttributeCenterY;
    stack.distribution = NSStackViewDistributionFillEqually;
    stack.spacing = 10;
    [background addSubview:stack];

    [NSLayoutConstraint activateConstraints:@[
        [self.tintView.leadingAnchor constraintEqualToAnchor:background.leadingAnchor],
        [self.tintView.trailingAnchor constraintEqualToAnchor:background.trailingAnchor],
        [self.tintView.topAnchor constraintEqualToAnchor:background.topAnchor],
        [self.tintView.bottomAnchor constraintEqualToAnchor:background.bottomAnchor],
        [stack.leadingAnchor constraintEqualToAnchor:background.leadingAnchor constant:10],
        [stack.trailingAnchor constraintEqualToAnchor:background.trailingAnchor constant:-10],
        [stack.centerYAnchor constraintEqualToAnchor:background.centerYAnchor],
    ]];
}

- (NSTextField *)rateLabelWithPrefix:(NSString *)prefix {
    NSTextField *label = [NSTextField labelWithString:[prefix stringByAppendingString:@" 0B/s"]];
    label.font = [NSFont monospacedSystemFontOfSize:11 weight:NSFontWeightMedium];
    label.textColor = NSColor.labelColor;
    label.lineBreakMode = NSLineBreakByClipping;
    label.maximumNumberOfLines = 1;
    return label;
}

- (void)restorePosition {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    NSNumber *savedX = [defaults objectForKey:CSFloatingPanelXKey];
    NSNumber *savedY = [defaults objectForKey:CSFloatingPanelYKey];

    if (savedX != nil && savedY != nil) {
        NSRect savedFrame = self.frame;
        savedFrame.origin = NSMakePoint(savedX.doubleValue, savedY.doubleValue);
        for (NSScreen *screen in NSScreen.screens) {
            if (NSIntersectsRect(savedFrame, screen.visibleFrame)) {
                [self setFrame:savedFrame display:NO];
                return;
            }
        }
    }

    NSScreen *screen = NSScreen.mainScreen ?: NSScreen.screens.firstObject;
    if (screen != nil) {
        NSRect visibleFrame = screen.visibleFrame;
        NSPoint origin = NSMakePoint(
            NSMinX(visibleFrame) + 12,
            NSMaxY(visibleFrame) - NSHeight(self.frame) - 12
        );
        [self setFrameOrigin:origin];
    }
}

- (void)updateDownloadRate:(double)downloadRate
                uploadRate:(double)uploadRate
                 usingSwap:(BOOL)usingSwap {
    self.downloadLabel.stringValue =
        [NSString stringWithFormat:@"↓ %@", CSFormatRate(downloadRate)];
    self.uploadLabel.stringValue =
        [NSString stringWithFormat:@"↑ %@", CSFormatRate(uploadRate)];
    [self updateTintForSwapState:usingSwap];
}

- (void)updateTintForSwapState:(BOOL)usingSwap {
    NSColor *tintColor = usingSwap
        ? [NSColor.systemRedColor colorWithAlphaComponent:0.48]
        : [NSColor.secondaryLabelColor colorWithAlphaComponent:0.08];
    self.tintView.layer.backgroundColor = tintColor.CGColor;
}

- (void)showPanel {
    [self orderFrontRegardless];
}

- (void)hidePanel {
    [self orderOut:nil];
}

- (void)windowDidMove:(NSNotification *)notification {
    (void)notification;
    NSPoint origin = self.frame.origin;
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    [defaults setDouble:origin.x forKey:CSFloatingPanelXKey];
    [defaults setDouble:origin.y forKey:CSFloatingPanelYKey];
}

@end
