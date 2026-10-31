//
//  InputController.mm
//  ViKey input method
//
//  macOS makes one controller for each text field which uses the input method. The controller
//  gives the keys to the composer and shows the word in the app:
//  - direct: the word is written into the document and changed with replacementRange, like the
//    event tap does with Backspace, so there is no underline
//  - marked text: the word is underlined until it ends; used in terminals, in apps which do not tell
//    where the cursor is, and in apps the user chooses in the input menu
//

#import <Cocoa/Cocoa.h>
#import <InputMethodKit/InputMethodKit.h>
#import "Composer.h"
#include "Engine.h"

#define VIKEY_APP_DOMAIN @"com.hkvn.vikey"
//posted by the app and the input method when Vietnamese / English changes; the object is the bundle id of the sender
#define LANGUAGE_CHANGED_NOTIFICATION @"com.hkvn.vikey.LanguageChanged"
#define EMPTY_HOTKEY 0xFE0000FE
#define NOT_FOUND_RANGE NSMakeRange(NSNotFound, NSNotFound)
#define OTHER_MODIFIERS (NSEventModifierFlagCommand | NSEventModifierFlagControl | NSEventModifierFlagOption | \
                         NSEventModifierFlagFunction | NSEventModifierFlagNumericPad | NSEventModifierFlagHelp)
#define HOTKEY_MODIFIERS (NSEventModifierFlagControl | NSEventModifierFlagOption | NSEventModifierFlagCommand | NSEventModifierFlagShift)

//one engine for the whole input method: only one text field types at a time
static VKComposer* composer;
static NSSet<NSString*>* excludedApps;
static NSData* loadedMacroData;

//terminals do not tell the input method where the cursor is: the word is underlined there
static NSSet<NSString*>* const terminalApps = [NSSet setWithArray:@[
    @"com.mitchellh.ghostty", @"com.apple.Terminal", @"com.googlecode.iterm2", @"net.kovidgoyal.kitty",
    @"org.alacritty", @"io.alacritty", @"com.github.wez.wezterm", @"dev.warp.Warp-Stable",
]];
//setting of the input method itself: other apps where the word is underlined (chosen in the menu, or learned)
static NSString* const MarkedTextAppsKey = @"MarkedTextApps";

static BOOL UsesMarkedText(NSString* app) {
    return [terminalApps containsObject:app] ||
           [[[NSUserDefaults standardUserDefaults] stringArrayForKey:MarkedTextAppsKey] containsObject:app];
}

static void SetUsesMarkedText(NSString* app, BOOL on) {
    if (app == nil)
        return;
    NSMutableArray* apps = [[[NSUserDefaults standardUserDefaults] stringArrayForKey:MarkedTextAppsKey] ?: @[] mutableCopy];
    [apps removeObject:app];
    if (on)
        [apps addObject:app];
    [[NSUserDefaults standardUserDefaults] setObject:apps forKey:MarkedTextAppsKey];
}

static string clipboardText() {
    NSString* text = [[NSPasteboard generalPasteboard] stringForType:NSPasteboardTypeString] ?: @"";
    if (text.length > 2000)
        text = [text substringWithRange:[text rangeOfComposedCharacterSequencesForRange:NSMakeRange(0, 2000)]];
    return string(text.UTF8String ?: "");
}

//the options of the ViKey app, read again each time a text field gets the focus
static void LoadSettings() {
    CFPreferencesAppSynchronize((__bridge CFStringRef)VIKEY_APP_DOMAIN);
    NSUserDefaults* vikey = [[NSUserDefaults alloc] initWithSuiteName:VIKEY_APP_DOMAIN];
    vInputType = (int)[vikey integerForKey:@"InputType"];
    vCodeTable = MAX(0, (int)[vikey integerForKey:@"CodeTable"]);
    vCheckSpelling = (int)[vikey integerForKey:@"Spelling"];
    vSetCheckSpelling();
    vUseModernOrthography = (int)[vikey integerForKey:@"ModernOrthography"];
    vQuickTelex = (int)[vikey integerForKey:@"QuickTelex"];
    vRestoreIfWrongSpelling = (int)[vikey integerForKey:@"RestoreIfInvalidWord"];
    vUseMacro = (int)[vikey integerForKey:@"UseMacro"];
    vAutoCapsMacro = (int)[vikey integerForKey:@"vAutoCapsMacro"];
    vUpperCaseFirstChar = (int)[vikey integerForKey:@"UpperCaseFirstChar"];
    vTempOffSpelling = (int)[vikey integerForKey:@"vTempOffSpelling"];
    vAllowConsonantZFWJ = (int)[vikey integerForKey:@"vAllowConsonantZFWJ"];
    vQuickStartConsonant = (int)[vikey integerForKey:@"vQuickStartConsonant"];
    vQuickEndConsonant = (int)[vikey integerForKey:@"vQuickEndConsonant"];
    vTempOffOpenKey = (int)[vikey integerForKey:@"vTempOffOpenKey"];
    vSwitchKeyStatus = (int)[vikey integerForKey:@"SwitchKeyStatus"];
    if (vSwitchKeyStatus == 0)
        vSwitchKeyStatus = 0x7A000206; //option + z, as in the app
    excludedApps = [NSSet setWithArray:[vikey stringArrayForKey:@"ExcludedApps"] ?: @[]];
    NSData* macroData = [vikey dataForKey:@"macroData"];
    if (![macroData isEqualToData:loadedMacroData]) {
        loadedMacroData = macroData;
        initMacroMap((Byte*)macroData.bytes, (int)macroData.length);
    }
    macroClipboardText = clipboardText;
    vLanguage = [vikey objectForKey:@"InputMethod"] == nil ? 1 : (int)[vikey integerForKey:@"InputMethod"];
}

//Vietnamese / English is shared with the app: one mode, whichever input source types
static BOOL IsVietnamese() {
    return vLanguage != 0;
}

static void ReloadLanguage() {
    CFPreferencesAppSynchronize((__bridge CFStringRef)VIKEY_APP_DOMAIN);
    NSNumber* language = CFBridgingRelease(CFPreferencesCopyAppValue(CFSTR("InputMethod"), (__bridge CFStringRef)VIKEY_APP_DOMAIN));
    vLanguage = language == nil ? 1 : language.intValue;
}

static void SaveLanguage() {
    CFPreferencesSetAppValue(CFSTR("InputMethod"), (__bridge CFNumberRef)@(vLanguage), (__bridge CFStringRef)VIKEY_APP_DOMAIN);
    CFPreferencesAppSynchronize((__bridge CFStringRef)VIKEY_APP_DOMAIN);
    [[NSDistributedNotificationCenter defaultCenter] postNotificationName:LANGUAGE_CHANGED_NOTIFICATION
                                                                   object:[[NSBundle mainBundle] bundleIdentifier]
                                                                 userInfo:nil deliverImmediately:YES];
}

//keys pressed on the whole Mac. An app handles some shortcuts (such as Command + Shift + T) before the input method
//sees them: without this, releasing Command + Shift after such a shortcut would look like a hotkey with no key
static int64_t SystemKeyDownCount() {
    return CGEventSourceCounterForEventType(kCGEventSourceStateHIDSystemState, kCGEventKeyDown);
}

//the modifier keys of the hotkey are down, no more and no less
static BOOL HotKeyModifiersMatch(int hotKey, NSEventModifierFlags flags) {
    return HAS_CONTROL(hotKey) == GET_BOOL(flags & NSEventModifierFlagControl) &&
           HAS_OPTION(hotKey) == GET_BOOL(flags & NSEventModifierFlagOption) &&
           HAS_COMMAND(hotKey) == GET_BOOL(flags & NSEventModifierFlagCommand) &&
           HAS_SHIFT(hotKey) == GET_BOOL(flags & NSEventModifierFlagShift);
}

@interface ViKeyInputController : IMKInputController
@end

@implementation ViKeyInputController {
    NSArray<NSString*>* _shown; //the word as it is in the document (direct) or in the marked text
    NSString* _app;
    BOOL _direct;
    BOOL _excluded;
    NSEventModifierFlags _lastFlags; //modifier keys pressed together, for a hotkey with no other key
    BOOL _keyPressedWithFlags;
    int64_t _keyDownCountWithFlags; //SystemKeyDownCount() when the modifier keys went down
}

-(instancetype)initWithServer:(IMKServer*)server delegate:(id)delegate client:(id)inputClient {
    if (self = [super initWithServer:server delegate:delegate client:inputClient]) {
        if (composer == nil) {
            composer = [[VKComposer alloc] init];
            //the app changed Vietnamese / English
            [[NSDistributedNotificationCenter defaultCenter] addObserverForName:LANGUAGE_CHANGED_NOTIFICATION object:nil queue:nil
                                                                      usingBlock:^(NSNotification* note) {
                if (![note.object isEqual:[[NSBundle mainBundle] bundleIdentifier]])
                    ReloadLanguage();
            }];
        }
        _shown = @[];
    }
    return self;
}

-(NSUInteger)recognizedEvents:(id)sender {
    return NSEventMaskKeyDown | NSEventMaskFlagsChanged | NSEventMaskLeftMouseDown | NSEventMaskRightMouseDown;
}

-(void)activateServer:(id)sender {
    [super activateServer:sender];
    LoadSettings();
    [composer finishWord];
    _shown = @[];
    _app = [sender bundleIdentifier];
    _excluded = [excludedApps containsObject:_app];
    _direct = !UsesMarkedText(_app) && [self canWriteDirectly:sender];
}

-(void)deactivateServer:(id)sender {
    [self commitComposition:sender];
    [super deactivateServer:sender];
}

-(void)commitComposition:(id)sender {
    [self showWord:[composer finishWord] finished:YES extraDelete:0 client:sender];
}

-(id)composedString:(id)sender {
    return _direct ? @"" : VKWordText(_shown);
}

#pragma mark - Keys

-(BOOL)handleEvent:(NSEvent*)event client:(id)sender {
    switch (event.type) {
        case NSEventTypeFlagsChanged:
            [self handleFlagsChanged:event.modifierFlags client:sender];
            return NO;
        case NSEventTypeLeftMouseDown:
        case NSEventTypeRightMouseDown:
            //the cursor moves: the word ends where it is
            [self commitComposition:sender];
            return NO;
        case NSEventTypeKeyDown:
            break;
        default:
            return NO;
    }
    _keyPressedWithFlags = YES;
    NSEventModifierFlags flags = event.modifierFlags;
    if ((vSwitchKeyStatus & ~0x8000) != EMPTY_HOTKEY && GET_SWITCH_KEY(vSwitchKeyStatus) == event.keyCode &&
        HotKeyModifiersMatch(vSwitchKeyStatus, flags)) {
        [self switchLanguage:sender];
        return YES;
    }
    if (!IsVietnamese() || _excluded)
        return NO;

    if (_direct && _shown.count > 0) {
        switch ([self checkShownWord:sender]) {
            case VKShownWordOK:
                break;
            case VKShownWordMoved: //the user moved the cursor in a way the input method does not see
                [composer finishWord];
                _shown = @[];
                break;
            case VKShownWordUnknown: //the app does not tell: underline the word in this app from now on
                SetUsesMarkedText(_app, YES);
                _direct = NO;
                [composer finishWord];
                _shown = @[];
                break;
        }
    }
    BOOL handled = [composer handleKeyCode:event.keyCode characters:event.characters ?: @""
                                     shift:(flags & NSEventModifierFlagShift) != 0
                                  capsLock:(flags & NSEventModifierFlagCapsLock) != 0
                            otherModifiers:(flags & OTHER_MODIFIERS) != 0];
    if (composer.finishedWord != nil)
        [self showWord:composer.finishedWord finished:YES extraDelete:composer.extraDeleteCount client:sender];
    else
        [self showWord:composer.word finished:handled ? NO : YES extraDelete:composer.extraDeleteCount client:sender];
    return handled;
}

//hotkey with modifier keys only (it works when they are released), and the "press Control / Command alone" options
-(void)handleFlagsChanged:(NSEventModifierFlags)flags client:(id)sender {
    flags &= HOTKEY_MODIFIERS;
    if (_lastFlags == 0 || flags > _lastFlags) {
        if (_lastFlags == 0) {
            _keyPressedWithFlags = NO;
            _keyDownCountWithFlags = SystemKeyDownCount();
        }
        _lastFlags = flags;
        return;
    }
    if (!_keyPressedWithFlags && SystemKeyDownCount() == _keyDownCountWithFlags) {
        if ((vSwitchKeyStatus & ~0x8000) != EMPTY_HOTKEY && GET_SWITCH_KEY(vSwitchKeyStatus) == 0xFE &&
            HotKeyModifiersMatch(vSwitchKeyStatus, _lastFlags)) {
            [self switchLanguage:sender];
        } else if (vTempOffSpelling && _lastFlags == NSEventModifierFlagControl) {
            vTempOffSpellChecking();
        } else if (vTempOffOpenKey && _lastFlags == NSEventModifierFlagCommand) {
            vTempOffEngine();
        }
    }
    _lastFlags = flags;
    _keyPressedWithFlags = YES;
}

-(void)switchLanguage:(id)sender {
    [self commitComposition:sender];
    vLanguage = IsVietnamese() ? 0 : 1;
    SaveLanguage();
    if (HAS_BEEP(vSwitchKeyStatus))
        NSBeep();
}

#pragma mark - Showing the word

//the client tells where the cursor is and gives the text before it: the word can be written into the document
-(BOOL)canWriteDirectly:(id)client {
    NSRange selection = [client selectedRange];
    if (selection.location == NSNotFound)
        return NO;
    if (selection.location == 0)
        return YES;
    return [client attributedSubstringFromRange:NSMakeRange(selection.location - 1, 1)] != nil;
}

typedef NS_ENUM(NSInteger, VKShownWord) {
    VKShownWordOK,      //the text before the cursor is the word written before
    VKShownWordMoved,   //the cursor is somewhere else
    VKShownWordUnknown, //the app does not tell where the cursor is, or the text
};

-(VKShownWord)checkShownWord:(id)client {
    NSString* shown = VKWordText(_shown);
    NSRange selection = [client selectedRange];
    if (selection.location == NSNotFound)
        return VKShownWordUnknown;
    if (selection.length > 0 || selection.location < shown.length)
        return VKShownWordMoved;
    NSAttributedString* before = [client attributedSubstringFromRange:NSMakeRange(selection.location - shown.length, shown.length)];
    if (before == nil)
        return VKShownWordUnknown;
    return [before.string isEqualToString:shown] ? VKShownWordOK : VKShownWordMoved;
}

//finished: the word ends, the next key starts a new one
-(void)showWord:(NSArray<NSString*>*)word finished:(BOOL)finished extraDelete:(NSInteger)extraDelete client:(id)client {
    if (_direct) {
        //change only the end which is different
        NSUInteger same = 0;
        while (same < _shown.count && same < word.count && [_shown[same] isEqualToString:word[same]])
            same++;
        NSUInteger deleteLength = extraDelete;
        for (NSUInteger i = same; i < _shown.count; i++)
            deleteLength += _shown[i].length;
        NSString* insert = VKWordText([word subarrayWithRange:NSMakeRange(same, word.count - same)]);
        if (deleteLength > 0 || insert.length > 0) {
            NSRange replace = NOT_FOUND_RANGE;
            if (deleteLength > 0) {
                NSRange selection = [client selectedRange];
                if (selection.location != NSNotFound && selection.location >= deleteLength)
                    replace = NSMakeRange(selection.location - deleteLength, deleteLength);
            }
            [client insertText:insert replacementRange:replace];
        }
        _shown = finished ? @[] : word;
        return;
    }
    NSString* text = VKWordText(word);
    if (finished) {
        if (text.length > 0)
            [client insertText:text replacementRange:NOT_FOUND_RANGE];
        else if (_shown.count > 0)
            [client setMarkedText:@"" selectionRange:NSMakeRange(0, 0) replacementRange:NOT_FOUND_RANGE];
        _shown = @[];
    } else if (text.length > 0 || _shown.count > 0) {
        [client setMarkedText:text selectionRange:NSMakeRange(text.length, 0) replacementRange:NOT_FOUND_RANGE];
        _shown = word;
    }
}

#pragma mark - Input menu

-(NSMenu*)menu {
    NSMenu* menu = [[NSMenu alloc] initWithTitle:@"ViKey"];
    NSMenuItem* vietnamese = [menu addItemWithTitle:@"Gõ Tiếng Việt" action:@selector(toggleVietnamese:) keyEquivalent:@""];
    vietnamese.state = IsVietnamese() ? NSControlStateValueOn : NSControlStateValueOff;
    NSString* appName = [NSRunningApplication runningApplicationsWithBundleIdentifier:_app ?: @""].firstObject.localizedName ?: _app;
    if (appName != nil) {
        NSMenuItem* marked = [menu addItemWithTitle:[NSString stringWithFormat:@"Gạch chân từ đang gõ trong %@", appName]
                                             action:@selector(toggleMarkedText:) keyEquivalent:@""];
        marked.state = UsesMarkedText(_app) ? NSControlStateValueOn : NSControlStateValueOff;
        //terminals always need it
        marked.enabled = ![terminalApps containsObject:_app];
    }
    [menu addItem:[NSMenuItem separatorItem]];
    [menu addItemWithTitle:@"Cài đặt ViKey…" action:@selector(openSettings:) keyEquivalent:@""];
    for (NSMenuItem* item in menu.itemArray)
        item.target = self;
    return menu;
}

-(void)toggleVietnamese:(id)sender {
    [self switchLanguage:[self client]];
}

-(void)toggleMarkedText:(id)sender {
    SetUsesMarkedText(_app, !UsesMarkedText(_app));
    [self commitComposition:[self client]];
    _direct = !UsesMarkedText(_app) && [self canWriteDirectly:[self client]];
}

-(void)openSettings:(id)sender {
    NSURL* app = [[NSWorkspace sharedWorkspace] URLForApplicationWithBundleIdentifier:VIKEY_APP_DOMAIN];
    if (app != nil)
        [[NSWorkspace sharedWorkspace] openApplicationAtURL:app configuration:[NSWorkspaceOpenConfiguration configuration] completionHandler:nil];
}
@end
