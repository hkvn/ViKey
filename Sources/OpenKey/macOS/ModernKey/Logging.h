//
//  Logging.h
//  ViKey
//
//  Log of what ViKey does, for the diagnostics window and Console.app (subsystem com.hkvn.vikey).
//  Never log the typed text.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

#ifdef __cplusplus
extern "C" {
#endif

/// can be called on any thread
void VKLog(NSString* category, NSString* format, ...) NS_FORMAT_FUNCTION(2, 3);

#ifdef __cplusplus
}
#endif

@interface VKLogger : NSObject
/// for Swift, which can not call VKLog
+(void)log:(NSString*)message category:(NSString*)category;
/// the latest entries, oldest first
+(NSArray<NSString*>*)recentEntries;
@end

NS_ASSUME_NONNULL_END
