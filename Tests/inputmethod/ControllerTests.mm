//
//  ControllerTests.mm
//  ViKey
//
//  Drives the input controller of the input method with a fake text field, in direct and marked text mode.
//  Run with scripts/run-tests.sh
//
#import <Cocoa/Cocoa.h>
#import <InputMethodKit/InputMethodKit.h>
#include "Engine.h"
#include <map>
#import <objc/runtime.h>

//IMK checks that the client is a real proxy: skip its own code in the test
static id fakeInit(id self, SEL _cmd, id server, id delegate, id client) { return self; }
static void fakeServer(id self, SEL _cmd, id client) {}
static void skipIMKSetup() {
    Class imk = [IMKInputController class];
    method_setImplementation(class_getInstanceMethod(imk, @selector(initWithServer:delegate:client:)), (IMP)fakeInit);
    method_setImplementation(class_getInstanceMethod(imk, @selector(activateServer:)), (IMP)fakeServer);
    method_setImplementation(class_getInstanceMethod(imk, @selector(deactivateServer:)), (IMP)fakeServer);
}

@interface FakeClient : NSObject
@property NSMutableString* text;
@property NSRange selection, marked;
@property BOOL knowsCursor;
@property NSString* bundleIdentifier;
@end
@implementation FakeClient
-(instancetype)init { if (self = [super init]) { _text = [NSMutableString string]; _selection = NSMakeRange(0, 0); _marked = NSMakeRange(NSNotFound, 0); _knowsCursor = YES; _bundleIdentifier = @"com.example.test"; } return self; }
-(NSRange)selectedRange { return _knowsCursor ? _selection : NSMakeRange(NSNotFound, 0); }
-(NSRange)markedRange { return _marked; }
-(NSAttributedString*)attributedSubstringFromRange:(NSRange)range {
    if (!_knowsCursor || NSMaxRange(range) > _text.length) return nil;
    return [[NSAttributedString alloc] initWithString:[_text substringWithRange:range]];
}
-(NSRange)target:(NSRange)replacement {
    if (replacement.location != NSNotFound) return replacement;
    return _marked.location != NSNotFound ? _marked : _selection;
}
-(void)insertText:(id)string replacementRange:(NSRange)replacement {
    NSString* s = [string isKindOfClass:[NSAttributedString class]] ? [string string] : string;
    NSRange target = [self target:replacement];
    [_text replaceCharactersInRange:target withString:s];
    _selection = NSMakeRange(target.location + s.length, 0);
    _marked = NSMakeRange(NSNotFound, 0);
}
-(void)setMarkedText:(id)string selectionRange:(NSRange)selection replacementRange:(NSRange)replacement {
    NSString* s = [string isKindOfClass:[NSAttributedString class]] ? [string string] : string;
    NSRange target = [self target:replacement];
    [_text replaceCharactersInRange:target withString:s];
    _marked = s.length > 0 ? NSMakeRange(target.location, s.length) : NSMakeRange(NSNotFound, 0);
    _selection = NSMakeRange(target.location + selection.location, selection.length);
}
//the app handles a key the input method did not use
-(void)appKey:(unichar)key {
    if (key == '<') {
        if (_selection.location > 0) { [_text deleteCharactersInRange:NSMakeRange(_selection.location - 1, 1)]; _selection.location--; }
    } else {
        [_text replaceCharactersInRange:_selection withString:[NSString stringWithCharacters:&key length:1]];
        _selection = NSMakeRange(_selection.location + 1, 0);
    }
}
@end

static const std::map<unichar, UInt16> keyCodes = {
    {'a', KEY_A}, {'b', KEY_B}, {'c', KEY_C}, {'d', KEY_D}, {'e', KEY_E}, {'f', KEY_F}, {'g', KEY_G}, {'h', KEY_H},
    {'i', KEY_I}, {'j', KEY_J}, {'k', KEY_K}, {'l', KEY_L}, {'m', KEY_M}, {'n', KEY_N}, {'o', KEY_O}, {'p', KEY_P},
    {'q', KEY_Q}, {'r', KEY_R}, {'s', KEY_S}, {'t', KEY_T}, {'u', KEY_U}, {'v', KEY_V}, {'w', KEY_W}, {'x', KEY_X},
    {'y', KEY_Y}, {'z', KEY_Z}, {' ', KEY_SPACE}, {'<', KEY_DELETE}, {'.', KEY_DOT},
};
static int failures = 0;
static void type(IMKInputController* controller, FakeClient* client, NSString* keys) {
    for (NSUInteger i = 0; i < keys.length; i++) {
        unichar key = [keys characterAtIndex:i];
        unichar lower = key >= 'A' && key <= 'Z' ? key + 32 : key;
        NSString* chars = [NSString stringWithCharacters:&key length:1];
        NSEvent* event = [NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint modifierFlags:key != lower ? NSEventModifierFlagShift : 0
                                         timestamp:0 windowNumber:0 context:nil characters:chars charactersIgnoringModifiers:chars isARepeat:NO keyCode:keyCodes.at(lower)];
        if (![controller handleEvent:event client:client])
            [client appKey:key];
    }
}
static void check(const char* name, BOOL ok) {
    if (ok)
        return;
    failures++;
    printf("FAIL  %s\n", name);
}

static void expect(const char* name, FakeClient* client, NSString* text) {
    if ([client.text isEqualToString:text])
        return;
    failures++;
    printf("FAIL  %s: got \"%s\", expected \"%s\"\n", name, client.text.UTF8String, text.UTF8String);
}
static IMKInputController* start(FakeClient* client, BOOL marked) {
    [[NSUserDefaults standardUserDefaults] setObject:marked ? @[client.bundleIdentifier] : @[] forKey:@"MarkedTextApps"];
    IMKInputController* controller = [[NSClassFromString(@"ViKeyInputController") alloc] initWithServer:nil delegate:nil client:client];
    [controller activateServer:client];
    //the same options for every run, whatever the user chose in ViKey
    vLanguage = 1; vInputType = 0; vCodeTable = 0; vCheckSpelling = 1; vSetCheckSpelling(); vUseModernOrthography = 1; vQuickTelex = 0;
    vRestoreIfWrongSpelling = 0; vUseMacro = 1; vUpperCaseFirstChar = 0; vQuickStartConsonant = 0; vQuickEndConsonant = 0;
    initMacroMap(nullptr, 0); addMacro("vk", "ViKey");
    return controller;
}

int main() {
    @autoreleasepool {
        skipIMKSetup();
        for (int marked = 0; marked <= 1; marked++) {
            FakeClient* client = [[FakeClient alloc] init];
            IMKInputController* controller = start(client, marked);
            type(controller, client, @"tieengs");
            expect("while typing", client, @"tiếng");
            type(controller, client, @" Vieetj ");
            expect("two words", client, @"tiếng Việt ");
            type(controller, client, @"ddaayf<<");
            expect("delete in a word", client, @"tiếng Việt đ");
            type(controller, client, @"aay ");
            expect("type again", client, @"tiếng Việt đây ");
            type(controller, client, @"vk ");
            expect("macro", client, @"tiếng Việt đây ViKey ");
            //the user clicks before the first word, the input method does not see it
            client.selection = NSMakeRange(0, 0);
            type(controller, client, @"aa");
            expect("cursor moved: the new word goes there", client, @"âtiếng Việt đây ViKey ");
            [controller commitComposition:client];
            expect("commit", client, @"âtiếng Việt đây ViKey ");
            [controller deactivateServer:client];
        }
        //an app which does not tell where the cursor is: marked text
        FakeClient* client = [[FakeClient alloc] init];
        client.knowsCursor = NO;
        IMKInputController* controller = start(client, NO);
        type(controller, client, @"tieengs Vieetj");
        expect("falls back to marked text", client, @"tiếng Việt");
        check("marked text is used", client.marked.location != NSNotFound);
        [controller commitComposition:client];
        expect("commit", client, @"tiếng Việt");

        //terminals: marked text, even when they give a cursor position
        client = [[FakeClient alloc] init];
        client.bundleIdentifier = @"com.mitchellh.ghostty";
        controller = start(client, NO);
        type(controller, client, @"tieengs");
        expect("terminal", client, @"tiếng");
        check("terminal uses marked text", client.marked.location != NSNotFound);
    }
    [[NSUserDefaults standardUserDefaults] removePersistentDomainForName:[[NSBundle mainBundle] bundleIdentifier] ?: @"inputmethod-controller-tests"];
    printf("input controller: %d failures\n", failures);
    return failures ? 1 : 0;
}
