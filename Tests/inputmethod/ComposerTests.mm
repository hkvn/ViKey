//
//  ComposerTests.mm
//  ViKey
//
//  Tests for the word building of the input method: what the user would see in the app.
//  Run with scripts/run-tests.sh
//

#import <Foundation/Foundation.h>
#import "Composer.h"
#include "Engine.h"
#include <map>

static int failures = 0;
static int checks = 0;

static void check(const char* name, BOOL ok) {
    checks++;
    if (!ok) {
        failures++;
        printf("FAIL  %s\n", name);
    }
}

static void checkEqual(const char* name, NSString* actual, NSString* expected) {
    checks++;
    if (![actual isEqualToString:expected]) {
        failures++;
        printf("FAIL  %s: got \"%s\", expected \"%s\"\n", name, actual.UTF8String, expected.UTF8String);
    }
}

static const std::map<unichar, UInt16> keyCodes = {
    {'a', KEY_A}, {'b', KEY_B}, {'c', KEY_C}, {'d', KEY_D}, {'e', KEY_E}, {'f', KEY_F}, {'g', KEY_G}, {'h', KEY_H},
    {'i', KEY_I}, {'j', KEY_J}, {'k', KEY_K}, {'l', KEY_L}, {'m', KEY_M}, {'n', KEY_N}, {'o', KEY_O}, {'p', KEY_P},
    {'q', KEY_Q}, {'r', KEY_R}, {'s', KEY_S}, {'t', KEY_T}, {'u', KEY_U}, {'v', KEY_V}, {'w', KEY_W}, {'x', KEY_X},
    {'y', KEY_Y}, {'z', KEY_Z}, {' ', KEY_SPACE}, {'.', KEY_DOT}, {',', KEY_COMMA},
    {'<', KEY_DELETE}, //"<" stands for the Delete key
};

/// types the keys like a user; the document gets the finished words and the keys which the app gets
static NSString* type(VKComposer* composer, NSString* keys, NSMutableString* document) {
    for (NSUInteger i = 0; i < keys.length; i++) {
        unichar key = [keys characterAtIndex:i];
        unichar lower = key >= 'A' && key <= 'Z' ? key + 32 : key;
        NSString* characters = [NSString stringWithCharacters:&key length:1];
        BOOL handled = [composer handleKeyCode:keyCodes.at(lower) characters:characters shift:key != lower capsLock:NO otherModifiers:NO];
        if (composer.finishedWord != nil)
            [document appendString:VKWordText(composer.finishedWord)];
        if (!handled) {
            if (key == '<') {
                if (document.length > 0)
                    [document deleteCharactersInRange:NSMakeRange(document.length - 1, 1)];
            } else {
                [document appendString:characters];
            }
        }
    }
    return [document stringByAppendingString:VKWordText(composer.word)];
}

static NSString* type(NSString* keys) {
    VKComposer* composer = [[VKComposer alloc] init];
    return type(composer, keys, [NSMutableString string]);
}

static void setUp() {
    vInputType = 0;
    vCodeTable = 0;
    vCheckSpelling = 1;
    vUseModernOrthography = 1;
    vUseMacro = 0;
    vSetCheckSpelling();
}

int main() {
    @autoreleasepool {
        setUp();
        VKComposer* composer = [[VKComposer alloc] init];
        NSMutableString* document = [NSMutableString string];
        type(composer, @"tieengs", document);
        checkEqual("word while typing", VKWordText(composer.word), @"tiếng");
        check("nothing written yet", document.length == 0);
        type(composer, @" ", document);
        checkEqual("space writes the word, then the app gets the space", document, @"tiếng ");
        check("new word after space", composer.word.count == 0);

        checkEqual("sentence", type(@"tieengs Vieetj "), @"tiếng Việt ");
        checkEqual("delete in the word", type(@"tieengs<"), @"tiến");
        checkEqual("delete removes a whole character", type(@"tieengs<<<"), @"ti");
        checkEqual("delete after the word goes to the app", type(@"ab <<"), @"a");
        checkEqual("delete then type again", type(@"vieetj<t"), @"việt");
        checkEqual("dot is part of the word", type(@"a.b "), @"a.b ");
        checkEqual("w alone is ư in Telex", type(@"windows"), @"ưindows");
        vRestoreIfWrongSpelling = 1;
        checkEqual("restore an English word", type(@"windows "), @"windows ");
        vRestoreIfWrongSpelling = 0;

        //shortcuts and arrows end the word
        composer = [[VKComposer alloc] init];
        document = [NSMutableString string];
        type(composer, @"dduowcj", document);
        BOOL handled = [composer handleKeyCode:KEY_A characters:@"a" shift:NO capsLock:NO otherModifiers:YES];
        check("shortcut goes to the app", !handled);
        checkEqual("shortcut finishes the word", VKWordText(composer.finishedWord), @"được");
        check("finishWord on an empty word", [composer finishWord].count == 0);
        type(composer, @"as", document);
        checkEqual("finishWord returns the word", VKWordText([composer finishWord]), @"á");

        //Unicode compound: one character is a letter and a combining mark
        vCodeTable = 3;
        composer = [[VKComposer alloc] init];
        document = [NSMutableString string];
        type(composer, @"as", document);
        check("compound character is one item", composer.word.count == 1 && composer.word.firstObject.length == 2);
        checkEqual("compound text", VKWordText(composer.word), @"á");
        type(composer, @"<", document);
        check("delete removes the letter and its mark", composer.word.count == 0);
        vCodeTable = 0;

        //macro
        vUseMacro = 1;
        initMacroMap(nullptr, 0);
        addMacro("vk", "ViKey");
        checkEqual("macro", type(@"vk "), @"ViKey ");
        addMacro("hn", "Hà Nội");
        checkEqual("macro with Vietnamese", type(@"hn "), @"Hà Nội ");
        vUseMacro = 0;

        printf("input method: %d checks, %d failures\n", checks, failures);
    }
    return failures == 0 ? 0 : 1;
}
