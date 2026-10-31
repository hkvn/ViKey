//
//  EngineBridge.h
//  ViKey
//
//  Objective-C API for the C++ engine, used by the Swift windows.
//  Every change is applied to the engine and saved in NSUserDefaults at once.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// one macro: the text to type and the full content
@interface VKMacro : NSObject
-(instancetype)initWithText:(NSString*)text content:(NSString*)content;
@property (nonatomic, copy, readonly) NSString* text;
@property (nonatomic, copy, readonly) NSString* content;
@end

/// posted on the main thread when the macros change
extern NSNotificationName const VKMacroStoreDidChangeNotification;

@interface VKMacroStore : NSObject
+(NSArray<VKMacro*>*)allMacros;
+(NSInteger)count;
+(BOOL)hasMacro:(NSString*)text;
/// adds the macro, or changes the content of an existing one. NO if the text is longer than 255 bytes
/// or the content longer than 65535 bytes (the limits of the saved data)
+(BOOL)setMacro:(NSString*)text content:(NSString*)content;
+(void)deleteMacro:(NSString*)text;
/// keepCurrent: existing macros are not changed; otherwise the old macros are removed first
+(void)addMacros:(NSArray<VKMacro*>*)macros keepCurrent:(BOOL)keepCurrent NS_SWIFT_NAME(addMacros(_:keepCurrent:));
@end

typedef NS_ENUM(NSInteger, VKConvertOption) {
    VKConvertOptionAlertWhenCompleted,
    VKConvertOptionAllCaps,
    VKConvertOptionAllLower,
    VKConvertOptionCapsFirstLetter,
    VKConvertOptionCapsEachWord,
    VKConvertOptionRemoveMark,
};

/// options of the convert tool
@interface VKConvertTool : NSObject
+(BOOL)option:(VKConvertOption)option;
/// the four case options can not be on together, like in the old window
+(void)setOption:(VKConvertOption)option on:(BOOL)on;
@property (class, nonatomic) NSInteger fromCode;
@property (class, nonatomic) NSInteger toCode;
/// same bits as vSwitchKeyStatus, see Engine.h
@property (class, nonatomic) int hotKey;
@end

/// per-app memory of Vietnamese / English and the code table (smart switch, remember code table)
@interface VKAppMemory : NSObject
/// bundle id -> status (bit 0: Vietnamese, other bits: code table)
+(NSDictionary<NSString*, NSNumber*>*)allApps;
/// -1 if the app is not remembered
+(NSInteger)statusForApp:(NSString*)bundleId;
+(void)setStatus:(int)status forApp:(NSString*)bundleId;
+(void)removeApp:(NSString*)bundleId;
+(void)removeAllApps;
@end

/// apps where ViKey always types English
@interface VKExcludedApps : NSObject
@property (class, nonatomic, copy) NSArray<NSString*>* bundleIds;
@end

/// what the keyboard thread sees now, for the diagnostics window
@interface VKEngineStatus : NSObject
+(VKEngineStatus*)current;
/// the event tap exists
@property (nonatomic, readonly) BOOL tapRunning;
@property (nonatomic, readonly) BOOL tapEnabled;
/// times macOS turned the tap off
@property (nonatomic, readonly) NSInteger tapRestartCount;
/// keys and clicks handled since the tap started
@property (nonatomic, readonly) NSInteger eventCount;
@property (nonatomic, readonly) double averageEventMicroseconds;
@property (nonatomic, readonly) double maxEventMicroseconds;
/// last check of the typing app
@property (nonatomic, readonly) double detectMicroseconds;
/// how the typing app was found: 0 the frontmost app, 1 a focused panel over it (Accessibility), 2 the Spotlight window
@property (nonatomic, readonly) NSInteger detectMethod;
@property (nonatomic, readonly) BOOL accessibilityAnswered;
@property (nonatomic, readonly, copy) NSString* frontApp;
/// the app which receives the keys
@property (nonatomic, readonly, copy) NSString* typingApp;
@property (nonatomic, readonly) BOOL typingAppExcluded;
@property (nonatomic, readonly, copy) NSString* inputSource;
@property (nonatomic, readonly) BOOL englishInputSource;
@end

NS_ASSUME_NONNULL_END
