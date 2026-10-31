//
//  OpenKeyManager.m
//  OpenKey
//
//  Created by Tuyen on 1/27/19.
//  Copyright © 2019 Tuyen Mai. All rights reserved.
//

#import "OpenKeyManager.h"
#import "Logging.h"

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
static CFRunLoopRef       tapRunLoop;

+(BOOL)isInited {
    return _isInited;
}

+(BOOL)isEventTapEnabled {
    return _isInited && CGEventTapIsEnabled(eventTap);
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
        VKLog(@"tap", @"can not create the event tap (Accessibility permission: %@)", AXIsProcessTrusted() ? @"yes" : @"no");
        return NO;
    }
    
    _isInited = YES;
    
    // Create a run loop source.
    runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0);
    
    // Read the keys on a thread of their own: when the main thread is busy (a window opens, an alert is shown,...)
    // typing does not wait, and macOS does not turn the tap off because it answers too slowly
    dispatch_semaphore_t started = dispatch_semaphore_create(0);
    CFRunLoopSourceRef source = runLoopSource;
    CFMachPortRef tap = eventTap;
    NSThread* thread = [[NSThread alloc] initWithBlock:^{
        tapRunLoop = (CFRunLoopRef)CFRetain(CFRunLoopGetCurrent());
        CFRunLoopAddSource(tapRunLoop, source, kCFRunLoopCommonModes);
        CGEventTapEnable(tap, true);
        dispatch_semaphore_signal(started);
        //until stopEventTap removes the tap
        CFRunLoopRun();
    }];
    thread.name = @"ViKey keyboard";
    thread.qualityOfService = NSQualityOfServiceUserInteractive;
    [thread start];
    dispatch_semaphore_wait(started, DISPATCH_TIME_FOREVER);
    VKLog(@"tap", @"event tap started");
    
    return YES;
}

//never call it while holding the engine lock: it waits for the keyboard thread
+(BOOL)stopEventTap {
    if (_isInited) { //release all object
        //remove the tap on its own thread, between two events
        dispatch_semaphore_t stopped = dispatch_semaphore_create(0);
        CFRunLoopRef runLoop = tapRunLoop;
        CFRunLoopSourceRef source = runLoopSource;
        CFMachPortRef tap = eventTap;
        CFRunLoopPerformBlock(runLoop, kCFRunLoopCommonModes, ^{
            CGEventTapEnable(tap, false);
            CFRunLoopRemoveSource(runLoop, source, kCFRunLoopCommonModes);
            CFMachPortInvalidate(tap);
            CFRunLoopStop(runLoop);
            dispatch_semaphore_signal(stopped);
        });
        CFRunLoopWakeUp(runLoop);
        if (dispatch_semaphore_wait(stopped, dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC)) == 0) {
            CFRelease(source);
            CFRelease(tap);
            CFRelease(runLoop);
            VKLog(@"tap", @"event tap stopped");
        } else {
            //the keyboard thread may still use them: keep them
            VKLog(@"tap", @"the keyboard thread did not stop in time");
        }
        runLoopSource = nil;
        eventTap = nil;
        tapRunLoop = nil;
        
        _isInited = false;
    }
    return YES;
}

//called on the keyboard thread
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
                VKLog(@"update", @"update check failed (HTTP %ld, %@)", (long)((NSHTTPURLResponse *)response).statusCode,
                      error.localizedDescription ?: @"no error");
                if (callback != nil)
                    [self showMessage:parent message:@"Không kiểm tra được bản mới!" subMsg:@"Không kết nối được GitHub, hoặc chưa có bản phát hành nào. Hãy thử lại sau."];
                return;
            }
            NSString* currentVersion = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
            BOOL needUpdating = [latestVersion compare:currentVersion options:NSNumericSearch] == NSOrderedDescending;
            VKLog(@"update", @"latest version %@, current %@", latestVersion, currentVersion);
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
