//
//  Composer.mm
//  ViKey input method
//

#import "Composer.h"
#include "Engine.h"

NSString* VKWordText(NSArray<NSString*>* word) {
    return [word componentsJoinedByString:@""];
}

//text of one engine character in the current code table, like SendNewCharString() of the event tap
static NSString* characterText(Uint32 data) {
    unichar chars[2];
    NSUInteger length = 1;
    if (data & PURE_CHARACTER_MASK) {
        chars[0] = (unichar)data;
    } else if (!(data & CHAR_CODE_MASK)) {
        chars[0] = keyCodeToCharacter(data);
    } else if (vCodeTable == 0) { //Unicode
        chars[0] = (unichar)data;
    } else if (vCodeTable == 1 || vCodeTable == 2 || vCodeTable == 4) { //one byte code tables, some characters have a second byte
        unichar value = (unichar)data;
        chars[0] = LOBYTE(value);
        if (HIBYTE(value) > 32)
            chars[length++] = HIBYTE(value);
    } else { //Unicode compound: a letter and a combining mark
        unichar value = (unichar)data;
        chars[0] = value & 0x1FFF;
        if ((value >> 13) > 0)
            chars[length++] = _unicodeCompoundMark[(value >> 13) - 1];
    }
    return chars[0] != 0 ? [NSString stringWithCharacters:chars length:length] : nil;
}

@implementation VKComposer {
    vKeyHookState* _state;
    NSMutableArray<NSString*>* _word;
}

-(instancetype)init {
    if (self = [super init]) {
        _state = (vKeyHookState*)vKeyInit();
        _word = [NSMutableArray array];
    }
    return self;
}

-(NSArray<NSString*>*)word {
    return [_word copy];
}

-(BOOL)handleKeyCode:(UInt16)keyCode characters:(NSString*)characters shift:(BOOL)shift capsLock:(BOOL)capsLock
      otherModifiers:(BOOL)otherModifiers {
    _finishedWord = nil;
    _extraDeleteCount = 0;
    //shortcuts, arrows, function keys: the app gets them, the word ends
    if (otherModifiers) {
        [self endWordAndResetEngine];
        return NO;
    }
    vKeyHandleEvent(vKeyEvent::Keyboard, vKeyEventState::KeyDown, keyCode, shift ? 1 : (capsLock ? 2 : 0), false);
    switch (_state->code) {
        case vDoNothing:
            if (_state->extCode == 2) { //delete
                if (_word.count == 0) {
                    //the app deletes text written before: the engine must not edit that word again
                    [self resetEngine];
                    return NO;
                }
                [_word removeLastObject];
                return YES;
            }
            //a character of the word, as the keyboard layout gives it. The engine does not set extCode for Space
            if (keyCode != KEY_SPACE && _state->extCode == 3 && characters.length > 0) {
                [_word addObject:characters];
                return YES;
            }
            [self endWord]; //space, return, tab,...
            return NO;
        case vWillProcess:
            [self applyEngineOutput];
            return YES;
        case vRestore: { //not a Vietnamese word: the keys as typed
            [self applyEngineOutput];
            unichar typed = keyCodeToCharacter(keyCode | (shift || capsLock ? CAPS_MASK : 0));
            if (typed == 0) {
                [self endWord];
                return NO;
            }
            [_word addObject:[NSString stringWithCharacters:&typed length:1]];
            return YES;
        }
        case vRestoreAndStartNewSession:
            [self applyEngineOutput];
            [self endWord];
            return NO;
        case vReplaceMaro:
            [self deleteLast:_state->backspaceCount];
            for (Uint32 data : _state->macroData) {
                NSString* text = characterText(data);
                if (text != nil)
                    [_word addObject:text];
            }
            [self endWord];
            return NO;
    }
    return NO;
}

-(NSArray<NSString*>*)finishWord {
    NSArray<NSString*>* word = [_word copy];
    [_word removeAllObjects];
    [self resetEngine];
    return word;
}

#pragma mark - Helpers

-(void)applyEngineOutput {
    if (_state->backspaceCount < MAX_BUFF)
        [self deleteLast:_state->backspaceCount];
    if (_state->newCharCount > MAX_BUFF)
        return;
    //charData holds the new characters from the last one to the first one
    for (int i = _state->newCharCount - 1; i >= 0; i--) {
        NSString* text = characterText(_state->charData[i]);
        if (text != nil)
            [_word addObject:text];
    }
}

-(void)deleteLast:(NSInteger)count {
    NSInteger fromWord = MIN(count, (NSInteger)_word.count);
    [_word removeObjectsInRange:NSMakeRange(_word.count - fromWord, fromWord)];
    _extraDeleteCount += count - fromWord;
}

-(void)endWord {
    if (_word.count > 0)
        _finishedWord = [_word copy];
    [_word removeAllObjects];
    startNewSession();
}

-(void)endWordAndResetEngine {
    [self endWord];
    [self resetEngine];
}

//like a mouse click for the event tap: the engine forgets the words before
-(void)resetEngine {
    vKeyHandleEvent(vKeyEvent::Mouse, vKeyEventState::MouseDown, 0);
    startNewSession();
}
@end
