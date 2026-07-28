#import "CSFormatter.h"

#import <math.h>

NSString *CSFormatPercentage(double value) {
    return [NSString stringWithFormat:@"%.0f%%", round(value * 100.0)];
}

NSString *CSFormatBytes(uint64_t value) {
    return [NSByteCountFormatter stringFromByteCount:(int64_t)value
                                         countStyle:NSByteCountFormatterCountStyleMemory];
}

NSString *CSFormatCompactBytes(uint64_t value) {
    static NSArray<NSString *> *units;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        units = @[@"B", @"K", @"M", @"G", @"T"];
    });

    double scaled = (double)value;
    NSUInteger unitIndex = 0;
    while (scaled >= 1024.0 && unitIndex < units.count - 1) {
        scaled /= 1024.0;
        unitIndex += 1;
    }

    NSString *number;
    if (unitIndex == 0 || scaled >= 100.0) {
        number = [NSString stringWithFormat:@"%.0f", round(scaled)];
    } else if (scaled >= 10.0) {
        number = [NSString stringWithFormat:@"%.1f", scaled];
    } else {
        number = [NSString stringWithFormat:@"%.2f", scaled];
    }
    return [number stringByAppendingString:units[unitIndex]];
}

NSString *CSFormatRate(double bytesPerSecond) {
    static NSArray<NSString *> *units;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        units = @[@"B/s", @"K/s", @"M/s", @"G/s"];
    });

    double scaled = MAX(bytesPerSecond, 0.0);
    NSUInteger unitIndex = 0;
    while (scaled >= 1000.0 && unitIndex < units.count - 1) {
        scaled /= 1000.0;
        unitIndex += 1;
    }

    NSString *number;
    if (unitIndex == 0 || scaled >= 100.0) {
        number = [NSString stringWithFormat:@"%.0f", round(scaled)];
    } else if (scaled >= 10.0) {
        number = [NSString stringWithFormat:@"%.1f", scaled];
    } else {
        number = [NSString stringWithFormat:@"%.2f", scaled];
    }
    return [number stringByAppendingString:units[unitIndex]];
}
