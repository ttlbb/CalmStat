#import "CSMenuBarController.h"

#import "CSFormatter.h"
#import "CSNetworkFloatingPanel.h"
#import "CSSystemMonitor.h"
#import <ServiceManagement/ServiceManagement.h>

static NSString *const CSShowCPUKey = @"showCPU";
static NSString *const CSShowMemoryKey = @"showMemory";
static NSString *const CSShowSwapKey = @"showSwap";
static NSString *const CSShowDiskKey = @"showDisk";
static NSString *const CSShowNetworkKey = @"showNetwork";
static NSString *const CSFloatingNetworkKey = @"floatingNetworkEnabled";
static NSString *const CSRefreshIntervalKey = @"refreshInterval";

typedef NS_ENUM(NSInteger, CSDisplayTag) {
    CSDisplayTagSwap = 100,
    CSDisplayTagCPU = 101,
    CSDisplayTagMemory = 102,
    CSDisplayTagDisk = 103,
    CSDisplayTagNetwork = 104,
};

@interface CSMenuBarController ()

@property(nonatomic, strong) CSSystemMonitor *monitor;
@property(nonatomic, strong) CSNetworkFloatingPanel *networkPanel;
@property(nonatomic, strong) SMAppService *loginService;
@property(nonatomic, strong) NSStatusItem *statusItem;
@property(nonatomic, strong) NSMenu *menu;
@property(nonatomic, strong) NSMenuItem *swapDetailItem;
@property(nonatomic, strong) NSMenuItem *cpuDetailItem;
@property(nonatomic, strong) NSMenuItem *memoryDetailItem;
@property(nonatomic, strong) NSMenuItem *diskDetailItem;
@property(nonatomic, strong) NSMenuItem *networkDetailItem;
@property(nonatomic, strong) NSMenuItem *floatingNetworkItem;
@property(nonatomic, strong) NSMenuItem *launchAtLoginItem;
@property(nonatomic, strong, nullable) NSTimer *timer;
@property(nonatomic, strong, nullable) CSSystemSnapshot *latestSnapshot;

@end

@implementation CSMenuBarController

- (instancetype)init {
    self = [super init];
    if (self) {
        _monitor = [[CSSystemMonitor alloc] init];
        _networkPanel = [[CSNetworkFloatingPanel alloc] init];
        _loginService = SMAppService.mainAppService;
        _statusItem = [NSStatusBar.systemStatusBar statusItemWithLength:NSVariableStatusItemLength];
        _menu = [[NSMenu alloc] init];
        _swapDetailItem = [[NSMenuItem alloc] init];
        _cpuDetailItem = [[NSMenuItem alloc] init];
        _memoryDetailItem = [[NSMenuItem alloc] init];
        _diskDetailItem = [[NSMenuItem alloc] init];
        _networkDetailItem = [[NSMenuItem alloc] init];

        [self registerDefaults];
        [self configureStatusItem];
        [self configureMenu];
        [self restartTimer];
        [self refresh];
    }
    return self;
}

- (void)dealloc {
    [_timer invalidate];
    [NSStatusBar.systemStatusBar removeStatusItem:_statusItem];
}

- (void)registerDefaults {
    [NSUserDefaults.standardUserDefaults registerDefaults:@{
        CSShowSwapKey: @YES,
        CSShowCPUKey: @YES,
        CSShowMemoryKey: @YES,
        CSShowDiskKey: @YES,
        CSShowNetworkKey: @NO,
        CSFloatingNetworkKey: @YES,
        CSRefreshIntervalKey: @1.0,
    }];
}

- (void)configureStatusItem {
    NSStatusBarButton *button = self.statusItem.button;
    button.font = [NSFont monospacedSystemFontOfSize:11 weight:NSFontWeightMedium];
    button.toolTip = @"CalmStat 系统监控";
}

- (void)configureMenu {
    self.menu.delegate = self;
    self.menu.autoenablesItems = NO;

    for (NSMenuItem *item in @[
        self.swapDetailItem,
        self.cpuDetailItem,
        self.memoryDetailItem,
        self.diskDetailItem,
        self.networkDetailItem,
    ]) {
        item.enabled = NO;
        [self.menu addItem:item];
    }

    [self.menu addItem:NSMenuItem.separatorItem];

    NSMenuItem *displayItem = [[NSMenuItem alloc] initWithTitle:@"菜单栏显示"
                                                         action:nil
                                                  keyEquivalent:@""];
    NSMenu *displayMenu = [[NSMenu alloc] init];
    [displayMenu addItem:[self toggleItemWithTitle:@"Swap" tag:CSDisplayTagSwap]];
    [displayMenu addItem:[self toggleItemWithTitle:@"CPU" tag:CSDisplayTagCPU]];
    [displayMenu addItem:[self toggleItemWithTitle:@"内存" tag:CSDisplayTagMemory]];
    [displayMenu addItem:[self toggleItemWithTitle:@"磁盘" tag:CSDisplayTagDisk]];
    [displayMenu addItem:[self toggleItemWithTitle:@"网络" tag:CSDisplayTagNetwork]];
    displayItem.submenu = displayMenu;
    [self.menu addItem:displayItem];

    self.floatingNetworkItem =
        [[NSMenuItem alloc] initWithTitle:@"悬浮显示网络速率"
                                   action:@selector(toggleFloatingNetwork:)
                            keyEquivalent:@""];
    self.floatingNetworkItem.target = self;
    [self.menu addItem:self.floatingNetworkItem];

    self.launchAtLoginItem =
        [[NSMenuItem alloc] initWithTitle:@"开机启动"
                                   action:@selector(toggleLaunchAtLogin:)
                            keyEquivalent:@""];
    self.launchAtLoginItem.target = self;
    [self.menu addItem:self.launchAtLoginItem];

    NSMenuItem *refreshItem = [[NSMenuItem alloc] initWithTitle:@"刷新频率"
                                                         action:nil
                                                  keyEquivalent:@""];
    NSMenu *refreshMenu = [[NSMenu alloc] init];
    [refreshMenu addItem:[self intervalItemWithTitle:@"每秒" interval:1]];
    [refreshMenu addItem:[self intervalItemWithTitle:@"每 2 秒" interval:2]];
    [refreshMenu addItem:[self intervalItemWithTitle:@"每 5 秒" interval:5]];
    refreshItem.submenu = refreshMenu;
    [self.menu addItem:refreshItem];

    [self.menu addItem:NSMenuItem.separatorItem];

    NSMenuItem *quitItem = [[NSMenuItem alloc] initWithTitle:@"退出 CalmStat"
                                                      action:@selector(terminate:)
                                               keyEquivalent:@"q"];
    quitItem.target = NSApplication.sharedApplication;
    [self.menu addItem:quitItem];

    self.statusItem.menu = self.menu;
    [self updatePreferenceStates];
}

- (NSMenuItem *)toggleItemWithTitle:(NSString *)title tag:(CSDisplayTag)tag {
    NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:title
                                                  action:@selector(toggleDisplay:)
                                           keyEquivalent:@""];
    item.target = self;
    item.tag = tag;
    return item;
}

- (NSMenuItem *)intervalItemWithTitle:(NSString *)title interval:(NSTimeInterval)interval {
    NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:title
                                                  action:@selector(changeRefreshInterval:)
                                           keyEquivalent:@""];
    item.target = self;
    item.representedObject = @(interval);
    return item;
}

- (void)restartTimer {
    [self.timer invalidate];
    NSTimeInterval interval = [NSUserDefaults.standardUserDefaults doubleForKey:CSRefreshIntervalKey];
    self.timer = [NSTimer timerWithTimeInterval:MAX(interval, 0.25)
                                         target:self
                                       selector:@selector(refresh)
                                       userInfo:nil
                                        repeats:YES];
    [NSRunLoop.mainRunLoop addTimer:self.timer forMode:NSRunLoopCommonModes];
}

- (void)refresh {
    CSSystemSnapshot *snapshot = [self.monitor sample];
    self.latestSnapshot = snapshot;
    [self.networkPanel updateDownloadRate:snapshot.downloadBytesPerSecond
                               uploadRate:snapshot.uploadBytesPerSecond];
    [self updateFloatingPanelVisibility];
    [self updateStatusTitleWithSnapshot:snapshot];
    [self updateDetailsWithSnapshot:snapshot];
}

- (void)updateStatusTitleWithSnapshot:(CSSystemSnapshot *)snapshot {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    NSFont *font = [NSFont monospacedSystemFontOfSize:11 weight:NSFontWeightMedium];
    NSDictionary<NSAttributedStringKey, id> *normalAttributes = @{
        NSFontAttributeName: font,
        NSForegroundColorAttributeName: NSColor.labelColor,
    };
    BOOL isUsingSwap = snapshot.swapUsed > 0;
    NSDictionary<NSAttributedStringKey, id> *swapAttributes = @{
        NSFontAttributeName: font,
        NSForegroundColorAttributeName:
            isUsingSwap ? NSColor.systemRedColor : NSColor.secondaryLabelColor,
    };
    NSDictionary<NSAttributedStringKey, id> *memoryAttributes = @{
        NSFontAttributeName: font,
        NSForegroundColorAttributeName:
            isUsingSwap ? NSColor.systemRedColor : NSColor.labelColor,
    };
    NSMutableAttributedString *title = [[NSMutableAttributedString alloc] init];

    if ([defaults boolForKey:CSShowSwapKey]) {
        [self appendComponent:@"S" attributes:swapAttributes toTitle:title];
    }
    if ([defaults boolForKey:CSShowCPUKey]) {
        [self appendComponent:[NSString stringWithFormat:@"CPU %@",
            CSFormatPercentage(snapshot.cpuUsage)] attributes:normalAttributes toTitle:title];
    }
    if ([defaults boolForKey:CSShowMemoryKey]) {
        [self appendComponent:[NSString stringWithFormat:@"MEM %@",
            CSFormatPercentage(snapshot.memoryUsage)] attributes:memoryAttributes toTitle:title];
    }
    if ([defaults boolForKey:CSShowDiskKey]) {
        [self appendComponent:[NSString stringWithFormat:@"SSD %@",
            CSFormatPercentage(snapshot.diskUsage)] attributes:normalAttributes toTitle:title];
    }
    if ([defaults boolForKey:CSShowNetworkKey]) {
        [self appendComponent:[NSString stringWithFormat:@"↓%@ ↑%@",
            CSFormatRate(snapshot.downloadBytesPerSecond),
            CSFormatRate(snapshot.uploadBytesPerSecond)]
            attributes:normalAttributes
            toTitle:title];
    }

    if (title.length == 0) {
        [title appendAttributedString:[[NSAttributedString alloc] initWithString:@"CalmStat"
                                                                      attributes:normalAttributes]];
    }
    self.statusItem.button.attributedTitle = title;
    self.statusItem.button.toolTip = isUsingSwap
        ? [NSString stringWithFormat:@"Swap 已使用 %@", CSFormatBytes(snapshot.swapUsed)]
        : @"Swap 未使用";
}

- (void)appendComponent:(NSString *)component
             attributes:(NSDictionary<NSAttributedStringKey, id> *)attributes
                toTitle:(NSMutableAttributedString *)title {
    if (title.length > 0) {
        [title appendAttributedString:[[NSAttributedString alloc] initWithString:@"  "
                                                                      attributes:attributes]];
    }
    [title appendAttributedString:[[NSAttributedString alloc] initWithString:component
                                                                  attributes:attributes]];
}

- (void)updateDetailsWithSnapshot:(CSSystemSnapshot *)snapshot {
    if (snapshot.swapUsed > 0) {
        self.swapDetailItem.title = [NSString stringWithFormat:@"Swap    已使用 %@ / %@  (%@)",
            CSFormatBytes(snapshot.swapUsed),
            CSFormatBytes(snapshot.swapTotal),
            CSFormatPercentage(snapshot.swapUsage)];
    } else {
        self.swapDetailItem.title = @"Swap    未使用";
    }
    self.cpuDetailItem.title =
        [NSString stringWithFormat:@"CPU 使用率    %@", CSFormatPercentage(snapshot.cpuUsage)];
    self.memoryDetailItem.title = [NSString stringWithFormat:@"内存    %@ / %@  (%@)",
        CSFormatBytes(snapshot.memoryUsed),
        CSFormatBytes(snapshot.memoryTotal),
        CSFormatPercentage(snapshot.memoryUsage)];
    self.diskDetailItem.title = [NSString stringWithFormat:@"磁盘    %@ / %@  (%@)",
        CSFormatBytes(snapshot.diskUsed),
        CSFormatBytes(snapshot.diskTotal),
        CSFormatPercentage(snapshot.diskUsage)];
    self.networkDetailItem.title = [NSString stringWithFormat:@"网络    ↓ %@    ↑ %@",
        CSFormatRate(snapshot.downloadBytesPerSecond),
        CSFormatRate(snapshot.uploadBytesPerSecond)];
}

- (void)toggleDisplay:(NSMenuItem *)sender {
    NSString *key = [self preferenceKeyForTag:sender.tag];
    if (key == nil) {
        return;
    }

    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    [defaults setBool:![defaults boolForKey:key] forKey:key];
    [self updatePreferenceStates];
    if (self.latestSnapshot != nil) {
        [self updateStatusTitleWithSnapshot:self.latestSnapshot];
    }
}

- (void)changeRefreshInterval:(NSMenuItem *)sender {
    NSNumber *interval = sender.representedObject;
    if (![interval isKindOfClass:NSNumber.class]) {
        return;
    }

    [NSUserDefaults.standardUserDefaults setDouble:interval.doubleValue forKey:CSRefreshIntervalKey];
    [self updatePreferenceStates];
    [self restartTimer];
    [self refresh];
}

- (void)toggleFloatingNetwork:(NSMenuItem *)sender {
    (void)sender;
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    [defaults setBool:![defaults boolForKey:CSFloatingNetworkKey] forKey:CSFloatingNetworkKey];
    [self updatePreferenceStates];
    [self updateFloatingPanelVisibility];
}

- (void)toggleLaunchAtLogin:(NSMenuItem *)sender {
    (void)sender;
    SMAppServiceStatus status = self.loginService.status;

    if (status == SMAppServiceStatusRequiresApproval) {
        [SMAppService openSystemSettingsLoginItems];
        return;
    }

    NSError *error = nil;
    BOOL succeeded = status == SMAppServiceStatusEnabled
        ? [self.loginService unregisterAndReturnError:&error]
        : [self.loginService registerAndReturnError:&error];

    [self updateLaunchAtLoginState];
    if (!succeeded) {
        [self showLaunchAtLoginError:error];
    } else if (self.loginService.status == SMAppServiceStatusRequiresApproval) {
        [self showLaunchAtLoginApproval];
    }
}

- (void)enableLaunchAtLoginIfNeeded {
    if (self.loginService.status == SMAppServiceStatusEnabled) {
        [self updateLaunchAtLoginState];
        return;
    }

    if (self.loginService.status == SMAppServiceStatusRequiresApproval) {
        [self updateLaunchAtLoginState];
        [self showLaunchAtLoginApproval];
        return;
    }

    NSError *error = nil;
    BOOL succeeded = [self.loginService registerAndReturnError:&error];
    [self updateLaunchAtLoginState];
    if (!succeeded) {
        [self showLaunchAtLoginError:error];
    } else if (self.loginService.status == SMAppServiceStatusRequiresApproval) {
        [self showLaunchAtLoginApproval];
    }
}

- (void)showLaunchAtLoginError:(NSError *)error {
    [NSApplication.sharedApplication activateIgnoringOtherApps:YES];
    NSAlert *alert = [[NSAlert alloc] init];
    alert.alertStyle = NSAlertStyleWarning;
    alert.messageText = @"无法启用开机启动";
    alert.informativeText = error.localizedDescription.length > 0
        ? error.localizedDescription
        : @"请将 CalmStat.app 移到“应用程序”文件夹后重试。";
    [alert addButtonWithTitle:@"好"];
    [alert runModal];
}

- (void)showLaunchAtLoginApproval {
    [NSApplication.sharedApplication activateIgnoringOtherApps:YES];
    NSAlert *alert = [[NSAlert alloc] init];
    alert.alertStyle = NSAlertStyleInformational;
    alert.messageText = @"需要批准 CalmStat";
    alert.informativeText = @"请在“系统设置 → 通用 → 登录项”中允许 CalmStat 后台运行。";
    [alert addButtonWithTitle:@"打开系统设置"];
    [alert addButtonWithTitle:@"稍后"];
    if ([alert runModal] == NSAlertFirstButtonReturn) {
        [SMAppService openSystemSettingsLoginItems];
    }
}

- (void)updateLaunchAtLoginState {
    switch (self.loginService.status) {
        case SMAppServiceStatusEnabled:
            self.launchAtLoginItem.title = @"开机启动";
            self.launchAtLoginItem.state = NSControlStateValueOn;
            break;
        case SMAppServiceStatusRequiresApproval:
            self.launchAtLoginItem.title = @"开机启动（需要批准）";
            self.launchAtLoginItem.state = NSControlStateValueMixed;
            break;
        case SMAppServiceStatusNotRegistered:
        case SMAppServiceStatusNotFound:
            self.launchAtLoginItem.title = @"开机启动";
            self.launchAtLoginItem.state = NSControlStateValueOff;
            break;
    }
}

- (void)updateFloatingPanelVisibility {
    if ([NSUserDefaults.standardUserDefaults boolForKey:CSFloatingNetworkKey]) {
        [self.networkPanel showPanel];
    } else {
        [self.networkPanel hidePanel];
    }
}

- (nullable NSString *)preferenceKeyForTag:(NSInteger)tag {
    switch (tag) {
        case CSDisplayTagSwap:
            return CSShowSwapKey;
        case CSDisplayTagCPU:
            return CSShowCPUKey;
        case CSDisplayTagMemory:
            return CSShowMemoryKey;
        case CSDisplayTagDisk:
            return CSShowDiskKey;
        case CSDisplayTagNetwork:
            return CSShowNetworkKey;
        default:
            return nil;
    }
}

- (void)updatePreferenceStates {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    [self updateLaunchAtLoginState];
    self.floatingNetworkItem.state = [defaults boolForKey:CSFloatingNetworkKey]
        ? NSControlStateValueOn
        : NSControlStateValueOff;
    NSMenu *displayMenu = [self.menu itemWithTitle:@"菜单栏显示"].submenu;
    for (NSMenuItem *item in displayMenu.itemArray) {
        NSString *key = [self preferenceKeyForTag:item.tag];
        item.state = key != nil && [defaults boolForKey:key] ? NSControlStateValueOn : NSControlStateValueOff;
    }

    double selectedInterval = [defaults doubleForKey:CSRefreshIntervalKey];
    NSMenu *refreshMenu = [self.menu itemWithTitle:@"刷新频率"].submenu;
    for (NSMenuItem *item in refreshMenu.itemArray) {
        NSNumber *interval = item.representedObject;
        item.state = interval != nil && interval.doubleValue == selectedInterval
            ? NSControlStateValueOn
            : NSControlStateValueOff;
    }
}

- (void)menuWillOpen:(NSMenu *)menu {
    (void)menu;
    [self updateLaunchAtLoginState];
    [self refresh];
}

@end
