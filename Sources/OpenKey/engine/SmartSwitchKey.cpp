//
//  SmartSwitchKey.cpp
//  OpenKey
//
//  Created by Tuyen on 8/13/19.
//  Copyright © 2019 Tuyen Mai. All rights reserved.
//

#include "SmartSwitchKey.h"
#include <map>
#include <iostream>
#include <memory.h>

//main data, i use `map` because it has O(Log(n))
static map<string, Int8> _smartSwitchKeyData;
static string _cacheKey = ""; //use cache for faster
static Int8 _cacheData = 0; //use cache for faster

void initSmartSwitchKey(const Byte* pData, const int& size) {
    _smartSwitchKeyData.clear();
    _cacheKey = "";
    if (pData == NULL || size < 2) return;
    Uint16 count = 0;
    memcpy(&count, pData, 2);
    size_t cursor = 2, total = (size_t)size;
    Uint8 bundleIdSize;
    Uint8 value;
    for (int i = 0; i < count; i++) {
        //the saved data can be broken: never read after its end
        if (cursor + 1 > total)
            break;
        bundleIdSize = pData[cursor++];
        if (cursor + bundleIdSize + 1 > total)
            break;
        string bundleId((char*)pData + cursor, bundleIdSize);
        cursor += bundleIdSize;
        value = pData[cursor++];
        _smartSwitchKeyData[bundleId] = value;
    }
}

void getSmartSwitchKeySaveData(vector<Byte>& outData) {
    outData.clear();
    Uint16 count = (Uint16)_smartSwitchKeyData.size();
    outData.push_back((Byte)count);
    outData.push_back((Byte)(count>>8));
    
    for (std::map<string, Int8>::iterator it = _smartSwitchKeyData.begin(); it != _smartSwitchKeyData.end(); ++it) {
        //setAppInputMethodStatus keeps the size in one byte
        outData.push_back((Byte)it->first.length());
        for (int j = 0; j < it->first.length(); j++) {
            outData.push_back(it->first[j]);
        }
        outData.push_back(it->second);
    }
}

int getAppInputMethodStatus(const string& bundleId, const int& currentInputMethod) {
    if (_cacheKey.compare(bundleId) == 0) {
        return _cacheData;
    }
    if (_smartSwitchKeyData.find(bundleId) != _smartSwitchKeyData.end()) {
        _cacheKey = bundleId;
        _cacheData = _smartSwitchKeyData[bundleId];
        return _cacheData;
    }
    _cacheKey = bundleId;
    _cacheData = currentInputMethod;
    if (!bundleId.empty() && bundleId.size() <= 255 && _smartSwitchKeyData.size() < 65535)
        _smartSwitchKeyData[bundleId] = _cacheData;
    return -1;
}

int findAppInputMethodStatus(const string& bundleId) {
    map<string, Int8>::iterator it = _smartSwitchKeyData.find(bundleId);
    return it != _smartSwitchKeyData.end() ? it->second : -1;
}

void setAppInputMethodStatus(const string& bundleId, const int& language) {
    //the saved data keeps the size in one byte and the count in two bytes
    if (bundleId.empty() || bundleId.size() > 255 ||
        (_smartSwitchKeyData.size() >= 65535 && _smartSwitchKeyData.find(bundleId) == _smartSwitchKeyData.end()))
        return;
    _smartSwitchKeyData[bundleId] = language;
    _cacheKey = bundleId;
    _cacheData = language;
}

void getAllAppInputMethodStatus(vector<string>& bundleIds, vector<int>& statuses) {
    bundleIds.clear();
    statuses.clear();
    for (std::map<string, Int8>::iterator it = _smartSwitchKeyData.begin(); it != _smartSwitchKeyData.end(); ++it) {
        bundleIds.push_back(it->first);
        statuses.push_back(it->second);
    }
}

void removeAppInputMethodStatus(const string& bundleId) {
    _smartSwitchKeyData.erase(bundleId);
    if (_cacheKey.compare(bundleId) == 0) {
        _cacheKey = "";
    }
}
