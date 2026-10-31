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
@property (nonatomic, copy, readonly) NSString* text;
@property (nonatomic, copy, readonly) NSString* content;
@end

@interface VKMacroStore : NSObject
+(NSArray<VKMacro*>*)allMacros;
+(BOOL)hasMacro:(NSString*)text;
/// adds the macro, or changes the content of an existing one
+(void)setMacro:(NSString*)text content:(NSString*)content;
+(void)deleteMacro:(NSString*)text;
+(void)importFromFile:(NSString*)path keepCurrent:(BOOL)keepCurrent;
+(void)exportToFile:(NSString*)path;
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
+(void)setStatus:(int)status forApp:(NSString*)bundleId;
+(void)removeApp:(NSString*)bundleId;
+(void)removeAllApps;
@end

/// apps where ViKey always types English
@interface VKExcludedApps : NSObject
@property (class, nonatomic, copy) NSArray<NSString*>* bundleIds;
@end

NS_ASSUME_NONNULL_END
