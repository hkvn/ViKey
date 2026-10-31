//
//  AppDelegate.h
//  ModernKey
//
//  Created by Tuyen on 1/18/19.
//  Copyright © 2019 Tuyen Mai. All rights reserved.
//

#import <Cocoa/Cocoa.h>

#define OPENKEY_BUNDLE @"com.hkvn.vikey"

@interface AppDelegate : NSObject <NSApplicationDelegate>

/// reads the settings into the engine and refreshes the menu
-(void)fillData;
-(void)onImputMethodChanged:(BOOL)willNotify;
-(void)onInputMethodSelected;
-(void)updateStatusIcon;

-(void)onInputTypeSelectedIndex:(int)index;
-(void)onCodeTableChanged:(int)index;

-(void)setRunOnStartup:(BOOL)val;
-(void)loadDefaultConfig;

-(void)setGrayIcon:(BOOL)val;

-(void)onMacroSelected;
-(void)onDiagnosticsSelected;
/// the app which turns on Secure Input, nil when it is off
-(NSString*)secureInputStatus;
-(void)onQuickConvert;
-(void)setQuickConvertString;

-(void)showIconOnDock:(BOOL)val;
@end

