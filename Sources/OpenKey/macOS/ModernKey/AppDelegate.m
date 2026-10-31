//
//  AppDelegate.m
//  ModernKey
//
//  Created by Tuyen on 1/18/19.
//  Copyright © 2019 Tuyen Mai. All rights reserved.
//

#import <AppKit/AppKit.h>
#import <Carbon/Carbon.h>
#import <Cocoa/Cocoa.h>
#import <ServiceManagement/ServiceManagement.h>
#import <UserNotifications/UserNotifications.h>
#include <libproc.h>
#include <sys/proc_info.h>
#import "AppDelegate.h"
#import "OpenKeyManager.h"
#import "MJAccessibilityUtils.h"
#import "Logging.h"
#import "ViKey-Swift.h"

AppDelegate* appDelegate;
extern void OnTableCodeChange(void);
extern void OnInputMethodChanged(void);
extern void RequestNewSession(void);
extern void OnFrontAppChanged(void);
extern bool IsExcludedAppActive(void);
//the engine lock, see Engine.h: hold it while changing the engine options which the keyboard thread also changes
extern void EngineLock(void);
extern void EngineUnlock(void);

//see document in Engine.h
int vLanguage = 1;
int vInputType = 0;
int vFreeMark = 0;
int vCodeTable = 0;
int vCheckSpelling = 1;
int vUseModernOrthography = 1;
int vQuickTelex = 0;
#define DEFAULT_SWITCH_STATUS 0x7A000206 //default option + z
int vSwitchKeyStatus = DEFAULT_SWITCH_STATUS;
int vRestoreIfWrongSpelling = 0;
int vFixRecommendBrowser = 1;
int vUseMacro = 1;
int vUseMacroInEnglishMode = 1;
int vAutoCapsMacro = 0;
int vSendKeyStepByStep = 0;
int vUseSmartSwitchKey = 1;
int vUpperCaseFirstChar = 0;
int vTempOffSpelling = 0;
int vAllowConsonantZFWJ = 0;
int vQuickStartConsonant = 0;
int vQuickEndConsonant = 0;
int vRememberCode = 1; //new on version 2.0
int vOtherLanguage = 1; //new on version 2.0
int vTempOffOpenKey = 0; //new on version 2.0

int vShowIconOnDock = 0; //new on version 2.0

int vPerformLayoutCompat = 0;

//beta feature
int vFixChromiumBrowser = 0; //new on version 2.0

extern int convertToolHotKey;
extern bool convertToolDontAlertWhenCompleted;

#define SECURE_INPUT_NOTIFY_DELAY 10 //seconds; short password typing should not show a notification
#define SECURE_INPUT_NOTIFICATION @"SecureInput"

//ViKey was OpenKey, which used this bundle id
#define OPENKEY_LEGACY_BUNDLE @"com.tuyenmai.openkey"

@interface AppDelegate () <UNUserNotificationCenterDelegate>

@end

//YES if process a started before process b
static BOOL startedBefore(const struct proc_bsdinfo* a, const struct proc_bsdinfo* b) {
    if (a->pbi_start_tvsec != b->pbi_start_tvsec)
        return a->pbi_start_tvsec < b->pbi_start_tvsec;
    if (a->pbi_start_tvusec != b->pbi_start_tvusec)
        return a->pbi_start_tvusec < b->pbi_start_tvusec;
    return a->pbi_pid < b->pbi_pid;
}


@implementation AppDelegate {
    SettingsWindowController *_settingsWC;
    MacroWindowController *_macroWC;
    ConvertToolWindowController *_convertWC;
    DiagnosticsWindowController *_diagnosticsWC;
    WelcomeWindowController *_welcomeWC;
    BOOL _started;
    
    NSStatusItem *statusItem;
    NSMenu *theMenu;
    
    NSMenuItem* menuInputMethod;
    
    NSMenuItem* mnuTelex;
    NSMenuItem* mnuVNI;
    NSMenuItem* mnuSimpleTelex1;
    NSMenuItem* mnuSimpleTelex2;
    
    NSMenuItem* mnuUnicode;
    NSMenuItem* mnuTCVN;
    NSMenuItem* mnuVNIWindows;
    
    NSMenuItem* mnuUnicodeComposite;
    NSMenuItem* mnuVietnameseLocaleCP1258;
    
    NSMenuItem* mnuQuickConvert;

    //Secure Input
    NSMenuItem* mnuSecureInput;
    NSMenuItem* mnuSecureInputSeparator;
    BOOL _secureInputOn;
    pid_t _secureInputPID;
    NSDate* _secureInputSince;
    BOOL _secureInputNotified;
}

//no Accessibility permission yet: the welcome window waits for it, then ViKey starts without a restart
-(void)showWelcome {
    if (_welcomeWC == nil) {
        __weak AppDelegate* weakSelf = self;
        _welcomeWC = [[WelcomeWindowController alloc] initOnGranted:^{
            [weakSelf startViKey];
        }];
    }
    [_welcomeWC show];
}

//the permission is granted but macOS does not send the keys yet: ViKey must be opened again
-(void)askToRelaunch {
    NSAlert *alert = [[NSAlert alloc] init];
    [alert setMessageText:@"Cần mở lại ViKey"];
    [alert setInformativeText:@"ViKey đã có quyền nhưng chưa nhận được phím gõ. Hãy mở lại ViKey để bắt đầu gõ."];
    [alert addButtonWithTitle:@"Mở lại ViKey"];
    [alert addButtonWithTitle:@"Thoát"];
    [alert.window makeKeyAndOrderFront:nil];
    [alert.window setLevel:NSStatusWindowLevel];
    if ([alert runModal] == NSAlertFirstButtonReturn) {
        //open again after this process quits: a new ViKey quits when an older one is still running
        NSTask* task = [[NSTask alloc] init];
        task.executableURL = [NSURL fileURLWithPath:@"/bin/sh"];
        task.arguments = @[@"-c", @"sleep 1; /usr/bin/open \"$0\"", [[NSBundle mainBundle] bundlePath]];
        [task launchAndReturnError:nil];
    }
    [NSApp terminate:nil];
}

//on the first launch, copy the settings of OpenKey (macros, hotkey, options,...)
-(void)importOpenKeySettings {
    NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
    if ([defaults objectForKey:@"NonFirstTime"] != nil || [defaults boolForKey:@"ImportedOpenKeySettings"])
        return;
    NSDictionary* openKeySettings = [defaults persistentDomainForName:OPENKEY_LEGACY_BUNDLE];
    for (NSString* key in openKeySettings) {
        [defaults setObject:openKeySettings[key] forKey:key];
    }
    [defaults setBool:YES forKey:@"ImportedOpenKeySettings"];
}

//ViKey and OpenKey running together would both change the keys
-(void)askToQuitOpenKey {
    NSArray<NSRunningApplication*>* apps = [NSRunningApplication runningApplicationsWithBundleIdentifier:OPENKEY_LEGACY_BUNDLE];
    if (apps.count == 0)
        return;
    NSAlert *alert = [[NSAlert alloc] init];
    [alert setMessageText:@"OpenKey đang chạy"];
    [alert setInformativeText:@"ViKey và OpenKey chạy cùng lúc sẽ gõ sai. Bạn nên thoát OpenKey."];
    [alert addButtonWithTitle:@"Thoát OpenKey"];
    [alert addButtonWithTitle:@"Để sau"];
    [alert.window makeKeyAndOrderFront:nil];
    [alert.window setLevel:NSStatusWindowLevel];
    if ([alert runModal] == NSAlertFirstButtonReturn) {
        for (NSRunningApplication* app in apps)
            [app terminate];
    }
}

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
    appDelegate = self;
    NSDictionary* info = [[NSBundle mainBundle] infoDictionary];
    VKLog(@"app", @"ViKey %@ (build %@) on macOS %@", info[@"CFBundleShortVersionString"], info[@"CFBundleVersion"],
          [[NSProcessInfo processInfo] operatingSystemVersionString]);
    [self importOpenKeySettings];
    
    [self registerSupportedNotification];
    
    //set quick tooltip
    [[NSUserDefaults standardUserDefaults] setObject: [NSNumber numberWithInt: 50]
                                              forKey: @"NSInitialToolTipDelay"];
    
    //check whether this app has been launched before that or not
    //Only check instances owned by current user (for multi-user/Fast User Switching support)
    //If two instances start at the same time, only the older one keeps running
    BOOL alreadyRunning = NO;
    struct proc_bsdinfo me, other;
    if (proc_pidinfo(getpid(), PROC_PIDTBSDINFO, 0, &me, sizeof(me)) == sizeof(me)) {
        for (NSRunningApplication *app in [NSRunningApplication runningApplicationsWithBundleIdentifier:OPENKEY_BUNDLE]) {
            if (app.processIdentifier == me.pbi_pid || app.terminated)
                continue;
            if (proc_pidinfo(app.processIdentifier, PROC_PIDTBSDINFO, 0, &other, sizeof(other)) != sizeof(other) || other.pbi_uid != me.pbi_uid)
                continue;
            if (startedBefore(&other, &me)) {
                alreadyRunning = YES;
                break;
            }
        }
    }

    if (alreadyRunning) {
        VKLog(@"app", @"another ViKey is running: quit");
        [NSApp terminate:nil];
        return;
    }
    
    // check if user granted Accessabilty permission
    if (!MJAccessibilityIsEnabled()) {
        VKLog(@"app", @"no Accessibility permission: show the welcome window");
        [self showWelcome];
        return;
    }
    [self startViKey];
}

-(void)startViKey {
    if (_started)
        return;
    _started = YES;
    [self askToQuitOpenKey];
    
    vShowIconOnDock = (int)[[NSUserDefaults standardUserDefaults] integerForKey:@"vShowIconOnDock"];
    if (vShowIconOnDock)
        [NSApp setActivationPolicy: NSApplicationActivationPolicyRegular];
    
    if (vSwitchKeyStatus & 0x8000)
        NSBeep();

    [self createStatusBarMenu];
    [self startSecureInputCheck];
    
    //init
    dispatch_async(dispatch_get_main_queue(), ^{
        if (![OpenKeyManager initEventTap]) {
            [self askToRelaunch];
        } else {
            //the engine has loaded the macros: the synced file can change them now
            [[MacroSync shared] start];
            NSInteger showui = [[NSUserDefaults standardUserDefaults] integerForKey:@"ShowUIOnStartup"];
            if (showui == 1) {
                [self onControlPanelSelected];
            }
        }
        [self setQuickConvertString];
    });
    
    //load default config if is first launch
    if ([[NSUserDefaults standardUserDefaults] boolForKey:@"NonFirstTime"] == 0) {
        [self loadDefaultConfig];
    }
    [[NSUserDefaults standardUserDefaults] setInteger:1 forKey:@"NonFirstTime"];
    
    //check update if enable
    NSInteger dontCheckUpdate = [[NSUserDefaults standardUserDefaults] integerForKey:@"DontCheckUpdate"];
    if (!dontCheckUpdate)
        [OpenKeyManager checkNewVersion:nil callbackFunc:nil];
    
    //correct run on startup
    NSInteger val = [[NSUserDefaults standardUserDefaults] integerForKey:@"RunOnStartup"];
    [appDelegate setRunOnStartup:val];
}

- (BOOL)applicationShouldHandleReopen:(NSApplication *)sender hasVisibleWindows:(BOOL)flag {
    if (_started)
        [self onControlPanelSelected];
    else
        [self showWelcome];
    return YES;
}

- (void)applicationWillTerminate:(NSNotification *)aNotification {
    [[MacroSync shared] flushPendingWrite];
}

-(void) createStatusBarMenu {
    NSStatusBar *statusBar = [NSStatusBar systemStatusBar];
    statusItem = [statusBar statusItemWithLength:NSVariableStatusItemLength];
    statusItem.button.image = [NSImage imageNamed:@"Status"];
    statusItem.button.alternateImage = [NSImage imageNamed:@"StatusHighlighted"];
    
    theMenu = [[NSMenu alloc] initWithTitle:@""];
    [theMenu setAutoenablesItems:NO];
    
    //only shown while Secure Input blocks typing
    mnuSecureInput = [theMenu addItemWithTitle:@"" action:@selector(onSecureInputSelected) keyEquivalent:@""];
    if (@available(macOS 11.0, *)) {
        mnuSecureInput.image = [NSImage imageWithSystemSymbolName:@"lock.fill" accessibilityDescription:nil];
    }
    mnuSecureInput.hidden = YES;
    mnuSecureInputSeparator = [NSMenuItem separatorItem];
    mnuSecureInputSeparator.hidden = YES;
    [theMenu addItem:mnuSecureInputSeparator];

    menuInputMethod = [theMenu addItemWithTitle:@"Bật Tiếng Việt"
                                                     action:@selector(onInputMethodSelected)
                                              keyEquivalent:@""];
    [theMenu addItem:[NSMenuItem separatorItem]];
    NSMenuItem* menuInputType = [theMenu addItemWithTitle:@"Kiểu gõ" action:nil keyEquivalent:@""];
    
    [theMenu addItem:[NSMenuItem separatorItem]];
    
    mnuUnicode = [theMenu addItemWithTitle:@"Unicode dựng sẵn" action:@selector(onCodeSelected:) keyEquivalent:@""];
    mnuUnicode.tag = 0;
    mnuTCVN = [theMenu addItemWithTitle:@"TCVN3 (ABC)" action:@selector(onCodeSelected:) keyEquivalent:@""];
    mnuTCVN.tag = 1;
    mnuVNIWindows = [theMenu addItemWithTitle:@"VNI Windows" action:@selector(onCodeSelected:) keyEquivalent:@""];
    mnuVNIWindows.tag = 2;
    NSMenuItem* menuCode = [theMenu addItemWithTitle:@"Bảng mã khác" action:nil keyEquivalent:@""];
    
    [theMenu addItem:[NSMenuItem separatorItem]];
    
    [theMenu addItemWithTitle:@"Công cụ chuyển mã..." action:@selector(onConvertTool) keyEquivalent:@""];
    mnuQuickConvert = [theMenu addItemWithTitle:@"Chuyển mã nhanh" action:@selector(onQuickConvert) keyEquivalent:@""];
    
    [theMenu addItem:[NSMenuItem separatorItem]];
    
    [theMenu addItemWithTitle:@"Cài đặt…" action:@selector(onControlPanelSelected) keyEquivalent:@","];
    [theMenu addItemWithTitle:@"Gõ tắt..." action:@selector(onMacroSelected) keyEquivalent:@""];
    [theMenu addItemWithTitle:@"Chẩn đoán…" action:@selector(onDiagnosticsSelected) keyEquivalent:@""];
    [theMenu addItemWithTitle:@"Giới thiệu" action:@selector(onAboutSelected) keyEquivalent:@""];
    [theMenu addItem:[NSMenuItem separatorItem]];
    
    [theMenu addItemWithTitle:@"Thoát" action:@selector(terminate:) keyEquivalent:@"q"];
    
    
    [self setInputTypeMenu:menuInputType];
    [self setCodeMenu:menuCode];
    
    //set menu
    [statusItem setMenu:theMenu];
    
    [self fillData];
}

-(void)setQuickConvertString {
    NSMutableString* hotKey = [NSMutableString stringWithString:@""];
    bool hasAdd = false;
    if (convertToolHotKey & 0x100) {
        [hotKey appendString:@"⌃"];
        hasAdd = true;
    }
    if (convertToolHotKey & 0x200) {
        if (hasAdd)
            [hotKey appendString:@" + "];
        [hotKey appendString:@"⌥"];
        hasAdd = true;
    }
    if (convertToolHotKey & 0x400) {
        if (hasAdd)
            [hotKey appendString:@" + "];
        [hotKey appendString:@"⌘"];
        hasAdd = true;
    }
    if (convertToolHotKey & 0x800) {
        if (hasAdd)
            [hotKey appendString:@" + "];
        [hotKey appendString:@"⇧"];
        hasAdd = true;
    }
    
    unsigned short k = ((convertToolHotKey>>24) & 0xFF);
    if (k != 0xFE) {
        if (hasAdd)
            [hotKey appendString:@" + "];
        if (k == kVK_Space)
            [hotKey appendFormat:@"%@", @"␣ "];
        else
            [hotKey appendFormat:@"%c", k];
    }
    [mnuQuickConvert setTitle: hasAdd ? [NSString stringWithFormat:@"Chuyển mã nhanh - [%@]", [hotKey uppercaseString]] : @"Chuyển mã nhanh"];
}

-(void)loadDefaultConfig {
    EngineLock();
    vLanguage = 1; [[NSUserDefaults standardUserDefaults] setInteger:vLanguage forKey:@"InputMethod"];
    vInputType = 0; [[NSUserDefaults standardUserDefaults] setInteger:vInputType forKey:@"InputType"];
    vFreeMark = 0; [[NSUserDefaults standardUserDefaults] setInteger:vFreeMark forKey:@"FreeMark"];
    vCheckSpelling = 1; [[NSUserDefaults standardUserDefaults] setInteger:vCheckSpelling forKey:@"Spelling"];
    vCodeTable = 0; [[NSUserDefaults standardUserDefaults] setInteger:vCodeTable forKey:@"CodeTable"];
    vSwitchKeyStatus = DEFAULT_SWITCH_STATUS; [[NSUserDefaults standardUserDefaults] setInteger:vCodeTable forKey:@"SwitchKeyStatus"];
    vQuickTelex = 0; [[NSUserDefaults standardUserDefaults] setInteger:vQuickTelex forKey:@"QuickTelex"];
    vUseModernOrthography = 0; [[NSUserDefaults standardUserDefaults] setInteger:vUseModernOrthography forKey:@"ModernOrthography"];
    vRestoreIfWrongSpelling = 0; [[NSUserDefaults standardUserDefaults] setInteger:vRestoreIfWrongSpelling forKey:@"RestoreIfInvalidWord"];
    vFixRecommendBrowser = 1; [[NSUserDefaults standardUserDefaults] setInteger:vFixRecommendBrowser forKey:@"FixRecommendBrowser"];
    vUseMacro = 1; [[NSUserDefaults standardUserDefaults] setInteger:vUseMacro forKey:@"UseMacro"];
    vUseMacroInEnglishMode = 0; [[NSUserDefaults standardUserDefaults] setInteger:vUseMacroInEnglishMode forKey:@"UseMacroInEnglishMode"];
    vSendKeyStepByStep = 0;[[NSUserDefaults standardUserDefaults] setInteger:vUseMacroInEnglishMode forKey:@"SendKeyStepByStep"];
    vUseSmartSwitchKey = 1;[[NSUserDefaults standardUserDefaults] setInteger:vUseSmartSwitchKey forKey:@"UseSmartSwitchKey"];
    vUpperCaseFirstChar = 0;[[NSUserDefaults standardUserDefaults] setInteger:vUpperCaseFirstChar forKey:@"UpperCaseFirstChar"];
    vTempOffSpelling = 0;[[NSUserDefaults standardUserDefaults] setInteger:vTempOffSpelling forKey:@"vTempOffSpelling"];
    vAllowConsonantZFWJ = 0;[[NSUserDefaults standardUserDefaults] setInteger:vAllowConsonantZFWJ forKey:@"vAllowConsonantZFWJ"];
    vQuickStartConsonant = 0;[[NSUserDefaults standardUserDefaults] setInteger:vQuickStartConsonant forKey:@"vQuickStartConsonant"];
    vQuickEndConsonant = 0;[[NSUserDefaults standardUserDefaults] setInteger:vQuickEndConsonant forKey:@"vQuickEndConsonant"];
    vRememberCode = 1;[[NSUserDefaults standardUserDefaults] setInteger:vRememberCode forKey:@"vRememberCode"];
    vOtherLanguage = 1;[[NSUserDefaults standardUserDefaults] setInteger:vOtherLanguage forKey:@"vOtherLanguage"];
    vTempOffOpenKey = 0;[[NSUserDefaults standardUserDefaults] setInteger:vTempOffOpenKey forKey:@"vTempOffOpenKey"];
    vShowIconOnDock = 0;[[NSUserDefaults standardUserDefaults] setInteger:vShowIconOnDock forKey:@"vShowIconOnDock"];
    vFixChromiumBrowser = 0;[[NSUserDefaults standardUserDefaults] setInteger:vFixChromiumBrowser forKey:@"vFixChromiumBrowser"];
    vPerformLayoutCompat = 0;[[NSUserDefaults standardUserDefaults] setInteger:vPerformLayoutCompat forKey:@"vPerformLayoutCompat"];

    [[NSUserDefaults standardUserDefaults] setInteger:1 forKey:@"GrayIcon"];
    [[NSUserDefaults standardUserDefaults] setInteger:1 forKey:@"RunOnStartup"];
    EngineUnlock();

    [self fillData];
}

-(void)setRunOnStartup:(BOOL)val {
    //OpenKey itself is the login item, no helper app needed
    SMAppService* service = [SMAppService mainAppService];
    NSError* error = nil;
    if (val && (service.status == SMAppServiceStatusNotRegistered || service.status == SMAppServiceStatusNotFound)) {
        //"requires approval" means the user turned it off in System Settings: do not register again
        [service registerAndReturnError:&error];
    } else if (!val && service.status != SMAppServiceStatusNotRegistered) {
        [service unregisterAndReturnError:&error];
    }
    if (error)
        NSLog(@"ViKey: can not change login item: %@", error);
}

-(void)setGrayIcon:(BOOL)val {
    [self fillData];
}

-(void)showIconOnDock:(BOOL)val {
    [NSApp setActivationPolicy: val ? NSApplicationActivationPolicyRegular : NSApplicationActivationPolicyAccessory];
}

#pragma mark -StatusBar menu data

- (void)setInputTypeMenu:(NSMenuItem*) parent {
    //sub for Kieu Go
    NSMenu *sub = [[NSMenu alloc] initWithTitle:@""];
    [sub setAutoenablesItems:NO];
    mnuTelex = [sub addItemWithTitle:@"Telex" action:@selector(onInputTypeSelected:) keyEquivalent:@""];
    mnuTelex.tag = 0;
    mnuVNI = [sub addItemWithTitle:@"VNI" action:@selector(onInputTypeSelected:) keyEquivalent:@""];
    mnuVNI.tag = 1;
    mnuSimpleTelex1 = [sub addItemWithTitle:@"Simple Telex 1" action:@selector(onInputTypeSelected:) keyEquivalent:@""];
    mnuSimpleTelex1.tag = 2;
    mnuSimpleTelex2 = [sub addItemWithTitle:@"Simple Telex 2" action:@selector(onInputTypeSelected:) keyEquivalent:@""];
    mnuSimpleTelex2.tag = 3;
    [theMenu setSubmenu:sub forItem:parent];
}

- (void)setCodeMenu:(NSMenuItem*) parent {
    //sub for Code
    NSMenu *sub = [[NSMenu alloc] initWithTitle:@""];
    [sub setAutoenablesItems:NO];
    mnuUnicodeComposite = [sub addItemWithTitle:@"Unicode tổ hợp" action:@selector(onCodeSelected:) keyEquivalent:@""];
    mnuUnicodeComposite.tag = 3;
    mnuVietnameseLocaleCP1258 = [sub addItemWithTitle:@"Vietnamese Locale CP 1258" action:@selector(onCodeSelected:) keyEquivalent:@""];
    mnuVietnameseLocaleCP1258.tag = 4;
    
    [theMenu setSubmenu:sub forItem:parent];
}

- (void) fillData {
    //the keyboard thread also changes the mode: it saves it first (see SaveModeAndRefreshMenu), then this reads it
    EngineLock();
    //fill data
    NSInteger intInputMethod = [[NSUserDefaults standardUserDefaults] integerForKey:@"InputMethod"];
    [menuInputMethod setState:(intInputMethod == 1 ? NSControlStateValueOn : NSControlStateValueOff)];
    vLanguage = (int)intInputMethod;
    [self updateStatusIcon];
    
    NSInteger intInputType = [[NSUserDefaults standardUserDefaults] integerForKey:@"InputType"];
    [mnuTelex setState:NSControlStateValueOff];
    [mnuVNI setState:NSControlStateValueOff];
    [mnuSimpleTelex1 setState:NSControlStateValueOff];
    [mnuSimpleTelex2 setState:NSControlStateValueOff];
    if (intInputType == 0) {
        [mnuTelex setState:NSControlStateValueOn];
    } else if (intInputType == 1) {
        [mnuVNI setState:NSControlStateValueOn];
    } else if (intInputType == 2) {
        [mnuSimpleTelex1 setState:NSControlStateValueOn];
    } else if (intInputType == 3) {
        [mnuSimpleTelex2 setState:NSControlStateValueOn];
    }
    vInputType = (int)intInputType;
    
    NSInteger intSwitchKeyStatus = [[NSUserDefaults standardUserDefaults] integerForKey:@"SwitchKeyStatus"];
    vSwitchKeyStatus = (int)intSwitchKeyStatus;
    if (vSwitchKeyStatus == 0)
        vSwitchKeyStatus = DEFAULT_SWITCH_STATUS;
    
    NSInteger intCode = [[NSUserDefaults standardUserDefaults] integerForKey:@"CodeTable"];
    [mnuUnicode setState:NSControlStateValueOff];
    [mnuTCVN setState:NSControlStateValueOff];
    [mnuVNIWindows setState:NSControlStateValueOff];
    [mnuUnicodeComposite setState:NSControlStateValueOff];
    [mnuVietnameseLocaleCP1258 setState:NSControlStateValueOff];
    if (intCode == 0) {
        [mnuUnicode setState:NSControlStateValueOn];
    } else if (intCode == 1) {
        [mnuTCVN setState:NSControlStateValueOn];
    } else if (intCode == 2) {
        [mnuVNIWindows setState:NSControlStateValueOn];
    } else if (intCode == 3) {
        [mnuUnicodeComposite setState:NSControlStateValueOn];
    } else if (intCode == 4) {
        [mnuVietnameseLocaleCP1258 setState:NSControlStateValueOn];
    }
    vCodeTable = (int)intCode;
    EngineUnlock();
    
    //
    NSInteger intRunOnStartup = [[NSUserDefaults standardUserDefaults] integerForKey:@"RunOnStartup"];
    [self setRunOnStartup:intRunOnStartup ? YES : NO];

    //refresh the settings window
    [[NSNotificationCenter defaultCenter] postNotificationName:SettingsWindowController.settingsDidChangeNotification object:nil];
}

-(void)updateStatusIcon {
    //Secure Input blocks typing: show a lock until it is turned off
    if (_secureInputOn) {
        if (@available(macOS 11.0, *)) {
            statusItem.button.image = [NSImage imageWithSystemSymbolName:@"lock.fill" accessibilityDescription:@"Secure Input"];
            statusItem.button.alternateImage = nil;
            return;
        }
    }
    NSInteger grayIcon = [[NSUserDefaults standardUserDefaults] integerForKey:@"GrayIcon"];
    //apps which always use English show the English icon
    if (vLanguage == 1 && !IsExcludedAppActive()) {
        statusItem.button.image = [NSImage imageNamed:@"Status"];
        [statusItem.button.image setTemplate:(grayIcon ? YES : NO)];
        statusItem.button.alternateImage = [NSImage imageNamed:@"StatusHighlighted"];
    } else {
        statusItem.button.image = [NSImage imageNamed:@"StatusEng"];
        [statusItem.button.image setTemplate:(grayIcon ? YES : NO)];
        statusItem.button.alternateImage = [NSImage imageNamed:@"StatusHighlightedEng"];
    }
}

-(void)onImputMethodChanged:(BOOL)willNotify {
    EngineLock();
    NSInteger intInputMethod = [[NSUserDefaults standardUserDefaults] integerForKey:@"InputMethod"];
    if (intInputMethod == 0)
        intInputMethod = 1;
    else
        intInputMethod = 0;
    vLanguage = (int)intInputMethod;
    [[NSUserDefaults standardUserDefaults] setInteger:intInputMethod forKey:@"InputMethod"];
    EngineUnlock();

    [self fillData];
    
    if (willNotify)
        OnInputMethodChanged();
    VKLog(@"mode", @"%@ from the menu", intInputMethod ? @"Vietnamese" : @"English");
}

#pragma mark -StatusBar menu action
- (void)onInputMethodSelected {
    [self onImputMethodChanged:YES];
}

- (void)onInputTypeSelected:(id)sender {
    NSMenuItem *menuItem = (NSMenuItem*) sender;
    [self onInputTypeSelectedIndex:(int)menuItem.tag];
}

- (void)onInputTypeSelectedIndex:(int)index {
    EngineLock();
    [[NSUserDefaults standardUserDefaults] setInteger:index forKey:@"InputType"];
    vInputType = index;
    EngineUnlock();
    [self fillData];
}

- (void)onCodeTableChanged:(int)index {
    //the macros must use the new code table before the next key
    EngineLock();
    [[NSUserDefaults standardUserDefaults] setInteger:index forKey:@"CodeTable"];
    vCodeTable = index;
    OnTableCodeChange();
    EngineUnlock();
    [self fillData];
}

- (void)onCodeSelected:(id)sender {
    NSMenuItem *menuItem = (NSMenuItem*) sender;
    [self onCodeTableChanged:(int)menuItem.tag];
}

-(void)onConvertTool {
    if (_convertWC == nil) {
        _convertWC = [[ConvertToolWindowController alloc] init];
    }
    [_convertWC show];
}

-(void)onQuickConvert {
    if ([OpenKeyManager quickConvert]) {
        if (!convertToolDontAlertWhenCompleted) {
            [OpenKeyManager showMessage: nil message:@"Chuyển mã thành công!" subMsg:@"Kết quả đã được lưu trong clipboard."];
        }
    } else {
        [OpenKeyManager showMessage: nil message:@"Không có dữ liệu trong clipboard!" subMsg:@"Hãy sao chép một đoạn text để chuyển đổi!"];
    }
}

-(SettingsWindowController*) settingsWindowController {
    if (_settingsWC == nil) {
        _settingsWC = [[SettingsWindowController alloc] init];
    }
    return _settingsWC;
}

-(void) onControlPanelSelected {
    [[self settingsWindowController] show];
}

-(void) onMacroSelected {
    if (_macroWC == nil) {
        _macroWC = [[MacroWindowController alloc] init];
    }
    [_macroWC show];
}

-(void) onAboutSelected {
    [[self settingsWindowController] showWithTab:SettingsWindowController.aboutTab];
}

-(void) onDiagnosticsSelected {
    if (_diagnosticsWC == nil) {
        _diagnosticsWC = [[DiagnosticsWindowController alloc] init];
    }
    [_diagnosticsWC show];
}

#pragma mark -Secure Input
//While an app turns on Secure Input (password field, Terminal "Secure Keyboard Entry",...),
//macOS does not send keys to any input method, so OpenKey can not type. Tell the user why.
-(void)startSecureInputCheck {
    if (@available(macOS 10.14, *)) {
        [UNUserNotificationCenter currentNotificationCenter].delegate = self;
    }
    //there is no notification for Secure Input changes, so check it often (it is a cheap call)
    NSTimer* timer = [NSTimer timerWithTimeInterval:1.0 target:self selector:@selector(checkSecureInput) userInfo:nil repeats:YES];
    timer.tolerance = 0.5;
    [[NSRunLoop mainRunLoop] addTimer:timer forMode:NSRunLoopCommonModes];
    [self checkSecureInput];
}

-(void)checkSecureInput {
    BOOL on = IsSecureEventInputEnabled();
    pid_t pid = 0;
    if (on) {
        NSDictionary* session = CFBridgingRelease(CGSessionCopyCurrentDictionary());
        pid = [[session objectForKey:@"kCGSSessionSecureInputPID"] intValue];
    }

    if (on != _secureInputOn || pid != _secureInputPID) {
        _secureInputOn = on;
        _secureInputPID = pid;
        _secureInputSince = [NSDate date];
        _secureInputNotified = NO;

        NSString* appName = [self secureInputAppName];
        VKLog(@"secure-input", @"%@%@", on ? @"on" : @"off", on && appName ? [NSString stringWithFormat:@" by %@ (pid %d)", appName, pid] : @"");
        mnuSecureInput.title = appName ? [NSString stringWithFormat:@"Không gõ được: %@ đang bật Secure Input", appName]
                                       : @"Không gõ được: Secure Input đang bật";
        mnuSecureInput.hidden = !on;
        mnuSecureInputSeparator.hidden = !on;
        statusItem.button.toolTip = on ? mnuSecureInput.title : nil;
        [self updateStatusIcon];

        if (!on) {
            if (@available(macOS 10.14, *)) {
                [[UNUserNotificationCenter currentNotificationCenter] removeDeliveredNotificationsWithIdentifiers:@[SECURE_INPUT_NOTIFICATION]];
            }
        }
    }

    //notify only in Vietnamese mode: in English mode typing still works
    if (on && !_secureInputNotified && vLanguage == 1 &&
        -[_secureInputSince timeIntervalSinceNow] >= SECURE_INPUT_NOTIFY_DELAY) {
        _secureInputNotified = YES;
        [self notifySecureInput];
    }
}

//nil when Secure Input is off
-(NSString*)secureInputStatus {
    if (!_secureInputOn)
        return nil;
    NSString* appName = [self secureInputAppName];
    return appName ? [NSString stringWithFormat:@"%@ (pid %d)", appName, _secureInputPID] : @"?";
}

//name of the app which turns on Secure Input, nil if unknown
-(NSString*)secureInputAppName {
    if (_secureInputPID <= 0)
        return nil;
    NSString* name = [NSRunningApplication runningApplicationWithProcessIdentifier:_secureInputPID].localizedName;
    if (name.length > 0)
        return name;
    //not a normal app, such as loginwindow
    char procName[256];
    if (proc_name(_secureInputPID, procName, sizeof(procName)) > 0)
        return [NSString stringWithUTF8String:procName];
    return nil;
}

-(void)notifySecureInput {
    if (@available(macOS 10.14, *)) {
        NSString* appName = [self secureInputAppName];
        UNUserNotificationCenter* center = [UNUserNotificationCenter currentNotificationCenter];
        [center requestAuthorizationWithOptions:UNAuthorizationOptionAlert completionHandler:^(BOOL granted, NSError* error) {
            if (!granted)
                return;
            UNMutableNotificationContent* content = [[UNMutableNotificationContent alloc] init];
            content.title = @"ViKey không gõ được tiếng Việt";
            content.body = appName ? [NSString stringWithFormat:@"%@ đang bật Secure Input. Bấm để xem cách khắc phục.", appName]
                                   : @"Secure Input đang bật. Bấm để xem cách khắc phục.";
            UNNotificationRequest* request = [UNNotificationRequest requestWithIdentifier:SECURE_INPUT_NOTIFICATION content:content trigger:nil];
            [center addNotificationRequest:request withCompletionHandler:nil];
        }];
    }
}

-(void)onSecureInputSelected {
    if (!_secureInputOn)
        return;
    NSString* appName = [self secureInputAppName];
    NSRunningApplication* app = _secureInputPID > 0 ? [NSRunningApplication runningApplicationWithProcessIdentifier:_secureInputPID] : nil;

    NSAlert *alert = [[NSAlert alloc] init];
    [alert setMessageText:appName ? [NSString stringWithFormat:@"%@ đang bật Secure Input", appName] : @"Secure Input đang bật"];
    [alert setInformativeText:@"Khi Secure Input bật, macOS không gửi phím cho bộ gõ, nên ViKey tạm thời không gõ được tiếng Việt. "
                              @"Đây là tính năng bảo mật của macOS, thường bật khi bạn nhập mật khẩu.\n\n"
                              @"Cách khắc phục:\n"
                              @"• Rời khỏi ô mật khẩu, hoặc chuyển sang ứng dụng khác.\n"
                              @"• Terminal, iTerm: tắt \"Secure Keyboard Entry\" trong menu của ứng dụng.\n"
                              @"• Nếu vẫn bị (nhất là với loginwindow): khoá màn hình rồi mở khoá lại."];
    [alert addButtonWithTitle:@"OK"];
    BOOL canOpenApp = app != nil && app.activationPolicy == NSApplicationActivationPolicyRegular;
    if (canOpenApp)
        [alert addButtonWithTitle:[NSString stringWithFormat:@"Mở %@", appName]];

    [alert.window makeKeyAndOrderFront:nil];
    [alert.window setLevel:NSStatusWindowLevel];
    if ([alert runModal] == NSAlertSecondButtonReturn && canOpenApp)
        [app activateWithOptions:0];
}

//show the banner even when OpenKey is the active app
-(void)userNotificationCenter:(UNUserNotificationCenter *)center willPresentNotification:(UNNotification *)notification
        withCompletionHandler:(void (^)(UNNotificationPresentationOptions))completionHandler API_AVAILABLE(macos(10.14)) {
    if (@available(macOS 11.0, *)) {
        completionHandler(UNNotificationPresentationOptionBanner | UNNotificationPresentationOptionList);
    } else {
        completionHandler(UNNotificationPresentationOptionNone);
    }
}

-(void)userNotificationCenter:(UNUserNotificationCenter *)center didReceiveNotificationResponse:(UNNotificationResponse *)response
        withCompletionHandler:(void (^)(void))completionHandler API_AVAILABLE(macos(10.14)) {
    if ([response.notification.request.identifier isEqualToString:SECURE_INPUT_NOTIFICATION]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self onSecureInputSelected];
        });
    }
    completionHandler();
}

#pragma mark -Short key event
-(void)onSwitchLanguage {
    [self onInputMethodSelected];
}

#pragma mark Reset OpenKey after mac computer awake
-(void)receiveWakeNote: (NSNotification*)note {
    VKLog(@"app", @"Mac woke up");
    [OpenKeyManager initEventTap];
}

-(void)receiveSleepNote: (NSNotification*)note {
    VKLog(@"app", @"Mac goes to sleep");
    [OpenKeyManager stopEventTap];
}

-(void)receiveActiveSpaceChanged: (NSNotification*)note {
    RequestNewSession();
}

-(void)activeAppChanged: (NSNotification*)note {
    //the typing app changes too: it applies its remembered mode (smart switch) and the "always English" list
    OnFrontAppChanged();
    [self updateStatusIcon];
}

-(void)registerSupportedNotification {
    [[[NSWorkspace sharedWorkspace] notificationCenter] addObserver: self
                                                           selector: @selector(receiveWakeNote:)
                                                               name: NSWorkspaceDidWakeNotification object: NULL];
    
    [[[NSWorkspace sharedWorkspace] notificationCenter] addObserver: self
                                                           selector: @selector(receiveSleepNote:)
                                                               name: NSWorkspaceWillSleepNotification object: NULL];
    
    [[[NSWorkspace sharedWorkspace] notificationCenter] addObserver: self
                                                           selector: @selector(receiveActiveSpaceChanged:)
                                                               name: NSWorkspaceActiveSpaceDidChangeNotification object: NULL];
    
    [[[NSWorkspace sharedWorkspace] notificationCenter] addObserver: self
                                                           selector: @selector(activeAppChanged:)
                                                               name: NSWorkspaceDidActivateApplicationNotification object: NULL];
}
@end
