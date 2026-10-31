//
//  Composer.h
//  ViKey input method
//
//  The word being typed, built from the output of the engine. The engine works like for the event tap:
//  "delete n characters, then type these". The composer applies that to the word, so the input method
//  can show the word as marked text, or write it into the document.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface VKComposer : NSObject
/// the word being typed, one item per engine character (one or two UTF-16 units)
@property (nonatomic, readonly) NSArray<NSString*>* word;
/// the word which the last key finished, or nil. It must be written before the app gets the key
@property (nonatomic, readonly, nullable) NSArray<NSString*>* finishedWord;
/// characters the engine wanted to delete before the word (rare, such as a macro over a word written before)
@property (nonatomic, readonly) NSInteger extraDeleteCount;

/// a key down in Vietnamese mode. YES: the key is used; NO: the app must get the key (after finishedWord is written).
/// otherModifiers: Command, Control, Option, Fn or an arrow key is down
-(BOOL)handleKeyCode:(UInt16)keyCode characters:(NSString*)characters shift:(BOOL)shift capsLock:(BOOL)capsLock
      otherModifiers:(BOOL)otherModifiers;

/// the word ends without a key (focus moved, mouse click, language switched): returns it and starts a new word
-(NSArray<NSString*>*)finishWord;
@end

NSString* VKWordText(NSArray<NSString*>* word);

NS_ASSUME_NONNULL_END
