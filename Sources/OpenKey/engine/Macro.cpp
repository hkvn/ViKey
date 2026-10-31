//
//  Macro.cpp
//  OpenKey
//
//  Created by Tuyen on 8/4/19.
//  Copyright © 2019 Tuyen Mai. All rights reserved.
//

#include "Macro.h"
#include "Vietnamese.h"
#include "Engine.h"
#include <iostream>
#include <memory.h>
#include <ctime>

using namespace std;

//main data
map<vector<Uint32>, MacroData> macroMap;

extern int vCodeTable;
//local variable
static int c = 0;
static bool _macroFlag = false;
static Uint16 _kChar = 0;
static Uint32 _charBuff;
static int _kMacro;

string (*macroClipboardText)() = nullptr;

static const char* _dynamicValueNames[] = {"{date}", "{time}", "{weekday}", "{day}", "{month}", "{year}", "{clipboard}"};
static const char* _weekdays[] = {"Chủ Nhật", "Thứ Hai", "Thứ Ba", "Thứ Tư", "Thứ Năm", "Thứ Sáu", "Thứ Bảy"};

#define MAX_MACRO_TEXT_SIZE 255 //the saved data keeps the text size in one byte
#define MAX_MACRO_CONTENT_SIZE 65535 //and the content size in two bytes
#define MAX_MACRO_COUNT 65535 //and the number of macros in two bytes

//positions of the content of the last macro found which come from a dynamic value: auto caps does not change them
static vector<bool> _valuePositions;

static bool hasDynamicValue(const string& content) {
    for (const char* name : _dynamicValueNames) {
        if (content.find(name) != string::npos)
            return true;
    }
    return false;
}

static string dynamicValue(const string& name, const struct tm& now, bool& known) {
    char buff[32];
    known = true;
    if (name == "{date}") {
        snprintf(buff, sizeof(buff), "%02d/%02d/%04d", now.tm_mday, now.tm_mon + 1, now.tm_year + 1900);
    } else if (name == "{time}") {
        snprintf(buff, sizeof(buff), "%02d:%02d", now.tm_hour, now.tm_min);
    } else if (name == "{weekday}") {
        return _weekdays[now.tm_wday];
    } else if (name == "{day}") {
        snprintf(buff, sizeof(buff), "%d", now.tm_mday);
    } else if (name == "{month}") {
        snprintf(buff, sizeof(buff), "%d", now.tm_mon + 1);
    } else if (name == "{year}") {
        snprintf(buff, sizeof(buff), "%d", now.tm_year + 1900);
    } else if (name == "{clipboard}") {
        return macroClipboardText != nullptr ? macroClipboardText() : "";
    } else {
        known = false;
        return "";
    }
    return buff;
}

//the content cut into fixed text and filled dynamic values (isValue)
static void splitDynamicValues(const string& content, vector<pair<string, bool>>& parts) {
    parts.clear();
    time_t time = std::time(nullptr);
    struct tm now;
    localtime_r(&time, &now);
    string text;
    size_t i = 0, end;
    bool known;
    while (i < content.size()) {
        if (content[i] == '{' && (end = content.find('}', i)) != string::npos) {
            string value = dynamicValue(content.substr(i, end - i + 1), now, known);
            if (known) {
                if (!text.empty())
                    parts.push_back(make_pair(text, false));
                text.clear();
                parts.push_back(make_pair(value, true));
                i = end + 1;
                continue;
            }
        }
        text += content[i++];
    }
    if (!text.empty())
        parts.push_back(make_pair(text, false));
}

string fillMacroDynamicValues(const string& content) {
    if (!hasDynamicValue(content))
        return content;
    vector<pair<string, bool>> parts;
    splitDynamicValues(content, parts);
    string result;
    for (const pair<string, bool>& part : parts)
        result += part.first;
    return result;
}

static void convert(const string& str, vector<Uint32>& outData) {
    outData.clear();
    wstring data = utf8ToWideString(str);
    Uint32 t = 0;
    int kSign = -1;
    int k = 0;
    for (int i = 0; i < data.size(); i++) {
        t = (Uint32)data[i];
        
        //find normal character fist
        if (_characterMap.find(t) != _characterMap.end()) {
            outData.push_back(_characterMap[t]);
            continue;
        }
        
        //find character which has tone/mark
        for (map<Uint32, vector<Uint16>>::iterator it = _codeTable[0].begin(); it != _codeTable[0].end(); ++it) {
            kSign = -1;
            k = 0;
            for (int j = 0; j < it->second.size(); j++) {
                if ((Uint16)t == it->second[j]) {
                    kSign = 0;
                    outData.push_back(_codeTable[vCodeTable][it->first][k] | CHAR_CODE_MASK);
                    break;
                }//end if
                k++;
            }
            if (kSign != -1)
                break;
        }
        if (kSign != -1)
            continue;
        
        //find other character
        outData.push_back(t | PURE_CHARACTER_MASK); //mark it as pure character
    }
}

/**
 * data structure:
 * byte 0 and 1: macro count
 *
 * byte n: macroText size (macroTextSize)
 * byte n + macroTextSize: macroText data
 *
 * byte m, m+1: macroContentSize
 * byte m+1 + macroContentSize: macroContent data
 *
 * ...
 * next macro
 */
void initMacroMap(const Byte* pData, const int& size) {
    macroMap.clear();
    if (pData == NULL || size < 2)
        return;
    Uint16 macroCount = 0;
    memcpy(&macroCount, pData, 2);
    size_t cursor = 2, total = (size_t)size;
    Uint8 macroTextSize;
    Uint16 macroContentSize;
    for (int i = 0; i < macroCount; i++) {
        //the saved data can be broken: never read after its end
        if (cursor + 1 > total)
            break;
        macroTextSize = pData[cursor++];
        if (cursor + macroTextSize + 2 > total)
            break;
        string macroText((char*)pData + cursor, macroTextSize);
        cursor += macroTextSize;
        
        memcpy(&macroContentSize, pData + cursor, 2);
        cursor+=2;
        if (cursor + macroContentSize > total)
            break;
        string macroContent((char*)pData + cursor, macroContentSize);
        cursor += macroContentSize;
        
        MacroData data;
        data.macroText = macroText;
        data.macroContent = macroContent;
        data.hasDynamicValue = hasDynamicValue(macroContent);
        
        vector<Uint32> key;
        convert(macroText, key);
        convert(macroContent, data.macroContentCode);
        
        macroMap[key] = data;
    }
}

void getMacroSaveData(vector<Byte>& outData) {
    //addMacro keeps the sizes in the limits of this format
    Uint16 totalMacro = (Uint16)min(macroMap.size(), (size_t)MAX_MACRO_COUNT);
    outData.push_back((Byte)totalMacro);
    outData.push_back((Byte)(totalMacro>>8));
    
    int saved = 0;
    for (std::map<vector<Uint32>, MacroData>::iterator it = macroMap.begin(); it != macroMap.end() && saved < totalMacro; ++it, ++saved) {
        outData.push_back((Byte)it->second.macroText.size());
        for (int j = 0; j < it->second.macroText.size(); j++) {
            outData.push_back(it->second.macroText[j]);
        }
        
        Uint16 macroContentSize = (Uint16)it->second.macroContent.size();
        outData.push_back((Byte)macroContentSize);
        outData.push_back(macroContentSize>>8);
        for (int j = 0; j < macroContentSize; j++) {
            outData.push_back(it->second.macroContent[j]);
        }
    }
}

static bool modifyCaseUnicode(Uint32& code, const bool& isUpperCase=true) {
    _charBuff = code;
    if (!(code & CHAR_CODE_MASK)) { //for normal char
        if (isUpperCase)
            code |= CAPS_MASK;
        else
            code &= ~CAPS_MASK;
        return code != _charBuff;
    }
    
    //for unicode character
    for (map<Uint32, vector<Uint16>>::iterator it = _codeTable[vCodeTable].begin(); it != _codeTable[vCodeTable].end(); ++it) {
        for (_kMacro = 0; _kMacro < it->second.size(); _kMacro++) {
            if ((Uint16)code == it->second[_kMacro]) {
                if (_kMacro % 2 == 0 && !isUpperCase)
                    _kMacro++;
                else if (_kMacro % 2 != 0 && isUpperCase)
                    _kMacro--;
                code = _codeTable[vCodeTable][it->first][_kMacro] | CHAR_CODE_MASK;
                return code != _charBuff;;
            }//end if
        }
    }
    return false;
}

//content to type: dynamic values are filled now
static void getContentCode(const MacroData& data, vector<Uint32>& macroContentCode) {
    _valuePositions.clear();
    if (!data.hasDynamicValue) {
        macroContentCode = data.macroContentCode;
        return;
    }
    macroContentCode.clear();
    vector<pair<string, bool>> parts;
    splitDynamicValues(data.macroContent, parts);
    vector<Uint32> code;
    for (const pair<string, bool>& part : parts) {
        convert(part.first, code);
        macroContentCode.insert(macroContentCode.end(), code.begin(), code.end());
        _valuePositions.insert(_valuePositions.end(), code.size(), part.second);
    }
}

bool findMacro(vector<Uint32>& key, vector<Uint32>& macroContentCode) {
    for (c = 0; c < key.size(); c++) {
        key[c] = getCharacterCode(key[c]);
    }
    if (macroMap.find(key) != macroMap.end()) {
        getContentCode(macroMap[key], macroContentCode);
        return true;
    }
    if (vAutoCapsMacro) {
        _macroFlag = false;
        if (key.size() > 1 && modifyCaseUnicode(key[1], false)) {
            _macroFlag = true;
            for (c = 2; c < key.size(); c++) {
                modifyCaseUnicode(key[c], false);
            }
        }
        
        if (key.size() > 0 && modifyCaseUnicode(key[0], false)) {
            if (macroMap.find(key) != macroMap.end()) {
                getContentCode(macroMap[key], macroContentCode);
                for (c = 0; c < macroContentCode.size(); c++) {
                    //a dynamic value (clipboard, date,...) is typed as it is
                    if (c < _valuePositions.size() && _valuePositions[c])
                        continue;
                    if (c == 0 || _macroFlag) {
                        _kChar = keyCodeToCharacter(macroContentCode[c]);
                        if (_kChar != 0) {
                            _kChar = toupper(_kChar);
                            macroContentCode[c] = _characterMap[_kChar];
                            continue;
                        }
                        if (macroContentCode[c] & CHAR_CODE_MASK) {
                            modifyCaseUnicode(macroContentCode[c]);
                        }
                    }
                }
                return true;
            }
        }
    }
    return false;
}

bool hasMacro(const string& macroName) {
    vector<Uint32> key;
    convert(macroName, key);
    return (macroMap.find(key) != macroMap.end());
}

void getAllMacro(vector<vector<Uint32>>& keys, vector<string>& macroTexts, vector<string>& macroContents) {
    keys.clear();
    macroTexts.clear();
    macroContents.clear();
    for (std::map<vector<Uint32>, MacroData>::iterator it = macroMap.begin(); it != macroMap.end(); ++it) {
        keys.push_back(it->first);
        macroTexts.push_back(it->second.macroText);
        macroContents.push_back(it->second.macroContent);
    }
}

bool addMacro(const string& macroText, const string& macroContent) {
    //the limits of the saved data
    if (macroText.empty() || macroText.size() > MAX_MACRO_TEXT_SIZE || macroContent.size() > MAX_MACRO_CONTENT_SIZE)
        return false;
    vector<Uint32> key;
    convert(macroText, key);
    if (macroMap.find(key) == macroMap.end()) { //add new macro
        if (macroMap.size() >= MAX_MACRO_COUNT)
            return false;
        MacroData data;
        data.macroText = macroText;
        data.macroContent = macroContent;
        data.hasDynamicValue = hasDynamicValue(macroContent);
        convert(macroContent, data.macroContentCode);
        macroMap[key] = data;
    } else { //edit this macro
        macroMap[key].macroContent = macroContent;
        macroMap[key].hasDynamicValue = hasDynamicValue(macroContent);
        convert(macroContent, macroMap[key].macroContentCode);
    }
    return true;
}

bool deleteMacro(const string& macroText) {
    vector<Uint32> key;
    convert(macroText, key);
    if (macroMap.find(key) != macroMap.end()) {
        macroMap.erase(key);
        return true;
    }
    return false;
}

void onTableCodeChange() {
    //the keys depend on the code table too, see findMacro
    map<vector<Uint32>, MacroData> rebuilt;
    for (std::map<vector<Uint32>, MacroData>::iterator it = macroMap.begin(); it != macroMap.end(); ++it) {
        MacroData data = it->second;
        vector<Uint32> key;
        convert(data.macroText, key);
        convert(data.macroContent, data.macroContentCode);
        rebuilt[key] = data;
    }
    macroMap.swap(rebuilt);
}

bool macrosUseClipboard() {
    for (std::map<vector<Uint32>, MacroData>::iterator it = macroMap.begin(); it != macroMap.end(); ++it) {
        if (it->second.hasDynamicValue && it->second.macroContent.find("{clipboard}") != string::npos)
            return true;
    }
    return false;
}
