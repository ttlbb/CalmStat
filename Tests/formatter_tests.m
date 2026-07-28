#import <Foundation/Foundation.h>

#import "CSFormatter.h"
#import "CSSystemMonitor.h"

static void AssertEqual(NSString *actual, NSString *expected) {
    if (![actual isEqualToString:expected]) {
        NSLog(@"断言失败：%@ != %@", actual, expected);
        abort();
    }
}

int main(void) {
    @autoreleasepool {
        AssertEqual(CSFormatPercentage(0.126), @"13%");
        AssertEqual(CSFormatCompactBytes(0), @"0B");
        AssertEqual(CSFormatCompactBytes(1536), @"1.50K");
        AssertEqual(CSFormatCompactBytes(1073741824), @"1.00G");
        AssertEqual(CSFormatRate(0), @"0B/s");
        AssertEqual(CSFormatRate(1500), @"1.50K/s");
        AssertEqual(CSFormatRate(12400000), @"12.4M/s");
        AssertEqual(CSFormatRate(820000000), @"820M/s");

        CSSystemSnapshot *snapshot = [[CSSystemSnapshot alloc] init];
        snapshot.memoryUsed = 6;
        snapshot.memoryTotal = 8;
        snapshot.swapUsed = 1;
        snapshot.swapTotal = 4;
        snapshot.diskUsed = 25;
        snapshot.diskTotal = 100;

        NSCAssert(fabs(snapshot.memoryUsage - 0.75) < 0.0001, @"内存比例错误");
        NSCAssert(fabs(snapshot.swapUsage - 0.25) < 0.0001, @"Swap 比例错误");
        NSCAssert(fabs(snapshot.diskUsage - 0.25) < 0.0001, @"磁盘比例错误");

        CSSystemSnapshot *liveSnapshot = [[[CSSystemMonitor alloc] init] sample];
        NSCAssert(liveSnapshot.cpuUsage >= 0 && liveSnapshot.cpuUsage <= 1, @"CPU 采样越界");
        NSCAssert(liveSnapshot.memoryTotal > 0, @"无法读取物理内存");
        NSCAssert(liveSnapshot.memoryUsed <= liveSnapshot.memoryTotal, @"内存采样越界");
        NSCAssert(liveSnapshot.swapUsed <= liveSnapshot.swapTotal, @"Swap 采样越界");
        NSCAssert(liveSnapshot.diskTotal > 0, @"无法读取系统磁盘");
        NSCAssert(liveSnapshot.diskUsed <= liveSnapshot.diskTotal, @"磁盘采样越界");
        NSLog(@"所有测试通过");
    }
    return 0;
}
