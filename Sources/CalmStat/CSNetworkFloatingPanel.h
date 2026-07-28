#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@interface CSNetworkFloatingPanel : NSPanel

- (void)updateDownloadRate:(double)downloadRate uploadRate:(double)uploadRate;
- (void)showPanel;
- (void)hidePanel;

@end

NS_ASSUME_NONNULL_END
