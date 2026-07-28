#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface CSSystemSnapshot : NSObject

@property(nonatomic) double cpuUsage;
@property(nonatomic) uint64_t memoryUsed;
@property(nonatomic) uint64_t memoryTotal;
@property(nonatomic) uint64_t swapUsed;
@property(nonatomic) uint64_t swapTotal;
@property(nonatomic) uint64_t diskUsed;
@property(nonatomic) uint64_t diskTotal;
@property(nonatomic) double downloadBytesPerSecond;
@property(nonatomic) double uploadBytesPerSecond;

@property(nonatomic, readonly) double memoryUsage;
@property(nonatomic, readonly) double swapUsage;
@property(nonatomic, readonly) double diskUsage;

@end

@interface CSSystemMonitor : NSObject

- (CSSystemSnapshot *)sample;

@end

NS_ASSUME_NONNULL_END
