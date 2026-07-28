#import "CSSystemMonitor.h"

#import <ifaddrs.h>
#import <mach/mach.h>
#import <mach/processor_info.h>
#import <mach/vm_statistics.h>
#import <net/if.h>
#import <net/if_dl.h>
#import <sys/sysctl.h>

@implementation CSSystemSnapshot

- (double)memoryUsage {
    return self.memoryTotal > 0 ? (double)self.memoryUsed / (double)self.memoryTotal : 0.0;
}

- (double)swapUsage {
    return self.swapTotal > 0 ? (double)self.swapUsed / (double)self.swapTotal : 0.0;
}

- (double)diskUsage {
    return self.diskTotal > 0 ? (double)self.diskUsed / (double)self.diskTotal : 0.0;
}

@end

@interface CSSystemMonitor () {
    uint64_t _previousCPUBusy;
    uint64_t _previousCPUTotal;
    BOOL _hasPreviousCPU;

    uint64_t _previousReceived;
    uint64_t _previousSent;
    NSTimeInterval _previousNetworkUptime;
    BOOL _hasPreviousNetwork;
}
@end

@implementation CSSystemMonitor

- (CSSystemSnapshot *)sample {
    CSSystemSnapshot *snapshot = [[CSSystemSnapshot alloc] init];
    snapshot.cpuUsage = [self cpuUsage];

    uint64_t memoryUsed = 0;
    uint64_t memoryTotal = 0;
    [self memoryUsed:&memoryUsed total:&memoryTotal];
    snapshot.memoryUsed = memoryUsed;
    snapshot.memoryTotal = memoryTotal;

    uint64_t swapUsed = 0;
    uint64_t swapTotal = 0;
    [self swapUsed:&swapUsed total:&swapTotal];
    snapshot.swapUsed = swapUsed;
    snapshot.swapTotal = swapTotal;

    uint64_t diskUsed = 0;
    uint64_t diskTotal = 0;
    [self diskUsed:&diskUsed total:&diskTotal];
    snapshot.diskUsed = diskUsed;
    snapshot.diskTotal = diskTotal;

    double download = 0;
    double upload = 0;
    [self downloadRate:&download uploadRate:&upload];
    snapshot.downloadBytesPerSecond = download;
    snapshot.uploadBytesPerSecond = upload;

    return snapshot;
}

- (double)cpuUsage {
    natural_t cpuCount = 0;
    processor_info_array_t cpuInfo = NULL;
    mach_msg_type_number_t cpuInfoCount = 0;

    kern_return_t result = host_processor_info(
        mach_host_self(),
        PROCESSOR_CPU_LOAD_INFO,
        &cpuCount,
        &cpuInfo,
        &cpuInfoCount
    );
    if (result != KERN_SUCCESS || cpuInfo == NULL) {
        return 0.0;
    }

    processor_cpu_load_info_t loadInfo = (processor_cpu_load_info_t)cpuInfo;
    uint64_t busy = 0;
    uint64_t total = 0;

    for (natural_t cpu = 0; cpu < cpuCount; cpu++) {
        uint64_t user = loadInfo[cpu].cpu_ticks[CPU_STATE_USER];
        uint64_t system = loadInfo[cpu].cpu_ticks[CPU_STATE_SYSTEM];
        uint64_t nice = loadInfo[cpu].cpu_ticks[CPU_STATE_NICE];
        uint64_t idle = loadInfo[cpu].cpu_ticks[CPU_STATE_IDLE];
        busy += user + system + nice;
        total += user + system + nice + idle;
    }

    vm_size_t size = (vm_size_t)cpuInfoCount * sizeof(integer_t);
    vm_deallocate(mach_task_self(), (vm_address_t)cpuInfo, size);

    double usage;
    if (_hasPreviousCPU && total >= _previousCPUTotal && busy >= _previousCPUBusy) {
        uint64_t totalDelta = total - _previousCPUTotal;
        uint64_t busyDelta = busy - _previousCPUBusy;
        usage = totalDelta > 0 ? (double)busyDelta / (double)totalDelta : 0.0;
    } else {
        usage = total > 0 ? (double)busy / (double)total : 0.0;
    }

    _previousCPUBusy = busy;
    _previousCPUTotal = total;
    _hasPreviousCPU = YES;
    return usage;
}

- (void)memoryUsed:(uint64_t *)used total:(uint64_t *)total {
    vm_statistics64_data_t statistics;
    mach_msg_type_number_t count = HOST_VM_INFO64_COUNT;
    kern_return_t result = host_statistics64(
        mach_host_self(),
        HOST_VM_INFO64,
        (host_info64_t)&statistics,
        &count
    );

    *total = NSProcessInfo.processInfo.physicalMemory;
    if (result != KERN_SUCCESS) {
        *used = 0;
        return;
    }

    uint64_t pageSize = vm_kernel_page_size;
    uint64_t active = (uint64_t)statistics.active_count * pageSize;
    uint64_t wired = (uint64_t)statistics.wire_count * pageSize;
    uint64_t compressed = (uint64_t)statistics.compressor_page_count * pageSize;
    *used = MIN(active + wired + compressed, *total);
}

- (void)swapUsed:(uint64_t *)used total:(uint64_t *)total {
    struct xsw_usage swapUsage;
    size_t size = sizeof(swapUsage);
    if (sysctlbyname("vm.swapusage", &swapUsage, &size, NULL, 0) != 0) {
        *used = 0;
        *total = 0;
        return;
    }

    *used = swapUsage.xsu_used;
    *total = swapUsage.xsu_total;
}

- (void)diskUsed:(uint64_t *)used total:(uint64_t *)total {
    NSError *error = nil;
    NSDictionary<NSFileAttributeKey, id> *attributes =
        [NSFileManager.defaultManager attributesOfFileSystemForPath:@"/" error:&error];
    if (attributes == nil || error != nil) {
        *used = 0;
        *total = 0;
        return;
    }

    uint64_t totalBytes = [attributes[NSFileSystemSize] unsignedLongLongValue];
    uint64_t freeBytes = [attributes[NSFileSystemFreeSize] unsignedLongLongValue];
    *total = totalBytes;
    *used = totalBytes >= freeBytes ? totalBytes - freeBytes : 0;
}

- (void)downloadRate:(double *)download uploadRate:(double *)upload {
    uint64_t received = 0;
    uint64_t sent = 0;
    [self networkReceived:&received sent:&sent];

    NSTimeInterval uptime = NSProcessInfo.processInfo.systemUptime;
    *download = 0;
    *upload = 0;

    if (_hasPreviousNetwork) {
        NSTimeInterval elapsed = uptime - _previousNetworkUptime;
        if (elapsed > 0) {
            uint64_t receivedDelta = received >= _previousReceived ? received - _previousReceived : 0;
            uint64_t sentDelta = sent >= _previousSent ? sent - _previousSent : 0;
            *download = (double)receivedDelta / elapsed;
            *upload = (double)sentDelta / elapsed;
        }
    }

    _previousReceived = received;
    _previousSent = sent;
    _previousNetworkUptime = uptime;
    _hasPreviousNetwork = YES;
}

- (void)networkReceived:(uint64_t *)received sent:(uint64_t *)sent {
    *received = 0;
    *sent = 0;

    struct ifaddrs *firstAddress = NULL;
    if (getifaddrs(&firstAddress) != 0 || firstAddress == NULL) {
        return;
    }

    for (struct ifaddrs *address = firstAddress; address != NULL; address = address->ifa_next) {
        if (address->ifa_addr == NULL || address->ifa_addr->sa_family != AF_LINK) {
            continue;
        }

        BOOL isUp = (address->ifa_flags & IFF_UP) != 0;
        BOOL isLoopback = (address->ifa_flags & IFF_LOOPBACK) != 0;
        if (!isUp || isLoopback || address->ifa_data == NULL) {
            continue;
        }

        const struct if_data *data = (const struct if_data *)address->ifa_data;
        *received += data->ifi_ibytes;
        *sent += data->ifi_obytes;
    }

    freeifaddrs(firstAddress);
}

@end
