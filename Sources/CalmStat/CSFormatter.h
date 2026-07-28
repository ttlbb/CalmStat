#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

NSString *CSFormatPercentage(double value);
NSString *CSFormatBytes(uint64_t value);
NSString *CSFormatCompactBytes(uint64_t value);
NSString *CSFormatRate(double bytesPerSecond);

NS_ASSUME_NONNULL_END
