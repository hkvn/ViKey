//
//  main.m
//  ViKey input method
//
//  ViKeyInput --register   adds the input method to the input sources and turns it on (run after installing)
//  ViKeyInput --disable    turns it off
//

#import <Cocoa/Cocoa.h>
#import <Carbon/Carbon.h>
#import <InputMethodKit/InputMethodKit.h>

static IMKServer* server;

static NSArray* inputSources(NSString* bundleId) {
    NSDictionary* filter = @{(__bridge NSString*)kTISPropertyBundleID: bundleId};
    return CFBridgingRelease(TISCreateInputSourceList((__bridge CFDictionaryRef)filter, true));
}

static int registerInputSource(BOOL enable) {
    NSBundle* bundle = [NSBundle mainBundle];
    if (enable) {
        OSStatus status = TISRegisterInputSource((__bridge CFURLRef)bundle.bundleURL);
        if (status != noErr) {
            fprintf(stderr, "TISRegisterInputSource failed: %d\n", (int)status);
            return 1;
        }
    }
    NSArray* sources = inputSources(bundle.bundleIdentifier);
    if (sources.count == 0) {
        fprintf(stderr, "input source %s not found\n", bundle.bundleIdentifier.UTF8String);
        return 1;
    }
    for (id source in sources) {
        OSStatus status = enable ? TISEnableInputSource((__bridge TISInputSourceRef)source)
                                 : TISDisableInputSource((__bridge TISInputSourceRef)source);
        if (status != noErr)
            fprintf(stderr, "%s failed: %d\n", enable ? "TISEnableInputSource" : "TISDisableInputSource", (int)status);
    }
    printf("%s %s\n", bundle.bundleIdentifier.UTF8String, enable ? "registered and enabled" : "disabled");
    return 0;
}

int main(int argc, const char* argv[]) {
    @autoreleasepool {
        if (argc > 1 && strcmp(argv[1], "--register") == 0)
            return registerInputSource(YES);
        if (argc > 1 && strcmp(argv[1], "--disable") == 0)
            return registerInputSource(NO);

        NSBundle* bundle = [NSBundle mainBundle];
        NSString* connection = [bundle objectForInfoDictionaryKey:@"InputMethodConnectionName"];
        server = [[IMKServer alloc] initWithName:connection bundleIdentifier:bundle.bundleIdentifier];
        [[NSApplication sharedApplication] run];
    }
    return 0;
}
