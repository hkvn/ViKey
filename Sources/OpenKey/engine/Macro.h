//
//  Macro.h
//  OpenKey
//
//  Created by Tuyen on 8/4/19.
//  Copyright © 2019 Tuyen Mai. All rights reserved.
//

#ifndef Macro_h
#define Macro_h

#include <vector>
#include <map>
#include <string>
#include "DataType.h"

using namespace std;

struct MacroData {
    string macroText; //ex: "ms"
    string macroContent; //ex: "millisecond"
    vector<Uint32> macroContentCode; //converted of macroContent
    bool hasDynamicValue = false; //content has {date}, {clipboard},...: it is filled each time the macro is typed
};

/**
 * set by the app: the text in the clipboard (UTF-8), for {clipboard}
 */
extern string (*macroClipboardText)();

/**
 * Call when you need to load macro data from disk
 */
void initMacroMap(const Byte* pData, const int& size);

/**
 * convert all macro data to save on disk
 */
void getMacroSaveData(vector<Byte>& outData);

/**
 * Use to find full text by macro
 */
bool findMacro(vector<Uint32>& key, vector<Uint32>& macroContentCode);

/**
 * check has this macro or not
 */
bool hasMacro(const string& macroName);

/**
 * Get all macro to show on macro table
 */
void getAllMacro(vector<vector<Uint32>>& keys, vector<string>& macroTexts, vector<string>& macroContents);

/**
 * add new macro to memory, or change the content of an existing one.
 * false if the text is empty or longer than 255 bytes, the content longer than 65535 bytes, or there are 65535 macros
 */
bool addMacro(const string& macroText, const string& macroContent);

/**
 * delete macro from memory
 */
bool deleteMacro(const string& macroText);

/**
 * When table code changed, we have to call this function to reload all macroContentCode (and the keys)
 */
void onTableCodeChange();

/**
 * a macro has {clipboard}: the app keeps the clipboard text for it
 */
bool macrosUseClipboard();

/**
 * Fill the dynamic values of a macro content:
 * {date} 31/10/2026, {time} 14:05, {weekday} Thứ Bảy, {day} 31, {month} 10, {year} 2026, {clipboard} the text in the clipboard
 */
string fillMacroDynamicValues(const string& content);

#endif /* Macro_h */
