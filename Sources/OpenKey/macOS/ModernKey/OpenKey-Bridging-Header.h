//
//  OpenKey-Bridging-Header.h
//  OpenKey
//
//  Objective-C and C symbols used by the Swift settings window.
//

#import "AppDelegate.h"
#import "OpenKeyManager.h"
#import "EngineBridge.h"
#import "MJAccessibilityUtils.h"

//options, see document in Engine.h; defined in AppDelegate.m
extern int vLanguage;
extern int vInputType;
extern int vCodeTable;
extern int vSwitchKeyStatus;
extern int vCheckSpelling;
extern int vUseModernOrthography;
extern int vQuickTelex;
extern int vRestoreIfWrongSpelling;
extern int vFixRecommendBrowser;
extern int vUseMacro;
extern int vUseMacroInEnglishMode;
extern int vAutoCapsMacro;
extern int vUseSmartSwitchKey;
extern int vUpperCaseFirstChar;
extern int vTempOffSpelling;
extern int vAllowConsonantZFWJ;
extern int vQuickStartConsonant;
extern int vQuickEndConsonant;
extern int vRememberCode;
extern int vOtherLanguage;
extern int vTempOffOpenKey;
extern int vShowIconOnDock;
extern int vSendKeyStepByStep;
extern int vFixChromiumBrowser;
extern int vPerformLayoutCompat;

extern AppDelegate* appDelegate;

//defined in OpenKey.mm
void OnSpellCheckingChanged(void);
