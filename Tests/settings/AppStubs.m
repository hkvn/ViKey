//
//  AppStubs.m
//  ViKey
//
//  Stand-ins for the app, so the settings model can be tested alone.
//

#import "OpenKey-Bridging-Header.h"

int vLanguage = 1, vInputType = 0, vFreeMark = 0, vCodeTable = 0, vSwitchKeyStatus = 0, vCheckSpelling = 1, vUseModernOrthography = 1,
    vQuickTelex = 0, vRestoreIfWrongSpelling = 0, vFixRecommendBrowser = 1, vUseMacro = 1, vUseMacroInEnglishMode = 0, vAutoCapsMacro = 0,
    vUseSmartSwitchKey = 1, vUpperCaseFirstChar = 0, vTempOffSpelling = 0, vAllowConsonantZFWJ = 0, vQuickStartConsonant = 0,
    vQuickEndConsonant = 0, vRememberCode = 1, vOtherLanguage = 1, vTempOffOpenKey = 0, vShowIconOnDock = 0, vSendKeyStepByStep = 0,
    vFixChromiumBrowser = 0, vPerformLayoutCompat = 0;

AppDelegate* appDelegate = nil;

void OnSpellCheckingChanged(void) {}
void saveSmartSwitchKeyData(void) {}
void ReloadExcludedApps(void) {}

@implementation AppDelegate
-(void)setRunOnStartup:(BOOL)val {}
-(void)setGrayIcon:(BOOL)val {}
-(void)showIconOnDock:(BOOL)val {}
-(void)onInputMethodSelected {}
-(void)onInputTypeSelectedIndex:(int)index {}
-(void)onCodeTableChanged:(int)index {}
-(void)onMacroSelected {}
-(void)onDiagnosticsSelected {}
-(void)loadDefaultConfig {}
-(void)setQuickConvertString {}
-(void)updateStatusIcon {}
@end

@implementation OpenKeyManager
+(NSArray*)getTableCodes { return @[@"Unicode", @"TCVN3 (ABC)", @"VNI Windows", @"Unicode tổ hợp", @"Vietnamese Locale CP 1258"]; }
+(NSString*)getBuildDate { return @""; }
+(void)checkNewVersion:(NSWindow*)parent callbackFunc:(CheckNewVersionCallback)callback {}
@end
