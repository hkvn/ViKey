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
    getMacroSaveData(macroData);
    [[NSUserDefaults standardUserDefaults] setObject:[NSData dataWithBytes:macroData.data() length:macroData.size()] forKey:@"macroData"];
}

+(NSArray<VKMacro*>*)allMacros {
    vector<vector<Uint32>> keys;
    vector<string> texts, contents;
    getAllMacro(keys, texts, contents);
    NSMutableArray<VKMacro*>* result = [NSMutableArray arrayWithCapacity:texts.size()];
    for (size_t i = 0; i < texts.size(); i++) {
        [result addObject:[[VKMacro alloc] initWithText:toNSString(texts[i]) content:toNSString(contents[i])]];
    }
    return result;
}

+(BOOL)hasMacro:(NSString*)text {
    return hasMacro(string(text.UTF8String));
}

+(void)setMacro:(NSString*)text content:(NSString*)content {
    addMacro(string(text.UTF8String), string(content.UTF8String));
    [self save];
}

+(void)deleteMacro:(NSString*)text {
    deleteMacro(string(text.UTF8String));
    [self save];
}

+(void)importFromFile:(NSString*)path keepCurrent:(BOOL)keepCurrent {
    readFromFile(string(path.fileSystemRepresentation), keepCurrent);
    [self save];
}

+(void)exportToFile:(NSString*)path {
    saveToFile(string(path.fileSystemRepresentation));
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
    convertToolFromCode = (Uint8)code;
    [[NSUserDefaults standardUserDefaults] setInteger:code forKey:@"convertToolFromCode"];
}

+(NSInteger)toCode {
    return convertToolToCode;
}

+(void)setToCode:(NSInteger)code {
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
    getAllAppInputMethodStatus(bundleIds, statuses);
    NSMutableDictionary<NSString*, NSNumber*>* result = [NSMutableDictionary dictionaryWithCapacity:bundleIds.size()];
    for (size_t i = 0; i < bundleIds.size(); i++) {
        result[toNSString(bundleIds[i])] = @(statuses[i]);
    }
    return result;
}

+(void)setStatus:(int)status forApp:(NSString*)bundleId {
    setAppInputMethodStatus(string(bundleId.UTF8String), status);
    saveSmartSwitchKeyData();
}

+(void)removeApp:(NSString*)bundleId {
    removeAppInputMethodStatus(string(bundleId.UTF8String));
    saveSmartSwitchKeyData();
}

+(void)removeAllApps {
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
