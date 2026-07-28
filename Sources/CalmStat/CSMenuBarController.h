#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@interface CSMenuBarController : NSObject <NSMenuDelegate>

- (void)enableLaunchAtLoginIfNeeded;

@end

NS_ASSUME_NONNULL_END
