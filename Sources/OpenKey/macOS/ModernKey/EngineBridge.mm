//
//  EngineBridge.mm
//  ViKey
//
//  Objective-C API for the C++ engine, see EngineBridge.h
//

#import "EngineBridge.h"
#import "AppDelegate.h"
#include "Engine.h"

extern AppDelegate* appDelegate;

//defined in OpenKey.mm
extern "C" void saveSmartSwitchKeyData(void);
extern "C" void ReloadExcludedApps(void);

#define EXCLUDED_APPS_KEY @"ExcludedApps"

static NSString* toNSString(const string& str) {
    return [NSString stringWithUTF8String:str.c_str()] ?: @"";
}

#pragma mark - Macro

NSNotificationName const VKMacroStoreDidChangeNotification = @"VKMacroStoreDidChange";

@implementation VKMacro
-(instancetype)initWithText:(NSString*)text content:(NSString*)content {
    if (self = [super init]) {
        _text = [text copy];
        _content = [content copy];
    }
    return self;
}
@end

@implementation VKMacroStore
+(void)save {
    vector<Byte> macroData;
    {
        ENGINE_LOCK;
        getMacroSaveData(macroData);
    }
    [[NSUserDefaults standardUserDefaults] setObject:[NSData dataWithBytes:macroData.data() length:macroData.size()] forKey:@"macroData"];
    [[NSNotificationCenter defaultCenter] postNotificationName:VKMacroStoreDidChangeNotification object:nil];
}

+(NSArray<VKMacro*>*)allMacros {
    vector<vector<Uint32>> keys;
    vector<string> texts, contents;
    {
        ENGINE_LOCK;
        getAllMacro(keys, texts, contents);
    }
    NSMutableArray<VKMacro*>* result = [NSMutableArray arrayWithCapacity:texts.size()];
    for (size_t i = 0; i < texts.size(); i++) {
        [result addObject:[[VKMacro alloc] initWithText:toNSString(texts[i]) content:toNSString(contents[i])]];
    }
    return result;
}

+(NSInteger)count {
    vector<vector<Uint32>> keys;
    vector<string> texts, contents;
    ENGINE_LOCK;
    getAllMacro(keys, texts, contents);
    return (NSInteger)texts.size();
}

+(BOOL)hasMacro:(NSString*)text {
    ENGINE_LOCK;
    return hasMacro(string(text.UTF8String));
}

+(BOOL)setMacro:(NSString*)text content:(NSString*)content {
    BOOL added;
    {
        ENGINE_LOCK;
        added = addMacro(string(text.UTF8String), string(content.UTF8String));
    }
    if (added)
        [self save];
    return added;
}

+(void)deleteMacro:(NSString*)text {
    {
        ENGINE_LOCK;
        deleteMacro(string(text.UTF8String));
    }
    [self save];
}

+(void)addMacros:(NSArray<VKMacro*>*)macros keepCurrent:(BOOL)keepCurrent {
    {
        ENGINE_LOCK;
        if (!keepCurrent)
            initMacroMap(NULL, 0);
        for (VKMacro* macro in macros) {
            string text(macro.text.UTF8String);
            if (!text.empty() && !hasMacro(text))
                addMacro(text, string(macro.content.UTF8String));
        }
    }
    [self save];
}
@end

#pragma mark - Convert tool

@implementation VKConvertTool
+(BOOL)option:(VKConvertOption)option {
    switch (option) {
        case VKConvertOptionAlertWhenCompleted: return !convertToolDontAlertWhenCompleted;
        case VKConvertOptionAllCaps: return convertToolToAllCaps;
        case VKConvertOptionAllLower: return convertToolToAllNonCaps;
        case VKConvertOptionCapsFirstLetter: return convertToolToCapsFirstLetter;
        case VKConvertOptionCapsEachWord: return convertToolToCapsEachWord;
        case VKConvertOptionRemoveMark: return convertToolRemoveMark;
    }
    return NO;
}

+(void)setOption:(VKConvertOption)option on:(BOOL)on {
    NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
    switch (option) {
        case VKConvertOptionAlertWhenCompleted:
            convertToolDontAlertWhenCompleted = !on;
            //the key name is misleading, but kept for old settings: 1 means "show the alert"
            [defaults setInteger:on forKey:@"convertToolDontAlertWhenCompleted"];
            return;
        case VKConvertOptionRemoveMark:
            convertToolRemoveMark = on;
            [defaults setInteger:on forKey:@"convertToolRemoveMark"];
            return;
        default:
            break;
    }
    //case options: only one can be on
    convertToolToAllCaps = on && option == VKConvertOptionAllCaps;
    convertToolToAllNonCaps = on && option == VKConvertOptionAllLower;
    convertToolToCapsFirstLetter = on && option == VKConvertOptionCapsFirstLetter;
    convertToolToCapsEachWord = on && option == VKConvertOptionCapsEachWord;
    [defaults setInteger:convertToolToAllCaps forKey:@"convertToolToAllCaps"];
    [defaults setInteger:convertToolToAllNonCaps forKey:@"convertToolToAllNonCaps"];
    [defaults setInteger:convertToolToCapsFirstLetter forKey:@"convertToolToCapsFirstLetter"];
    [defaults setInteger:convertToolToCapsEachWord forKey:@"convertToolToCapsEachWord"];
}

+(NSInteger)fromCode {
    return convertToolFromCode;
}

+(void)setFromCode:(NSInteger)code {
    code = MIN(MAX(code, 0), 4);
    convertToolFromCode = (Uint8)code;
    [[NSUserDefaults standardUserDefaults] setInteger:code forKey:@"convertToolFromCode"];
}

+(NSInteger)toCode {
    return convertToolToCode;
}

+(void)setToCode:(NSInteger)code {
    code = MIN(MAX(code, 0), 4);
    convertToolToCode = (Uint8)code;
    [[NSUserDefaults standardUserDefaults] setInteger:code forKey:@"convertToolToCode"];
}

+(int)hotKey {
    return convertToolHotKey;
}

+(void)setHotKey:(int)hotKey {
    convertToolHotKey = hotKey;
    [[NSUserDefaults standardUserDefaults] setInteger:hotKey forKey:@"convertToolHotKey"];
    [appDelegate setQuickConvertString];
}
@end

#pragma mark - Per-app memory

@implementation VKAppMemory
+(NSDictionary<NSString*, NSNumber*>*)allApps {
    vector<string> bundleIds;
    vector<int> statuses;
    {
        ENGINE_LOCK;
        getAllAppInputMethodStatus(bundleIds, statuses);
    }
    NSMutableDictionary<NSString*, NSNumber*>* result = [NSMutableDictionary dictionaryWithCapacity:bundleIds.size()];
    for (size_t i = 0; i < bundleIds.size(); i++) {
        result[toNSString(bundleIds[i])] = @(statuses[i]);
    }
    return result;
}

+(NSInteger)statusForApp:(NSString*)bundleId {
    ENGINE_LOCK;
    return findAppInputMethodStatus(string(bundleId.UTF8String));
}

+(void)setStatus:(int)status forApp:(NSString*)bundleId {
    ENGINE_LOCK;
    setAppInputMethodStatus(string(bundleId.UTF8String), status);
    saveSmartSwitchKeyData();
}

+(void)removeApp:(NSString*)bundleId {
    ENGINE_LOCK;
    removeAppInputMethodStatus(string(bundleId.UTF8String));
    saveSmartSwitchKeyData();
}

+(void)removeAllApps {
    ENGINE_LOCK;
    vector<string> bundleIds;
    vector<int> statuses;
    getAllAppInputMethodStatus(bundleIds, statuses);
    for (const string& bundleId : bundleIds) {
        removeAppInputMethodStatus(bundleId);
    }
    saveSmartSwitchKeyData();
}
@end

#pragma mark - Excluded apps

@implementation VKExcludedApps
+(NSArray<NSString*>*)bundleIds {
    return [[NSUserDefaults standardUserDefaults] stringArrayForKey:EXCLUDED_APPS_KEY] ?: @[];
}

+(void)setBundleIds:(NSArray<NSString*>*)bundleIds {
    [[NSUserDefaults standardUserDefaults] setObject:bundleIds forKey:EXCLUDED_APPS_KEY];
    ReloadExcludedApps();
    [appDelegate updateStatusIcon];
}
@end
