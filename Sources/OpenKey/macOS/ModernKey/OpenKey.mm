//
//  OpenKey.m
//  OpenKey
//
//  Created by Tuyen on 1/18/19.
//  Copyright © 2019 Tuyen Mai. All rights reserved.
//
#import <Cocoa/Cocoa.h>
#import <Carbon/Carbon.h>
#import <Foundation/Foundation.h>
#include <atomic>
#include <mach/mach_time.h>
#import "Engine.h"
#import "AppDelegate.h"
#import "OpenKeyManager.h"
#import "EngineBridge.h"
#import "Logging.h"

#define OTHER_CONTROL_KEY (_flag & kCGEventFlagMaskCommand) || (_flag & kCGEventFlagMaskControl) || \
                            (_flag & kCGEventFlagMaskAlternate) || (_flag & kCGEventFlagMaskSecondaryFn) || \
                            (_flag & kCGEventFlagMaskNumericPad) || (_flag & kCGEventFlagMaskHelp)

#define DYNA_DATA(macro, pos) (macro ? pData->macroData[pos] : pData->charData[pos])
#define MAX_UNICODE_STRING  20
#define EMPTY_HOTKEY 0xFE0000FE
#define LOAD_DATA(VAR, KEY) VAR = (int)[[NSUserDefaults standardUserDefaults] integerForKey:@#KEY]
#define TARGET_APP_MAX_AGE 0.5 //seconds, see getTargetApp()
#define TARGET_APP_CHECK_DELAY 0.3 //seconds, see CheckTypingAppSoon()
#define AX_TIMEOUT 0.05 //seconds, see FocusedApp()
#define SLOW_EVENT_LOG 20000 //microseconds: handling one event slower than this is logged
#define MAX_CLIPBOARD_MACRO 2000 //characters of {clipboard} in a macro
#define VIKEY_INPUT_METHOD @"com.hkvn.inputmethod.ViKey" //InputMethodKit version of ViKey, see Sources/OpenKey/macOS/InputMethod

// Ignore code for Modifier keys and numpad
// Reference: https://eastmanreference.com/complete-list-of-applescript-key-codes
NSDictionary *keyStringToKeyCodeMap = @{
    // Characters from number row
    @"`": @50, @"~": @50, @"1": @18, @"!": @18, @"2": @19, @"@": @19, @"3": @20, @"#": @20, @"4": @21, @"$": @21,
    @"5": @23, @"%": @23, @"6": @22, @"^": @22, @"7": @26, @"&": @26, @"8": @28, @"*": @28, @"9": @25, @"(": @25,
    @"0": @29, @")": @29, @"-": @27, @"_": @27, @"=": @24, @"+": @24,
    // Characters from first keyboard row
    @"q": @12, @"w": @13, @"e": @14, @"r": @15, @"t": @17, @"y": @16, @"u": @32, @"i": @34, @"o": @31, @"p": @35,
    @"[": @33, @"{": @33, @"]": @30, @"}": @30, @"\\": @42, @"|": @42,
    // Characters from second keyboard row
    @"a": @0, @"s": @1, @"d": @2, @"f": @3, @"g": @5, @"h": @4, @"j": @38, @"k": @40, @"l": @37,
    @";": @41, @":": @41, @"'": @39, @"\"": @39,
    // Characters from second third row
    @"z": @6, @"x": @7, @"c": @8, @"v": @9, @"b": @11, @"n": @45, @"m": @46,
    @",": @43, @"<": @43, @".": @47, @">": @47, @"/": @44, @"?": @44
};

extern AppDelegate* appDelegate;
extern int vSendKeyStepByStep;
extern int vFixChromiumBrowser;
extern int vPerformLayoutCompat;

//The keys are handled on a thread of their own (see OpenKeyManager), the app changes settings and engine data on the
//main thread: the variables below and the engine are used only while holding the engine lock (see ENGINE_LOCK).
//The keyboard thread never waits for the main thread, so the main thread can hold the lock without a deadlock.
extern "C" {
    //app which must sent special empty character
    NSArray* _niceSpaceApp = @[@"com.sublimetext.3",
                               @"com.sublimetext.2",
                             ];
    
    //app which error with unicode Compound
    NSArray* _unicodeCompoundApp = @[@"com.apple.",
                                     @"com.google.Chrome", @"com.brave.Browser",
                                     @"com.microsoft.edgemac.Dev", @"com.microsoft.edgemac.Beta", @"com.microsoft.Edge.Dev", @"com.microsoft.Edge"];
    NSArray* _recommendWorkaroundDisabledApp = @[@"com.apple.Spotlight"];
    
    CGEventSourceRef myEventSource = NULL;
    vKeyHookState* pData;
    CGEventRef eventBackSpaceDown;
    CGEventRef eventBackSpaceUp;
    UniChar _newChar, _newCharHi;
    CGEventRef _newEventDown, _newEventUp;
    CGKeyCode _keycode;
    CGEventFlags _flag, _lastFlag = 0, _privateFlag;
    CGEventTapProxy _proxy;
    
    Uint16 _newCharString[MAX_UNICODE_STRING];
    Uint16 _newCharSize;
    bool _willContinuteSending = false;
    bool _willSendControlKey = false;
    
    vector<Uint16> _syncKey;
    
    Uint16 _uniChar[2];
    int _i, _j, _k;
    Uint32 _tempChar;
    bool _hasJustUsedHotKey = false;

    int _languageTemp = 0; //use for smart switch key
    vector<Byte> savedSmartSwitchKeyData; ////use for smart switch key
    
    bool _inited = false; //OpenKeyInit() has loaded the settings and the engine data
    
    NSString* _frontApp = @""; //frontmost app, see OnFrontAppChanged()
    pid_t _frontPid = 0;
    NSString* _targetApp = nil; //app which receives the keys, nil when it must be checked again, see getTargetApp()
    CFAbsoluteTime _targetAppTime = 0;
    NSString* _typingApp = @""; //last value of _targetApp
    NSString* _memoryApp = @""; //last typing app which is not ViKey: smart switch remembers the mode for it
    bool _checkTypingAppPending = false;
    
    //see FocusedApp()
    AXUIElementRef _systemWide = NULL;
    pid_t _focusedPid = 0;
    NSString* _focusedApp = nil;
    bool _accessibilityAnswered = true;
    
    //for the diagnostics window
    NSInteger _detectMethod = 0; //see VKEngineStatus.detectMethod
    double _detectTime = 0; //microseconds
    uint64_t _eventCount = 0, _eventTotalTime = 0, _eventMaxTime = 0; //mach time units
    std::atomic<int> _tapRestartCount(0);
    mach_timebase_info_data_t _timebase;
    
    //see UpdateInputSourceLanguage()
    bool _isEnglishInputSource = true;
    bool _isViKeyInputMethod = false; //the ViKey input method types: the event tap does nothing
    NSString* _inputSource = @"";
    CFDataRef _keyboardLayout = NULL; //'uchr' data of the keyboard layout, see ConvertEventToKeyboadLayoutCompatKeyCode()
    UInt32 _keyboardType = 0;
    
    void EngineLock() {
        engineMutex().lock();
    }
    
    void EngineUnlock() {
        engineMutex().unlock();
    }
    
    double MachToMicroseconds(uint64_t time) {
        if (_timebase.denom == 0)
            mach_timebase_info(&_timebase);
        return (double)time * _timebase.numer / _timebase.denom / 1000.0;
    }
    
    //for "turn off Vietnamese when in other language" and "Telex on other layouts". Asking macOS on every key is slow
    //(about 28 µs) and must happen on the main thread, so this is updated only when the keyboard input source changes
    void UpdateInputSourceLanguage() {
        bool isEnglish = true;
        NSString* inputSource = @"";
        TISInputSourceRef isource = TISCopyCurrentKeyboardInputSource();
        if (isource != NULL) {
            //languages is owned by isource: read it before releasing isource
            CFArrayRef languages = (CFArrayRef) TISGetInputSourceProperty(isource, kTISPropertyInputSourceLanguages);
            if (languages != NULL && CFArrayGetCount(languages) > 0) {
                NSString *currentLanguage = (__bridge NSString *)CFArrayGetValueAtIndex(languages, 0);
                isEnglish = [currentLanguage isLike:@"en"];
            }
            NSString* sourceId = (__bridge NSString *)TISGetInputSourceProperty(isource, kTISPropertyInputSourceID);
            inputSource = [sourceId copy] ?: @"";
            CFRelease(isource);
        }
        CFDataRef keyboardLayout = NULL;
        TISInputSourceRef layout = TISCopyCurrentKeyboardLayoutInputSource();
        if (layout != NULL) {
            CFDataRef data = (CFDataRef) TISGetInputSourceProperty(layout, kTISPropertyUnicodeKeyLayoutData);
            if (data != NULL)
                keyboardLayout = CFDataCreateCopy(kCFAllocatorDefault, data);
            CFRelease(layout);
        }
        
        ENGINE_LOCK;
        if (![inputSource isEqualToString:_inputSource])
            VKLog(@"keyboard", @"input source: %@", inputSource);
        _isEnglishInputSource = isEnglish;
        _isViKeyInputMethod = [inputSource hasPrefix:VIKEY_INPUT_METHOD];
        _inputSource = inputSource;
        if (_keyboardLayout != NULL)
            CFRelease(_keyboardLayout);
        _keyboardLayout = keyboardLayout;
        _keyboardType = LMGetKbdType();
    }
    
    static void OnInputSourceChanged(CFNotificationCenterRef center, void *observer, CFNotificationName name,
                                     const void *object, CFDictionaryRef userInfo) {
        UpdateInputSourceLanguage();
    }
    
    //apps where ViKey always types English (Terminal, games,...), see VKExcludedApps
    NSSet<NSString*>* _excludedApps = nil;
    bool _isExcludedAppActive = false;
    
    void ReloadExcludedApps() {
        NSSet<NSString*>* excludedApps = [NSSet setWithArray:[[NSUserDefaults standardUserDefaults] stringArrayForKey:@"ExcludedApps"] ?: @[]];
        ENGINE_LOCK;
        _excludedApps = excludedApps;
        _isExcludedAppActive = [_excludedApps containsObject:_typingApp];
    }
    
    bool IsExcludedAppActive() {
        return _isExcludedAppActive;
    }
    
    //for {clipboard} in macros
    static string ReadClipboardText() {
        NSString* text = [[NSPasteboard generalPasteboard] stringForType:NSPasteboardTypeString] ?: @"";
        if (text.length > MAX_CLIPBOARD_MACRO)
            text = [text substringWithRange:[text rangeOfComposedCharacterSequencesForRange:NSMakeRange(0, MAX_CLIPBOARD_MACRO)]];
        return string(text.UTF8String ?: "");
    }
    
    void UpdateFrontApp() {
        NSRunningApplication* front = [[NSWorkspace sharedWorkspace] frontmostApplication];
        NSString* app = front.bundleIdentifier ?: (front.localizedName ?: @"");
        ENGINE_LOCK;
        _frontApp = app;
        _frontPid = front.processIdentifier;
    }
    
    void OpenKeyInit() {
        ENGINE_LOCK;
        //load saved data
        vFreeMark = 0;//(int)[[NSUserDefaults standardUserDefaults] integerForKey:@"FreeMark"];
        LOAD_DATA(vCodeTable, CodeTable); if (vCodeTable < 0) vCodeTable = 0;
        LOAD_DATA(vCheckSpelling, Spelling);
        LOAD_DATA(vQuickTelex, QuickTelex);
        LOAD_DATA(vUseModernOrthography, ModernOrthography);
        LOAD_DATA(vRestoreIfWrongSpelling, RestoreIfInvalidWord);
        LOAD_DATA(vFixRecommendBrowser, FixRecommendBrowser);
        LOAD_DATA(vUseMacro, UseMacro);
        LOAD_DATA(vUseMacroInEnglishMode, UseMacroInEnglishMode);
        LOAD_DATA(vAutoCapsMacro, vAutoCapsMacro);
        LOAD_DATA(vSendKeyStepByStep, SendKeyStepByStep);
        LOAD_DATA(vUseSmartSwitchKey, UseSmartSwitchKey);
        LOAD_DATA(vUpperCaseFirstChar, UpperCaseFirstChar);
        
        LOAD_DATA(vTempOffSpelling, vTempOffSpelling);
        LOAD_DATA(vAllowConsonantZFWJ, vAllowConsonantZFWJ);
        LOAD_DATA(vQuickEndConsonant, vQuickEndConsonant);
        LOAD_DATA(vQuickStartConsonant, vQuickStartConsonant);
        LOAD_DATA(vRememberCode, vRememberCode);
        LOAD_DATA(vOtherLanguage, vOtherLanguage);
        LOAD_DATA(vTempOffOpenKey, vTempOffOpenKey);
        
        LOAD_DATA(vFixChromiumBrowser, vFixChromiumBrowser);
        
        LOAD_DATA(vPerformLayoutCompat, vPerformLayoutCompat);
        
        //create them once: OpenKeyInit runs again after the Mac wakes up
        if (myEventSource == NULL) {
            myEventSource = CGEventSourceCreate(kCGEventSourceStatePrivate);
            eventBackSpaceDown = CGEventCreateKeyboardEvent (myEventSource, 51, true);
            eventBackSpaceUp = CGEventCreateKeyboardEvent (myEventSource, 51, false);
        }
        pData = (vKeyHookState*)vKeyInit();
        
        //init and load macro data
        NSUserDefaults *prefs = [NSUserDefaults standardUserDefaults];
        NSData *data = [prefs objectForKey:@"macroData"];
        initMacroMap((Byte*)data.bytes, (int)data.length);
        macroClipboardText = ReadClipboardText;
        
        //init and load smart switch key data
        data = [prefs objectForKey:@"smartSwitchKey"];
        initSmartSwitchKey((Byte*)data.bytes, (int)data.length);
        
        //init convert tool
        convertToolDontAlertWhenCompleted = ![prefs boolForKey:@"convertToolDontAlertWhenCompleted"];
        convertToolToAllCaps = [prefs boolForKey:@"convertToolToAllCaps"];
        convertToolToAllNonCaps = [prefs boolForKey:@"convertToolToAllNonCaps"];
        convertToolToCapsFirstLetter = [prefs boolForKey:@"convertToolToCapsFirstLetter"];
        convertToolToCapsEachWord = [prefs boolForKey:@"convertToolToCapsEachWord"];
        convertToolRemoveMark = [prefs boolForKey:@"convertToolRemoveMark"];
        convertToolFromCode = [prefs integerForKey:@"convertToolFromCode"];
        convertToolToCode = [prefs integerForKey:@"convertToolToCode"];
        convertToolHotKey = (int)[prefs integerForKey:@"convertToolHotKey"];
        if (convertToolHotKey == 0) {
            convertToolHotKey = EMPTY_HOTKEY;
        }
        
        //OpenKeyInit runs again after the Mac wakes up: add the observer only once.
        //Deliver immediately: ViKey is a menu bar app, so it is almost never the active app
        static bool observingInputSource = false;
        if (!observingInputSource) {
            observingInputSource = true;
            CFNotificationCenterAddObserver(CFNotificationCenterGetDistributedCenter(), NULL, OnInputSourceChanged,
                                            kTISNotifySelectedKeyboardInputSourceChanged, NULL,
                                            CFNotificationSuspensionBehaviorDeliverImmediately);
        }
        UpdateInputSourceLanguage();
        ReloadExcludedApps();
        UpdateFrontApp();
        //the first key checks the typing app, which also applies its remembered mode
        _targetApp = nil;
        _typingApp = @"";
        _inited = true;
    }
    
    //the focus may be in another app or panel now: check the target app again
    void InvalidateTargetApp() {
        ENGINE_LOCK;
        _targetApp = nil;
    }
    
    void RequestNewSession() {
        ENGINE_LOCK;
        if (!_inited)
            return;
        //send event signal to Engine
        vKeyHandleEvent(vKeyEvent::Mouse, vKeyEventState::MouseDown, 0);
        InvalidateTargetApp();
        
        if (IS_DOUBLE_CODE(vCodeTable)) { //VNI
            _syncKey.clear();
        }
    }
    
    NSString* ConvertUtil(NSString* str) {
        return [NSString stringWithUTF8String:convertUtil([str UTF8String]).c_str()];
    }
    
    BOOL containUnicodeCompoundApp(NSString* topApp) {
        if (topApp == nil) return false;
        for (_j = 0; _j < [_unicodeCompoundApp count]; _j++) {
            if ([topApp hasPrefix:[_unicodeCompoundApp objectAtIndex:_j]] || [[_unicodeCompoundApp objectAtIndex:_j] isEqualToString:topApp])
                return true;
        }
        return false;
    }

    BOOL isSpotlightVisible() {
        NSArray *windows = CFBridgingRelease(CGWindowListCopyWindowInfo(kCGWindowListOptionOnScreenOnly | kCGWindowListExcludeDesktopElements,
                                                                        kCGNullWindowID));
        for (NSDictionary *window in windows) {
            if (![[window objectForKey:(__bridge NSString *)kCGWindowOwnerName] isEqualToString:@"Spotlight"])
                continue;
            //skip Spotlight's menu bar icon, only the search panel counts
            CGRect bounds;
            if (!CGRectMakeWithDictionaryRepresentation((__bridge CFDictionaryRef)[window objectForKey:(__bridge NSString *)kCGWindowBounds], &bounds) ||
                bounds.size.width < 100)
                continue;
            NSNumber* alpha = [window objectForKey:(__bridge NSString *)kCGWindowAlpha];
            if (alpha != nil && alpha.doubleValue <= 0)
                continue;
            return true;
        }
        return false;
    }

    //bundle id of the app with the keyboard focus, nil if Accessibility does not answer. Panels such as Spotlight,
    //Alfred, Raycast or the emoji picker take the keys without becoming the frontmost app
    NSString* FocusedApp() {
        if (_systemWide == NULL) {
            _systemWide = AXUIElementCreateSystemWide();
            //an app which does not respond must not stop typing
            AXUIElementSetMessagingTimeout(_systemWide, AX_TIMEOUT);
        }
        CFTypeRef app = NULL;
        pid_t pid = 0;
        _accessibilityAnswered = AXUIElementCopyAttributeValue(_systemWide, kAXFocusedApplicationAttribute, &app) == kAXErrorSuccess && app != NULL;
        if (!_accessibilityAnswered)
            return nil;
        AXUIElementGetPid((AXUIElementRef)app, &pid);
        CFRelease(app);
        if (pid <= 0)
            return nil;
        if (pid == _frontPid)
            return _frontApp;
        //asking for the bundle id is slow (about 50 µs): remember the last answer
        if (pid != _focusedPid) {
            NSRunningApplication* focused = [NSRunningApplication runningApplicationWithProcessIdentifier:pid];
            _focusedPid = pid;
            _focusedApp = focused.bundleIdentifier ?: focused.localizedName;
        }
        return _focusedApp;
    }
    
    NSString* DetectTargetApp() {
        uint64_t start = mach_absolute_time();
        NSString* app = FocusedApp();
        if (app != nil && ![app isEqualToString:_frontApp]) {
            _detectMethod = 1;
        } else if (isSpotlightVisible()) { //in case Accessibility does not see the Spotlight panel
            app = @"com.apple.Spotlight";
            _detectMethod = 2;
        } else {
            app = _frontApp;
            _detectMethod = 0;
        }
        _detectTime = MachToMicroseconds(mach_absolute_time() - start);
        return app ?: @"";
    }
    
    void saveSmartSwitchKeyData() {
        ENGINE_LOCK;
        getSmartSwitchKeySaveData(savedSmartSwitchKeyData);
        NSData* _data = [NSData dataWithBytes:savedSmartSwitchKeyData.data() length:savedSmartSwitchKeyData.size()];
        NSUserDefaults *prefs = [NSUserDefaults standardUserDefaults];
        [prefs setObject:_data forKey:@"smartSwitchKey"];
    }
    
    //the engine changed the mode itself: save it now, so the settings never show an old mode, then refresh the menu
    void SaveModeAndRefreshMenu() {
        [[NSUserDefaults standardUserDefaults] setInteger:vLanguage forKey:@"InputMethod"];
        [[NSUserDefaults standardUserDefaults] setInteger:vCodeTable forKey:@"CodeTable"];
        dispatch_async(dispatch_get_main_queue(), ^{
            [appDelegate fillData];
        });
    }
    
    //per-app memory: the app keeps the current mode
    void RememberAppMode() {
        if (_memoryApp.length == 0)
            return;
        setAppInputMethodStatus(string(_memoryApp.UTF8String), vLanguage | (vCodeTable << 1));
        saveSmartSwitchKeyData();
    }
    
    //the keys go to another app or panel now: apply its remembered mode (smart switch).
    //addNewApp: remember the mode for an app seen the first time; not after a click, which also opens menu bar items
    void OnTypingAppChanged(NSString* app, bool addNewApp) {
        VKLog(@"app", @"typing in %@%@", app, _detectMethod == 1 ? @" (focused panel)" : (_detectMethod == 2 ? @" (Spotlight window)" : @""));
        _typingApp = app;
        _isExcludedAppActive = [_excludedApps containsObject:app];
        if (app.length > 0 && ![app isEqualToString:OPENKEY_BUNDLE]) {
            _memoryApp = app;
            if (vUseSmartSwitchKey) {
                _languageTemp = addNewApp ? getAppInputMethodStatus(string(app.UTF8String), vLanguage | (vCodeTable << 1))
                                          : findAppInputMethodStatus(string(app.UTF8String));
                if (_languageTemp == -1) { //new app: it keeps the current mode
                    if (addNewApp)
                        saveSmartSwitchKeyData();
                } else {
                    bool changed = false;
                    if ((_languageTemp & 0x01) != vLanguage) {
                        vLanguage = _languageTemp & 0x01;
                        changed = true;
                    }
                    if (vRememberCode && (_languageTemp >> 1) != vCodeTable) { //for remember table code feature
                        vCodeTable = _languageTemp >> 1;
                        onTableCodeChange();
                        changed = true;
                    }
                    if (changed) {
                        VKLog(@"app", @"remembered mode: %@, code table %d", vLanguage ? @"Vietnamese" : @"English", vCodeTable);
                        startNewSession();
                        _syncKey.clear();
                        SaveModeAndRefreshMenu();
                    }
                }
            }
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            [appDelegate updateStatusIcon];
        });
    }
    
    //Panels such as Spotlight take keys but they are never the frontmost app. Checking it is slow (about 0.4 ms),
    //so check again only after something which can move the focus (see InvalidateTargetApp), or when the answer is old
    NSString* getTargetApp(bool addNewApp=true) {
        CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
        if (_targetApp == nil || now - _targetAppTime > TARGET_APP_MAX_AGE) {
            _targetApp = DetectTargetApp();
            _targetAppTime = now;
            if (![_targetApp isEqualToString:_typingApp])
                OnTypingAppChanged(_targetApp, addNewApp);
        }
        return _targetApp;
    }
    
    //the focus may move after this event (Spotlight opens, a panel closes,...): check the app again soon,
    //so the menu bar icon and the remembered mode follow it before the next key
    void CheckTypingAppSoon() {
        if (_checkTypingAppPending)
            return;
        _checkTypingAppPending = true;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(TARGET_APP_CHECK_DELAY * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            ENGINE_LOCK;
            _checkTypingAppPending = false;
            if (!_inited)
                return;
            _targetApp = nil;
            getTargetApp(false);
        });
    }
    
    //call on the main thread when the frontmost app changes
    void OnFrontAppChanged() {
        UpdateFrontApp();
        ENGINE_LOCK;
        if (!_inited)
            return;
        //the menu bar icon and the remembered mode follow the new app at once
        _targetApp = nil;
        getTargetApp();
    }

    BOOL shouldUseRecommendWorkaround() {
        return vFixRecommendBrowser && ![_recommendWorkaroundDisabledApp containsObject:getTargetApp()];
    }

    BOOL shouldUseSelectionReplacement() {
        return [_recommendWorkaroundDisabledApp containsObject:getTargetApp()];
    }
    
    void OnTableCodeChange() {
        ENGINE_LOCK;
        onTableCodeChange();
        if (vRememberCode) {
            RememberAppMode();
        }
    }
    
    void OnInputMethodChanged() {
        ENGINE_LOCK;
        if (vUseSmartSwitchKey) {
            RememberAppMode();
        }
    }
    
    void OnSpellCheckingChanged() {
        ENGINE_LOCK;
        vSetCheckSpelling();
    }
    
    void InsertKeyLength(const Uint8& len) {
        _syncKey.push_back(len);
    }
    
    void SendPureCharacter(const Uint16& ch) {
        _newEventDown = CGEventCreateKeyboardEvent(myEventSource, 0, true);
        _newEventUp = CGEventCreateKeyboardEvent(myEventSource, 0, false);
        CGEventKeyboardSetUnicodeString(_newEventDown, 1, &ch);
        CGEventKeyboardSetUnicodeString(_newEventUp, 1, &ch);
        CGEventTapPostEvent(_proxy, _newEventDown);
        CGEventTapPostEvent(_proxy, _newEventUp);
        CFRelease(_newEventDown);
        CFRelease(_newEventUp);
        if (IS_DOUBLE_CODE(vCodeTable)) {
            InsertKeyLength(1);
        }
    }
    
    void SendKeyCode(Uint32 data) {
        _newChar = (Uint16)data;
        if (!(data & CHAR_CODE_MASK)) {
            if (IS_DOUBLE_CODE(vCodeTable)) //VNI
                InsertKeyLength(1);
            
            _newEventDown = CGEventCreateKeyboardEvent(myEventSource, _newChar, true);
            _newEventUp = CGEventCreateKeyboardEvent(myEventSource, _newChar, false);
            _privateFlag = CGEventGetFlags(_newEventDown);
            
            if (data & CAPS_MASK) {
                _privateFlag |= kCGEventFlagMaskShift;
            } else {
                _privateFlag &= ~kCGEventFlagMaskShift;
            }
            _privateFlag |= kCGEventFlagMaskNonCoalesced;
            
            CGEventSetFlags(_newEventDown, _privateFlag);
            CGEventSetFlags(_newEventUp, _privateFlag);
            CGEventTapPostEvent(_proxy, _newEventDown);
            CGEventTapPostEvent(_proxy, _newEventUp);
        } else {
            if (vCodeTable == 0) { //unicode 2 bytes code
                _newEventDown = CGEventCreateKeyboardEvent(myEventSource, 0, true);
                _newEventUp = CGEventCreateKeyboardEvent(myEventSource, 0, false);
                CGEventKeyboardSetUnicodeString(_newEventDown, 1, &_newChar);
                CGEventKeyboardSetUnicodeString(_newEventUp, 1, &_newChar);
                CGEventTapPostEvent(_proxy, _newEventDown);
                CGEventTapPostEvent(_proxy, _newEventUp);
            } else if (vCodeTable == 1 || vCodeTable == 2 || vCodeTable == 4) { //others such as VNI Windows, TCVN3: 1 byte code
                _newCharHi = HIBYTE(_newChar);
                _newChar = LOBYTE(_newChar);
                
                _newEventDown = CGEventCreateKeyboardEvent(myEventSource, 0, true);
                _newEventUp = CGEventCreateKeyboardEvent(myEventSource, 0, false);
                CGEventKeyboardSetUnicodeString(_newEventDown, 1, &_newChar);
                CGEventKeyboardSetUnicodeString(_newEventUp, 1, &_newChar);
                CGEventTapPostEvent(_proxy, _newEventDown);
                CGEventTapPostEvent(_proxy, _newEventUp);
                if (_newCharHi > 32) {
                    if (vCodeTable == 2) //VNI
                        InsertKeyLength(2);
                    CFRelease(_newEventDown);
                    CFRelease(_newEventUp);
                    _newEventDown = CGEventCreateKeyboardEvent(myEventSource, 0, true);
                    _newEventUp = CGEventCreateKeyboardEvent(myEventSource, 0, false);
                    CGEventKeyboardSetUnicodeString(_newEventDown, 1, &_newCharHi);
                    CGEventKeyboardSetUnicodeString(_newEventUp, 1, &_newCharHi);
                    CGEventTapPostEvent(_proxy, _newEventDown);
                    CGEventTapPostEvent(_proxy, _newEventUp);
                } else {
                    if (vCodeTable == 2) //VNI
                        InsertKeyLength(1);
                }
            } else if (vCodeTable == 3) { //Unicode Compound
                _newCharHi = (_newChar >> 13);
                _newChar &= 0x1FFF;
                _uniChar[0] = _newChar;
                _uniChar[1] = _newCharHi > 0 ? (_unicodeCompoundMark[_newCharHi - 1]) : 0;
                InsertKeyLength(_newCharHi > 0 ? 2 : 1);
                _newEventDown = CGEventCreateKeyboardEvent(myEventSource, 0, true);
                _newEventUp = CGEventCreateKeyboardEvent(myEventSource, 0, false);
                CGEventKeyboardSetUnicodeString(_newEventDown, (_newCharHi > 0 ? 2 : 1), _uniChar);
                CGEventKeyboardSetUnicodeString(_newEventUp, (_newCharHi > 0 ? 2 : 1), _uniChar);
                CGEventTapPostEvent(_proxy, _newEventDown);
                CGEventTapPostEvent(_proxy, _newEventUp);
            }
        }
        CFRelease(_newEventDown);
        CFRelease(_newEventUp);
    }
    
    void SendEmptyCharacter() {
        if (IS_DOUBLE_CODE(vCodeTable)) //VNI or Unicode Compound
            InsertKeyLength(1);
        
        _newChar = 0x202F; //empty char
        if ([_niceSpaceApp containsObject:getTargetApp()]) {
            _newChar = 0x200C; //Unicode character with empty space
        }
        
        _newEventDown = CGEventCreateKeyboardEvent(myEventSource, 0, true);
        _newEventUp = CGEventCreateKeyboardEvent(myEventSource, 0, false);
        CGEventKeyboardSetUnicodeString(_newEventDown, 1, &_newChar);
        CGEventKeyboardSetUnicodeString(_newEventUp, 1, &_newChar);
        CGEventTapPostEvent(_proxy, _newEventDown);
        CGEventTapPostEvent(_proxy, _newEventUp);
        CFRelease(_newEventDown);
        CFRelease(_newEventUp);
    }
    
    void SendVirtualKey(const Byte& vKey) {
        CGEventRef eventVkeyDown = CGEventCreateKeyboardEvent (myEventSource, vKey, true);
        CGEventRef eventVkeyUp = CGEventCreateKeyboardEvent (myEventSource, vKey, false);
        
        CGEventTapPostEvent(_proxy, eventVkeyDown);
        CGEventTapPostEvent(_proxy, eventVkeyUp);
        
        CFRelease(eventVkeyDown);
        CFRelease(eventVkeyUp);
    }

    void SendBackspace() {
        CGEventTapPostEvent(_proxy, eventBackSpaceDown);
        CGEventTapPostEvent(_proxy, eventBackSpaceUp);
        
        if (IS_DOUBLE_CODE(vCodeTable)) { //VNI or Unicode Compound
            if (_syncKey.back() > 1) {
                if (!(vCodeTable == 3 && containUnicodeCompoundApp(getTargetApp()))) {
                    CGEventTapPostEvent(_proxy, eventBackSpaceDown);
                    CGEventTapPostEvent(_proxy, eventBackSpaceUp);
                }
            }
            _syncKey.pop_back();
        }
    }
    
    void SendShiftAndLeftArrow() {
        CGEventRef eventVkeyDown = CGEventCreateKeyboardEvent (myEventSource, KEY_LEFT, true);
        CGEventRef eventVkeyUp = CGEventCreateKeyboardEvent (myEventSource, KEY_LEFT, false);
        _privateFlag = CGEventGetFlags(eventVkeyDown);
        _privateFlag |= kCGEventFlagMaskShift;
        CGEventSetFlags(eventVkeyDown, _privateFlag);
        CGEventSetFlags(eventVkeyUp, _privateFlag);
        
        CGEventTapPostEvent(_proxy, eventVkeyDown);
        CGEventTapPostEvent(_proxy, eventVkeyUp);
        
        if (IS_DOUBLE_CODE(vCodeTable)) { //VNI or Unicode Compound
            if (_syncKey.back() > 1) {
                if (!(vCodeTable == 3 && containUnicodeCompoundApp(getTargetApp()))) {
                    CGEventTapPostEvent(_proxy, eventVkeyDown);
                    CGEventTapPostEvent(_proxy, eventVkeyUp);
                }
            }
            _syncKey.pop_back();
        }
        CFRelease(eventVkeyDown);
        CFRelease(eventVkeyUp);
    }
    
    //delete chars before cursor. In apps where backspace breaks (Spotlight), select them instead: new chars replace the selection
    void SendDeleteKeys(const int& count) {
        bool useSelection = shouldUseSelectionReplacement();
        for (int i = 0; i < count; i++) {
            if (useSelection)
                SendShiftAndLeftArrow();
            else
                SendBackspace();
        }
    }
    
    void SendCutKey() {
        CGEventRef eventVkeyDown = CGEventCreateKeyboardEvent (myEventSource, KEY_X, true);
        CGEventRef eventVkeyUp = CGEventCreateKeyboardEvent (myEventSource, KEY_X, false);
        _privateFlag = CGEventGetFlags(eventVkeyDown);
        _privateFlag |= NX_COMMANDMASK;
        CGEventSetFlags(eventVkeyDown, _privateFlag);
        CGEventSetFlags(eventVkeyUp, _privateFlag);
        
        CGEventTapPostEvent(_proxy, eventVkeyDown);
        CGEventTapPostEvent(_proxy, eventVkeyUp);
        
        CFRelease(eventVkeyDown);
        CFRelease(eventVkeyUp);
    }
    
    void SendNewCharString(const bool& dataFromMacro=false, const Uint16& offset=0) {
        _j = 0;
        _newCharSize = dataFromMacro ? pData->macroData.size() : pData->newCharCount;
        _willContinuteSending = false;
        _willSendControlKey = false;
        
        if (_newCharSize > 0) {
            for (_k = dataFromMacro ? offset : pData->newCharCount - 1 - offset;
                 dataFromMacro ? _k < pData->macroData.size() : _k >= 0;
                 dataFromMacro ? _k++ : _k--) {
                
                if (_j >= 16) {
                    _willContinuteSending = true;
                    break;
                }
                
                _tempChar = DYNA_DATA(dataFromMacro, _k);
                if (_tempChar & PURE_CHARACTER_MASK) {
                    _newCharString[_j++] = _tempChar;
                    if (IS_DOUBLE_CODE(vCodeTable)) {
                        InsertKeyLength(1);
                    }
                } else if (!(_tempChar & CHAR_CODE_MASK)) {
                    if (IS_DOUBLE_CODE(vCodeTable)) //VNI
                        InsertKeyLength(1);
                    _newCharString[_j++] = keyCodeToCharacter(_tempChar);
                } else {
                    if (vCodeTable == 0) {  //unicode 2 bytes code
                        _newCharString[_j++] = _tempChar;
                    } else if (vCodeTable == 1 || vCodeTable == 2 || vCodeTable == 4) { //others such as VNI Windows, TCVN3: 1 byte code
                        _newChar = _tempChar;
                        _newCharHi = HIBYTE(_newChar);
                        _newChar = LOBYTE(_newChar);
                        _newCharString[_j++] = _newChar;
                        
                        if (_newCharHi > 32) {
                            if (vCodeTable == 2) //VNI
                                InsertKeyLength(2);
                            _newCharString[_j++] = _newCharHi;
                            _newCharSize++;
                        } else {
                            if (vCodeTable == 2) //VNI
                                InsertKeyLength(1);
                        }
                    } else if (vCodeTable == 3) { //Unicode Compound
                        _newChar = _tempChar;
                        _newCharHi = (_newChar >> 13);
                        _newChar &= 0x1FFF;
                        
                        InsertKeyLength(_newCharHi > 0 ? 2 : 1);
                        _newCharString[_j++] = _newChar;
                        if (_newCharHi > 0) {
                            _newCharSize++;
                            _newCharString[_j++] = _unicodeCompoundMark[_newCharHi - 1];
                        }
                        
                    }
                }
            }//end for
        }
        
        if (!_willContinuteSending && (pData->code == vRestore || pData->code == vRestoreAndStartNewSession)) { //if is restore
            if (keyCodeToCharacter(_keycode) != 0) {
                _newCharSize++;
                _newCharString[_j++] = keyCodeToCharacter(_keycode | ((_flag & kCGEventFlagMaskAlphaShift) || (_flag & kCGEventFlagMaskShift) ? CAPS_MASK : 0));
            } else {
                _willSendControlKey = true;
            }
        }
        if (!_willContinuteSending && pData->code == vRestoreAndStartNewSession) {
            startNewSession();
        }
        
        _newEventDown = CGEventCreateKeyboardEvent(myEventSource, 0, true);
        _newEventUp = CGEventCreateKeyboardEvent(myEventSource, 0, false);
        CGEventKeyboardSetUnicodeString(_newEventDown, _willContinuteSending ? 16 : _newCharSize - offset, _newCharString);
        CGEventKeyboardSetUnicodeString(_newEventUp, _willContinuteSending ? 16 : _newCharSize - offset, _newCharString);
        CGEventTapPostEvent(_proxy, _newEventDown);
        CGEventTapPostEvent(_proxy, _newEventUp);
        CFRelease(_newEventDown);
        CFRelease(_newEventUp);

        if (_willContinuteSending) {
            SendNewCharString(dataFromMacro, dataFromMacro ? _k : 16);
        }
        
        //the case when hCode is vRestore or vRestoreAndStartNewSession, the word is invalid and last key is control key such as TAB, LEFT ARROW, RIGHT ARROW,...
        if (_willSendControlKey) {
            SendKeyCode(_keycode);
        }
    }
            
    bool checkHotKey(int hotKeyData, bool checkKeyCode=true) {
        if ((hotKeyData & (~0x8000)) == EMPTY_HOTKEY)
            return false;
        if (HAS_CONTROL(hotKeyData) ^ GET_BOOL(_lastFlag & kCGEventFlagMaskControl))
            return false;
        if (HAS_OPTION(hotKeyData) ^ GET_BOOL(_lastFlag & kCGEventFlagMaskAlternate))
            return false;
        if (HAS_COMMAND(hotKeyData) ^ GET_BOOL(_lastFlag & kCGEventFlagMaskCommand))
            return false;
        if (HAS_SHIFT(hotKeyData) ^ GET_BOOL(_lastFlag & kCGEventFlagMaskShift))
            return false;
        if (checkKeyCode) {
            if (GET_SWITCH_KEY(hotKeyData) != _keycode)
                return false;
        }
        return true;
    }
    
    void switchLanguage() {
        //the hotkey may be pressed in a panel which has just opened: apply its remembered mode first
        getTargetApp();
        if (vLanguage == 0)
            vLanguage = 1;
        else
            vLanguage = 0;
        startNewSession();
        if (vUseSmartSwitchKey)
            RememberAppMode();
        SaveModeAndRefreshMenu();
        if (HAS_BEEP(vSwitchKeyStatus)) {
            dispatch_async(dispatch_get_main_queue(), ^{
            NSBeep();
            });
        }
        VKLog(@"mode", @"%@ by hotkey", vLanguage ? @"Vietnamese" : @"English");
    }
    
    void handleMacro() {
        //fix autocomplete
        if (shouldUseRecommendWorkaround()) {
            SendEmptyCharacter();
            pData->backspaceCount++;
        }
        
        //send backspace
        if (pData->backspaceCount > 0) {
            SendDeleteKeys(pData->backspaceCount);
        }
        //send real data
        if (!vSendKeyStepByStep) {
            SendNewCharString(true);
        } else {
            for (int i = 0; i < pData->macroData.size(); i++) {
                if (pData->macroData[i] & PURE_CHARACTER_MASK) {
                    SendPureCharacter(pData->macroData[i]);
                } else {
                    SendKeyCode(pData->macroData[i]);
                }
            }
        }
        SendKeyCode(_keycode | (_flag & kCGEventFlagMaskShift ? CAPS_MASK : 0));
    }

    // TODO: Research API to convert character into CGKeyCode more elegantly!
    int ConvertKeyStringToKeyCode(NSString *keyString, CGKeyCode fallback) {
        // Infomation about capitalization (shift/caps) is already included
        // in the original CGEvent, only find out which position on keyboard a key is pressed
        NSString *lowercasedKeyString = [keyString lowercaseString];
        if (!lowercasedKeyString) {
            return fallback;
        }
        
        NSNumber *keycode = [keyStringToKeyCodeMap objectForKey:lowercasedKeyString];

        if (keycode) {
            return [keycode intValue];
        }
        return fallback;
    }

    // If conversion fails, return fallbackKeyCode
    // Like NSEvent.charactersIgnoringModifiers (only Shift counts), with the keyboard layout saved by UpdateInputSourceLanguage():
    // asking macOS for the layout must happen on the main thread
    CGKeyCode ConvertEventToKeyboadLayoutCompatKeyCode(CGEventRef keyEvent, CGKeyCode fallbackKeyCode) {
        if (_keyboardLayout == NULL)
            return fallbackKeyCode;
        UInt32 modifiers = (CGEventGetFlags(keyEvent) & kCGEventFlagMaskShift) ? (shiftKey >> 8) & 0xFF : 0;
        UInt32 deadKeyState = 0;
        UniChar chars[4];
        UniCharCount length = 0;
        if (UCKeyTranslate((const UCKeyboardLayout*)CFDataGetBytePtr(_keyboardLayout), fallbackKeyCode, kUCKeyActionDown, modifiers,
                           _keyboardType, kUCKeyTranslateNoDeadKeysMask, &deadKeyState, 4, &length, chars) != noErr || length == 0)
            return fallbackKeyCode;
        return ConvertKeyStringToKeyCode([NSString stringWithCharacters:chars length:length], fallbackKeyCode);
    }
    
    static CGEventRef HandleEvent(CGEventTapProxy proxy, CGEventType type, CGEventRef event);

    /**
     * MAIN HOOK entry, very important function.
     * MAIN Callback. It runs on the keyboard thread, see OpenKeyManager
     */
    CGEventRef OpenKeyCallback(CGEventTapProxy proxy, CGEventType type, CGEventRef event, void *refcon) {
        //macOS turns off the tap when the callback is too slow, turn it on again
        if (type == kCGEventTapDisabledByTimeout || type == kCGEventTapDisabledByUserInput) {
            [OpenKeyManager reEnableEventTap];
            int count = ++_tapRestartCount;
            VKLog(@"tap", @"macOS turned off the event tap (%@), turned it on again (%d times)",
                  type == kCGEventTapDisabledByTimeout ? @"too slow" : @"user input", count);
            return event;
        }
        
        //dont handle my event
        if (CGEventGetIntegerValueField(event, kCGEventSourceStateID) == CGEventSourceGetSourceStateID(myEventSource)) {
            return event;
        }
        
        //the ViKey input method is the input source: it types, hotkeys included
        if (_isViKeyInputMethod) {
            return event;
        }
        
        //the time includes waiting for the lock: it is how long the key waits
        uint64_t start = mach_absolute_time();
        ENGINE_LOCK;
        CGEventRef result = HandleEvent(proxy, type, event);
        uint64_t time = mach_absolute_time() - start;
        _eventCount++;
        _eventTotalTime += time;
        if (time > _eventMaxTime)
            _eventMaxTime = time;
        if (MachToMicroseconds(time) > SLOW_EVENT_LOG)
            VKLog(@"tap", @"slow event handling: %.1f ms", MachToMicroseconds(time) / 1000);
        return result;
    }
    
    static CGEventRef HandleEvent(CGEventTapProxy proxy, CGEventType type, CGEventRef event) {
        _flag = CGEventGetFlags(event);
        _keycode = (CGKeyCode)CGEventGetIntegerValueField(event, kCGKeyboardEventKeycode);
        
        if (type == kCGEventKeyDown && vPerformLayoutCompat) {
            // If conversion fail, use current keycode
           _keycode = ConvertEventToKeyboadLayoutCompatKeyCode(event, _keycode);
        }
        
        //things which can move the focus to another app or panel: click, Cmd+Space, Cmd+Tab, Escape, Return,...
        if (type == kCGEventLeftMouseDown || type == kCGEventRightMouseDown ||
            (type == kCGEventKeyDown && (OTHER_CONTROL_KEY || _keycode == KEY_ESC || _keycode == KEY_RETURN || _keycode == KEY_ENTER))) {
            InvalidateTargetApp();
            CheckTypingAppSoon();
        }
        
        //switch language shortcut; convert hotkey
        if (type == kCGEventKeyDown) {
            if (GET_SWITCH_KEY(vSwitchKeyStatus) != _keycode && GET_SWITCH_KEY(convertToolHotKey) != _keycode) {
                _lastFlag = 0;
            } else {
                if (GET_SWITCH_KEY(vSwitchKeyStatus) == _keycode && checkHotKey(vSwitchKeyStatus, GET_SWITCH_KEY(vSwitchKeyStatus) != 0xFE)){
                    switchLanguage();
                    _lastFlag = 0;
                    _hasJustUsedHotKey = true;
                    return NULL;
                }
                if (GET_SWITCH_KEY(convertToolHotKey) == _keycode && checkHotKey(convertToolHotKey, GET_SWITCH_KEY(convertToolHotKey) != 0xFE)){
                    //run after the callback returns: it can show a modal alert
                    dispatch_async(dispatch_get_main_queue(), ^{
                        [appDelegate onQuickConvert];
                    });
                    _lastFlag = 0;
                    _hasJustUsedHotKey = true;
                    return NULL;
                }
            }
            _hasJustUsedHotKey = _lastFlag != 0;
        } else if (type == kCGEventFlagsChanged) {
            if (_lastFlag == 0 || _lastFlag < _flag) {
                _lastFlag = _flag;
            } else if (_lastFlag > _flag)  {
                //check switch
                if (checkHotKey(vSwitchKeyStatus, GET_SWITCH_KEY(vSwitchKeyStatus) != 0xFE)) {
                    _lastFlag = 0;
                    switchLanguage();
                    _hasJustUsedHotKey = true;
                    return NULL;
                }
                if (checkHotKey(convertToolHotKey, GET_SWITCH_KEY(convertToolHotKey) != 0xFE)) {
                    _lastFlag = 0;
                    dispatch_async(dispatch_get_main_queue(), ^{
                        [appDelegate onQuickConvert];
                    });
                    _hasJustUsedHotKey = true;
                    return NULL;
                }
                //check temporarily turn off spell checking
                if (vTempOffSpelling && !_hasJustUsedHotKey && _lastFlag & kCGEventFlagMaskControl) {
                    vTempOffSpellChecking();
                }
                if (vTempOffOpenKey && !_hasJustUsedHotKey && _lastFlag & kCGEventFlagMaskCommand) {
                    vTempOffEngine();
                }
                _lastFlag = 0;
                _hasJustUsedHotKey = false;
            }
        }

        // Also check correct event hooked
        if ((type != kCGEventKeyDown) && (type != kCGEventKeyUp) &&
            (type != kCGEventLeftMouseDown) && (type != kCGEventRightMouseDown))
            return event;
        
        _proxy = proxy;
        
        //the app which receives the keys: it can be a panel over the frontmost app (Spotlight, Alfred,...).
        //When it changes, its remembered mode is applied
        if (type == kCGEventKeyDown)
            getTargetApp();
        
        //If is in english mode, or the app always uses English
        if (vLanguage == 0 || _isExcludedAppActive) {
            if (vUseMacro && vUseMacroInEnglishMode && type == kCGEventKeyDown) {
                vEnglishMode((type == kCGEventKeyDown ? vKeyEventState::KeyDown : vKeyEventState::MouseDown),
                             _keycode,
                             (_flag & kCGEventFlagMaskShift) || (_flag & kCGEventFlagMaskAlphaShift),
                             OTHER_CONTROL_KEY);
                
                if (pData->code == vReplaceMaro) { //handle macro in english mode
                    handleMacro();
                    return NULL;
                }
            }
            return event;
        }
        
        //handle mouse
        if (type == kCGEventLeftMouseDown || type == kCGEventRightMouseDown) {
            RequestNewSession();
            return event;
        }

        //if "turn off Vietnamese when in other language" mode on
        if (vOtherLanguage && !_isEnglishInputSource) {
            return event;
        }
        
        //handle keyboard
        if (type == kCGEventKeyDown) {
            //send event signal to Engine
            vKeyHandleEvent(vKeyEvent::Keyboard,
                            vKeyEventState::KeyDown,
                            _keycode,
                            _flag & kCGEventFlagMaskShift ? 1 : (_flag & kCGEventFlagMaskAlphaShift ? 2 : 0),
                            OTHER_CONTROL_KEY);
            if (pData->code == vDoNothing) { //do nothing
                if (IS_DOUBLE_CODE(vCodeTable)) { //VNI
                    if (pData->extCode == 1) { //break key
                        _syncKey.clear();
                    } else if (pData->extCode == 2) { //delete key
                        if (_syncKey.size() > 0) {
                            if (_syncKey.back() > 1 && (vCodeTable == 2 || !containUnicodeCompoundApp(getTargetApp()))) {
                                //send one more backspace
                                CGEventTapPostEvent(_proxy, eventBackSpaceDown);
                                CGEventTapPostEvent(_proxy, eventBackSpaceUp);
                            }
                            _syncKey.pop_back();
                        }
                       
                    } else if (pData->extCode == 3) { //normal key
                        InsertKeyLength(1);
                    }
                }
                return event;
            } else if (pData->code == vWillProcess || pData->code == vRestore || pData->code == vRestoreAndStartNewSession) { //handle result signal
                
                //fix autocomplete
                if (shouldUseRecommendWorkaround() && pData->extCode != 4) {
                    if (vFixChromiumBrowser && [_unicodeCompoundApp containsObject:getTargetApp()]) {
                        if (pData->backspaceCount > 0) {
                            SendShiftAndLeftArrow();
                            if (pData->backspaceCount == 1)
                                pData->backspaceCount--;
                        }
                    } else {
                        SendEmptyCharacter();
                        pData->backspaceCount++;
                    
                    }
                }

                //send backspace
                if (pData->backspaceCount > 0 && pData->backspaceCount < MAX_BUFF) {
                    SendDeleteKeys(pData->backspaceCount);
                }
                
                //send new character
                if (!vSendKeyStepByStep) {
                    SendNewCharString();
                } else {
                    if (pData->newCharCount > 0 && pData->newCharCount <= MAX_BUFF) {
                        for (int i = pData->newCharCount - 1; i >= 0; i--) {
                            SendKeyCode(pData->charData[i]);
                        }
                    }
                    if (pData->code == vRestore || pData->code == vRestoreAndStartNewSession) {
                        SendKeyCode(_keycode | ((_flag & kCGEventFlagMaskAlphaShift) || (_flag & kCGEventFlagMaskShift) ? CAPS_MASK : 0));
                    }
                    if (pData->code == vRestoreAndStartNewSession) {
                        startNewSession();
                    }
                }
            } else if (pData->code == vReplaceMaro) { //MACRO
                handleMacro();
            }
            
            return NULL;
        }
        
        return event;
    }
}

#pragma mark - Diagnostics

@interface VKEngineStatus ()
@property (nonatomic, readwrite) BOOL tapRunning;
@property (nonatomic, readwrite) BOOL tapEnabled;
@property (nonatomic, readwrite) NSInteger tapRestartCount;
@property (nonatomic, readwrite) NSInteger eventCount;
@property (nonatomic, readwrite) double averageEventMicroseconds;
@property (nonatomic, readwrite) double maxEventMicroseconds;
@property (nonatomic, readwrite) double detectMicroseconds;
@property (nonatomic, readwrite) NSInteger detectMethod;
@property (nonatomic, readwrite) BOOL accessibilityAnswered;
@property (nonatomic, readwrite, copy) NSString* frontApp;
@property (nonatomic, readwrite, copy) NSString* typingApp;
@property (nonatomic, readwrite) BOOL typingAppExcluded;
@property (nonatomic, readwrite, copy) NSString* inputSource;
@property (nonatomic, readwrite) BOOL englishInputSource;
@end

@implementation VKEngineStatus
//"::": the properties have ivars with the same names as the globals
+(VKEngineStatus*)current {
    VKEngineStatus* status = [[VKEngineStatus alloc] init];
    status.tapRunning = [OpenKeyManager isInited];
    status.tapEnabled = [OpenKeyManager isEventTapEnabled];
    status.tapRestartCount = ::_tapRestartCount;
    ENGINE_LOCK;
    status.eventCount = (NSInteger)::_eventCount;
    status.averageEventMicroseconds = ::_eventCount > 0 ? MachToMicroseconds(::_eventTotalTime) / ::_eventCount : 0;
    status.maxEventMicroseconds = MachToMicroseconds(::_eventMaxTime);
    status.detectMicroseconds = ::_detectTime;
    status.detectMethod = ::_detectMethod;
    status.accessibilityAnswered = ::_accessibilityAnswered;
    status.frontApp = ::_frontApp;
    status.typingApp = ::_typingApp;
    status.typingAppExcluded = ::_isExcludedAppActive;
    status.inputSource = ::_inputSource;
    status.englishInputSource = ::_isEnglishInputSource;
    return status;
}
@end
