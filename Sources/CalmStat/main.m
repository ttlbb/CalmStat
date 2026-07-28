#import <Cocoa/Cocoa.h>

#import "CSMenuBarController.h"

@interface CSAppDelegate : NSObject <NSApplicationDelegate>

@property(nonatomic, strong) CSMenuBarController *menuBarController;

@end

@implementation CSAppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    (void)notification;
    [NSApplication.sharedApplication setActivationPolicy:NSApplicationActivationPolicyAccessory];
    self.menuBarController = [[CSMenuBarController alloc] init];
    if ([NSProcessInfo.processInfo.arguments containsObject:@"--enable-launch-at-login"]) {
        [self.menuBarController enableLaunchAtLoginIfNeeded];
    }
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender {
    (void)sender;
    return NO;
}

@end

int main(int argc, const char *argv[]) {
    (void)argc;
    (void)argv;

    @autoreleasepool {
        NSApplication *application = NSApplication.sharedApplication;
        CSAppDelegate *delegate = [[CSAppDelegate alloc] init];
        application.delegate = delegate;
        [application run];
    }
    return 0;
}
