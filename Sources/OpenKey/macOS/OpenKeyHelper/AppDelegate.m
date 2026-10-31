//
//  AppDelegate.m
//  OpenKeyHelper
//
//  Created by Tuyen on 2/1/19.
//  Copyright © 2019 Tuyen Mai. All rights reserved.
//

#import "AppDelegate.h"
#include <libproc.h>
#include <sys/proc_info.h>

#define OPENKEY_BUNDLE @"com.hkvn.vikey"

@interface AppDelegate ()

@property (weak) IBOutlet NSWindow *window;
@end

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
    //Check if OpenKey is running for current user (multi-user/Fast User Switching support)
    uid_t currentUID = getuid();
    BOOL isRunning = NO;

    for (NSRunningApplication *app in [NSRunningApplication runningApplicationsWithBundleIdentifier:OPENKEY_BUNDLE]) {
        struct proc_bsdinfo proc;
        int size = proc_pidinfo(app.processIdentifier, PROC_PIDTBSDINFO, 0, &proc, sizeof(proc));
        if (!app.terminated && size == sizeof(proc) && proc.pbi_uid == currentUID) {
            isRunning = YES;
            break;
        }
    }

    if (!isRunning) {
        NSString* path = [[NSBundle mainBundle] bundlePath];
        for (int i = 0; i < 4; i++)
            path = [path stringByDeletingLastPathComponent];
        [[NSWorkspace sharedWorkspace] launchApplication:path];
    }

    //job done, dont stay in background
    [NSApp terminate:nil];
}


- (void)applicationWillTerminate:(NSNotification *)aNotification {
    // Insert code here to tear down your application
}


@end
