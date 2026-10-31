//
//  Logging.m
//  ViKey
//

#import "Logging.h"
#import <os/lock.h>
#import <os/log.h>

#define LOG_SUBSYSTEM "com.hkvn.vikey"
#define MAX_RECENT_ENTRIES 300

static os_unfair_lock _lock = OS_UNFAIR_LOCK_INIT;
static NSMutableArray<NSString*>* _recentEntries;
static NSMutableDictionary<NSString*, os_log_t>* _logs;
static NSDateFormatter* _timeFormatter;

static void addEntry(NSString* category, NSString* message) {
    os_unfair_lock_lock(&_lock);
    if (_recentEntries == nil) {
        _recentEntries = [NSMutableArray arrayWithCapacity:MAX_RECENT_ENTRIES];
        _logs = [NSMutableDictionary dictionary];
        _timeFormatter = [[NSDateFormatter alloc] init];
        _timeFormatter.dateFormat = @"HH:mm:ss.SSS";
    }
    os_log_t log = _logs[category];
    if (log == nil) {
        log = os_log_create(LOG_SUBSYSTEM, category.UTF8String);
        _logs[category] = log;
    }
    if (_recentEntries.count >= MAX_RECENT_ENTRIES)
        [_recentEntries removeObjectAtIndex:0];
    [_recentEntries addObject:[NSString stringWithFormat:@"%@ [%@] %@", [_timeFormatter stringFromDate:[NSDate date]], category, message]];
    os_unfair_lock_unlock(&_lock);
    os_log(log, "%{public}@", message);
}

void VKLog(NSString* category, NSString* format, ...) {
    va_list args;
    va_start(args, format);
    NSString* message = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    addEntry(category, message);
}

@implementation VKLogger
+(void)log:(NSString*)message category:(NSString*)category {
    addEntry(category, message);
}

+(NSArray<NSString*>*)recentEntries {
    os_unfair_lock_lock(&_lock);
    NSArray<NSString*>* entries = [_recentEntries copy] ?: @[];
    os_unfair_lock_unlock(&_lock);
    return entries;
}
@end
