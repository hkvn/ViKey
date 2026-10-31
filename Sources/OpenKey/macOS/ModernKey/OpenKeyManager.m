//
//  OpenKeyManager.m
//  OpenKey
//
//  Created by Tuyen on 1/27/19.
//  Copyright © 2019 Tuyen Mai. All rights reserved.
//

#import "OpenKeyManager.h"

extern void OpenKeyInit(void);

extern CGEventRef OpenKeyCallback(CGEventTapProxy proxy,
                                  CGEventType type,
                                  CGEventRef event,
                                  void *refcon);

extern NSString* ConvertUtil(NSString* str);

@interface OpenKeyManager ()

@end

@implementation OpenKeyManager {

}
static BOOL _isInited = NO;

static CFMachPortRef      eventTap;
static CGEventMask        eventMask;
static CFRunLoopSourceRef runLoopSource;

+(BOOL)isInited {
    return _isInited;
}

+(BOOL)initEventTap {
    if (_isInited)
        return true;
    
    //init modernKey
    OpenKeyInit();
    
    // Create an event tap. We are interested in key presses.
    // Mouse down starts a new word; mouse drags are not needed and would wake the app very often
    eventMask = ((1 << kCGEventKeyDown) |
                 (1 << kCGEventKeyUp) |
                 (1 << kCGEventFlagsChanged) |
                 (1 << kCGEventLeftMouseDown) |
                 (1 << kCGEventRightMouseDown));
    
    eventTap = CGEventTapCreate(kCGSessionEventTap,
                                kCGHeadInsertEventTap,
                                0,
                                eventMask,
                                OpenKeyCallback,
                                NULL);
    
    if (!eventTap) {
        
        fprintf(stderr, "failed to create event tap\n");
        return NO;
    }
    
    _isInited = YES;
    
    // Create a run loop source.
    runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0);
    
    // Add to the current run loop.
    CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, kCFRunLoopCommonModes);
    
    // Enable the event tap.
    CGEventTapEnable(eventTap, true);
    
    return YES;
}

+(BOOL)stopEventTap {
    if (_isInited) { //release all object
        CFRunLoopRemoveSource(CFRunLoopGetCurrent(), runLoopSource, kCFRunLoopCommonModes);
        CFRelease(runLoopSource);
        runLoopSource = nil;
        
        CFMachPortInvalidate(eventTap);
        CFRelease(eventTap);
        eventTap = nil;
        
        _isInited = false;
    }
    return YES;
}

+(void)reEnableEventTap {
    if (_isInited)
        CGEventTapEnable(eventTap, true);
}

+(NSArray*)getTableCodes {
    return [[NSArray alloc] initWithObjects:
            @"Unicode",
            @"TCVN3 (ABC)",
            @"VNI Windows",
            @"Unicode tổ hợp",
            @"Vietnamese Locale CP 1258", nil];
}

+(NSString*)getBuildDate {
    return [NSString stringWithUTF8String:__DATE__];
}

#pragma mark -Convert feature
+(BOOL)quickConvert {
    NSPasteboard *pasteboard = [NSPasteboard generalPasteboard];
    NSString *htmlString = [pasteboard stringForType:NSPasteboardTypeHTML];
    NSString *rawString = [pasteboard stringForType:NSPasteboardTypeString];
    bool converted = false;
    if (htmlString != nil) {
        htmlString = ConvertUtil(htmlString);
        converted = true;
    }
    if (rawString != nil) {
        rawString = ConvertUtil(rawString);
        converted = true;
    }
    if (converted) {
        [pasteboard clearContents];
        if (htmlString != nil)
            [pasteboard setString:htmlString forType:NSPasteboardTypeHTML];
        if (rawString != nil)
            [pasteboard setString:rawString forType:NSPasteboardTypeString];
        
        return YES;
    }
    return NO;
}

+(void)showMessage:(NSWindow*)window message:(NSString*)msg subMsg:(NSString*)subMsg {
    NSAlert *alert = [[NSAlert alloc] init];
    [alert setMessageText:msg];
    [alert setInformativeText:subMsg];
    [alert addButtonWithTitle:@"OK"];
    if (window) {
        [alert beginSheetModalForWindow:window completionHandler:^(NSModalResponse returnCode) {
        }];
    } else {
        [alert runModal];
    }
}

#pragma mark -AutoUpdate feature

#define RELEASES_PAGE @"https://github.com/hkvn/ViKey/releases/latest"

//callback is nil when checking on startup: then only a newer version is shown
+(void)checkNewVersion:(NSWindow*)parent callbackFunc:(CheckNewVersionCallback) callback {
    //latest published release on GitHub (drafts and pre-releases are not included)
    NSMutableURLRequest* request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:@"https://api.github.com/repos/hkvn/ViKey/releases/latest"]];
    [request setValue:@"application/vnd.github+json" forHTTPHeaderField:@"Accept"];
    [[[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        NSDictionary* release = nil;
        if (((NSHTTPURLResponse *)response).statusCode == 200 && data) {
            id object = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
            if ([object isKindOfClass:[NSDictionary class]])
                release = object;
        }
        NSString* latestVersion = [release[@"tag_name"] isKindOfClass:[NSString class]] ? release[@"tag_name"] : nil;
        if ([latestVersion hasPrefix:@"v"])
            latestVersion = [latestVersion substringFromIndex:1];
        NSString* pageURL = [release[@"html_url"] isKindOfClass:[NSString class]] ? release[@"html_url"] : RELEASES_PAGE;

        dispatch_async(dispatch_get_main_queue(), ^{
            if (callback != nil) {
                callback();
            }
            if (latestVersion == nil) {
                if (callback != nil)
                    [self showMessage:parent message:@"Không kiểm tra được bản mới!" subMsg:@"Không kết nối được GitHub, hoặc chưa có bản phát hành nào. Hãy thử lại sau."];
                return;
            }
            NSString* currentVersion = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
            BOOL needUpdating = [latestVersion compare:currentVersion options:NSNumericSearch] == NSOrderedDescending;
            if (needUpdating || callback != nil) {
                [self showUpdateMessage:parent needUpdating:needUpdating newVersion:latestVersion currentVersion:currentVersion pageURL:pageURL];
            }
        });
    }] resume];
}

+(void)showUpdateMessage:(NSWindow*)parent needUpdating:(BOOL)needUpdating newVersion:(NSString*)versionString
          currentVersion:(NSString*)currentVersion pageURL:(NSString*)pageURL {
    NSAlert *alert = [[NSAlert alloc] init];
    [alert setMessageText:(needUpdating ? [NSString stringWithFormat:@"ViKey có phiên bản mới (%@)", versionString] : @"Bạn đang dùng phiên bản mới nhất!")];
    [alert setInformativeText:(needUpdating ? [NSString stringWithFormat:@"Bạn đang dùng phiên bản %@. Bấm 'Tải về' để mở trang tải bản mới.", currentVersion] : @"")];

    if (!needUpdating) {
        [alert addButtonWithTitle:@"OK"];
    } else {
        [alert addButtonWithTitle:@"Tải về"];
        [alert addButtonWithTitle:@"Để sau"];
    }
    void (^handler)(NSModalResponse) = ^(NSModalResponse returnCode) {
        if (returnCode == NSAlertFirstButtonReturn && needUpdating) {
            [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:pageURL]];
        }
    };
    if (parent == nil) {
        [alert.window makeKeyAndOrderFront:nil];
        [alert.window setLevel:NSStatusWindowLevel];
        handler([alert runModal]);
    } else {
        [alert beginSheetModalForWindow:parent completionHandler:handler];
    }
}
@end
