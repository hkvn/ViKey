//
//  EngineTests.cpp
//  ViKey
//
//  Tests for the typing engine, the convert tool, macros and the UTF-8 helpers.
//  Run with scripts/run-tests.sh
//

#include "Engine.h"
#include <cstdio>
#include <ctime>
#include <map>

extern int vInputType, vCodeTable, vCheckSpelling, vUseModernOrthography, vUseMacro, vFreeMark;

static int failures = 0;
static int checks = 0;

static void check(const char* name, bool ok) {
    checks++;
    if (!ok) {
        failures++;
        printf("FAIL  %s\n", name);
    }
}

static void checkEqual(const char* name, const string& actual, const string& expected) {
    checks++;
    if (actual != expected) {
        failures++;
        printf("FAIL  %s: got \"%s\", expected \"%s\"\n", name, actual.c_str(), expected.c_str());
    }
}

//MARK: typing helpers
static vKeyHookState* pData;

static const std::map<char, Uint16> keyCodes = {
    {'a', KEY_A}, {'b', KEY_B}, {'c', KEY_C}, {'d', KEY_D}, {'e', KEY_E}, {'f', KEY_F}, {'g', KEY_G}, {'h', KEY_H},
    {'i', KEY_I}, {'j', KEY_J}, {'k', KEY_K}, {'l', KEY_L}, {'m', KEY_M}, {'n', KEY_N}, {'o', KEY_O}, {'p', KEY_P},
    {'q', KEY_Q}, {'r', KEY_R}, {'s', KEY_S}, {'t', KEY_T}, {'u', KEY_U}, {'v', KEY_V}, {'w', KEY_W}, {'x', KEY_X},
    {'y', KEY_Y}, {'z', KEY_Z}, {' ', KEY_SPACE},
    {'0', KEY_0}, {'1', KEY_1}, {'2', KEY_2}, {'3', KEY_3}, {'4', KEY_4}, {'5', KEY_5}, {'6', KEY_6}, {'7', KEY_7},
    {'8', KEY_8}, {'9', KEY_9},
};

/// text of one engine character (Unicode code table)
static void appendCharacter(wstring& out, Uint32 data) {
    if (data & PURE_CHARACTER_MASK)
        out += (wchar_t)(data & 0xFFFF);
    else if (data & CHAR_CODE_MASK)
        out += (wchar_t)(data & 0xFFFF);
    else
        out += (wchar_t)keyCodeToCharacter(data);
}

/// types the keys like a user and returns the text the app would show
static string type(const char* keys) {
    wstring out;
    startNewSession();
    for (const char* p = keys; *p; p++) {
        vKeyHandleEvent(vKeyEvent::Keyboard, vKeyEventState::KeyDown, keyCodes.at(*p));
        if (pData->code == vDoNothing) {
            out += (wchar_t)*p;
            continue;
        }
        for (int i = 0; i < pData->backspaceCount && !out.empty(); i++)
            out.pop_back();
        if (pData->code == vReplaceMaro) {
            for (Uint32 data : pData->macroData)
                appendCharacter(out, data);
            out += (wchar_t)*p;
            continue;
        }
        for (int i = pData->newCharCount - 1; i >= 0; i--)
            appendCharacter(out, pData->charData[i]);
        if (pData->code == vRestore || pData->code == vRestoreAndStartNewSession)
            out += (wchar_t)*p;
    }
    return wideStringToUtf8(out);
}

static void setUp() {
    vInputType = 0;
    vCodeTable = 0;
    vCheckSpelling = 1;
    vUseModernOrthography = 1;
    vUseMacro = 0;
    vFreeMark = 0;
    vSetCheckSpelling();
}

//MARK: tests
static void testTelex() {
    setUp();
    checkEqual("telex tieengs", type("tieengs"), "tiếng");
    checkEqual("telex vieetj", type("vieetj"), "việt");
    checkEqual("telex nguwowif", type("nguwowif"), "người");
    checkEqual("telex dduwowngf", type("dduwowngf"), "đường");
    checkEqual("telex khuyur", type("khuyur"), "khuỷu");
    checkEqual("telex quoocs", type("quoocs"), "quốc");
    checkEqual("telex thuowngf", type("thuowngf"), "thường");
}

static void testSpelling() {
    setUp();
    checkEqual("uych with sac", type("huychs"), "huých");
    checkEqual("uych with nang", type("huychj"), "huỵch");
    //a "c, ch, t" ending only takes sac or nang
    checkEqual("uych with huyen is refused", type("huychf"), "huychf");
    checkEqual("uych with hoi is refused", type("huychr"), "huychr");
    checkEqual("uych with nga is refused", type("huychx"), "huychx");
    checkEqual("ach with huyen is refused", type("achf"), "achf");
    checkEqual("ach with sac", type("achs"), "ách");
}

static void testOrthography() {
    setUp();
    vUseModernOrthography = 1;
    checkEqual("modern orthography hoaf", type("hoaf"), "hoà");
    vUseModernOrthography = 0;
    checkEqual("old orthography hoaf", type("hoaf"), "hòa");
}

static void testVNI() {
    setUp();
    vInputType = 1;
    checkEqual("vni tie6ng1", type("tie6ng1"), "tiếng");
    checkEqual("vni vie6t5", type("vie6t5"), "việt");
    checkEqual("vni d9u7o7ng2", type("d9u7o7ng2"), "đường");
}

static string convert(const char* text, int from, int to) {
    convertToolFromCode = from;
    convertToolToCode = to;
    return convertUtil(text);
}

static void setConvertCase(bool allCaps, bool allLower, bool firstLetter, bool eachWord, bool removeMark) {
    convertToolToAllCaps = allCaps;
    convertToolToAllNonCaps = allLower;
    convertToolToCapsFirstLetter = firstLetter;
    convertToolToCapsEachWord = eachWord;
    convertToolRemoveMark = removeMark;
}

static void testConvertTool() {
    setUp();
    setConvertCase(false, false, false, false, false);
    //the last character of the text needs its own encoding too
    checkEqual("unicode -> vni, accent at end", convert("chà", 0, 2), "cha\xc3\xb8");
    checkEqual("unicode -> compound, accent at end", convert("chà", 0, 3), "cha\xcc\x80");
    checkEqual("unicode -> vni, accent inside", convert("chàx", 0, 2), "cha\xc3\xb8x");

    const char* samples[] = {"chà", "xin chào", "Tiếng Việt có dấu ở cuối: được", "huỵch ạ", "ĐƯỜNG Ữ Ặ"};
    for (int table : {2, 3, 4}) {
        for (const char* text : samples) {
            string name = "round trip unicode -> table " + to_string(table) + " -> unicode: " + text;
            checkEqual(name.c_str(), convert(convert(text, 0, table).c_str(), table, 0), text);
        }
    }
    //TCVN3 has no uppercase letters with marks
    checkEqual("round trip tcvn3 lowercase", convert(convert("tiếng việt được", 0, 1).c_str(), 1, 0), "tiếng việt được");

    const char* text = "Tiếng VIỆT có Dấu. đường ĐƯỜNG";
    setConvertCase(false, false, false, false, false);
    checkEqual("case: no option keeps case", convert(text, 0, 0), "Tiếng VIỆT có Dấu. đường ĐƯỜNG");
    setConvertCase(true, false, false, false, false);
    checkEqual("case: all caps", convert(text, 0, 0), "TIẾNG VIỆT CÓ DẤU. ĐƯỜNG ĐƯỜNG");
    setConvertCase(false, true, false, false, false);
    checkEqual("case: all lower", convert(text, 0, 0), "tiếng việt có dấu. đường đường");
    setConvertCase(false, false, true, false, false);
    checkEqual("case: first letter", convert(text, 0, 0), "Tiếng việt có dấu. Đường đường");
    setConvertCase(false, false, false, true, false);
    checkEqual("case: each word", convert(text, 0, 0), "Tiếng Việt Có Dấu. Đường Đường");
    setConvertCase(false, false, false, false, true);
    checkEqual("remove marks, keep case", convert(text, 0, 0), "Tieng VIET co Dau. duong DUONG");
    setConvertCase(true, false, false, false, true);
    checkEqual("remove marks, all caps", convert(text, 0, 0), "TIENG VIET CO DAU. DUONG DUONG");
    setConvertCase(false, false, false, false, false);
}

static void testUtf8() {
    //characters outside the BMP are kept as UTF-16 surrogate pairs (the app sends UTF-16 to macOS)
    wstring wide = utf8ToWideString("Việt 😀");
    check("utf8 -> wide length", wide.size() == 7);
    check("utf8 -> wide letters", wide.size() == 7 && wide[2] == 0x1EC7 && wide[4] == L' ');
    check("utf8 -> wide surrogate pair", wide.size() == 7 && wide[5] == 0xD83D && wide[6] == 0xDE00);
    checkEqual("wide -> utf8 round trip", wideStringToUtf8(wide), "Việt 😀");
    checkEqual("wide -> utf8 stops at NUL", wideStringToUtf8(wstring(L"ab\0cd", 5)), "ab");
    check("utf8 -> wide stops at NUL", utf8ToWideString(string("ab\0cd", 5)) == L"ab");
    checkEqual("empty string", wideStringToUtf8(utf8ToWideString("")), "");
    //bad input must not crash
    check("invalid first byte", utf8ToWideString("\xff" "a") == wstring(L"\xFFFD" L"a"));
    check("cut multi-byte character", utf8ToWideString("a\xe1\xbb") == wstring(L"a\xFFFD"));
    checkEqual("lone surrogate", wideStringToUtf8(wstring(1, (wchar_t)0xD83D)), "\xef\xbf\xbd");
}

static void testMacro() {
    setUp();
    vUseMacro = 1;
    initMacroMap(nullptr, 0);
    check("add macro", addMacro("vk", "ViKey 😀"));
    check("has macro", hasMacro("vk"));
    checkEqual("macro is replaced", type("vk "), "ViKey 😀 ");
    checkEqual("macro works inside other text", type("abc "), "abc ");

    //save and load
    vector<Byte> saved;
    getMacroSaveData(saved);
    initMacroMap(saved.data(), (int)saved.size());
    check("macro kept after save and load", hasMacro("vk"));
    check("delete macro", deleteMacro("vk"));
    check("macro deleted", !hasMacro("vk"));
    vUseMacro = 0;
}

static string testClipboard() {
    return "nội dung";
}

static void testDynamicMacro() {
    setUp();
    vUseMacro = 1;
    initMacroMap(nullptr, 0);
    macroClipboardText = testClipboard;
    addMacro("cb", "[{clipboard}]");
    checkEqual("clipboard in a macro", type("cb "), "[nội dung] ");

    time_t time = std::time(nullptr);
    struct tm now;
    localtime_r(&time, &now);
    char date[32];
    snprintf(date, sizeof(date), "%02d/%02d/%04d", now.tm_mday, now.tm_mon + 1, now.tm_year + 1900);
    addMacro("nn", "Hôm nay {date}");
    checkEqual("date in a macro", type("nn "), string("Hôm nay ") + date + " ");
    const char* weekdays[] = {"Chủ Nhật", "Thứ Hai", "Thứ Ba", "Thứ Tư", "Thứ Năm", "Thứ Sáu", "Thứ Bảy"};
    checkEqual("weekday and year", fillMacroDynamicValues("{weekday}, {year}"),
               string(weekdays[now.tm_wday]) + ", " + to_string(now.tm_year + 1900));
    checkEqual("unknown names are kept", fillMacroDynamicValues("{foo} {date"), "{foo} {date");
    checkEqual("text without values", fillMacroDynamicValues("a:b"), "a:b");

    //the content is filled again each time: the clipboard can change
    macroClipboardText = nullptr;
    checkEqual("no clipboard", type("cb "), "[] ");
    vUseMacro = 0;
}

static void testAppMemory() {
    initSmartSwitchKey(nullptr, 0);
    //status: bit 0 Vietnamese, other bits code table
    check("new app is unknown", getAppInputMethodStatus("com.apple.Terminal", 1) == -1);
    check("new app gets the current status", getAppInputMethodStatus("com.apple.Terminal", 1) == 1);
    setAppInputMethodStatus("com.apple.Terminal", 0 | (2 << 1));
    check("status changed", getAppInputMethodStatus("com.apple.Terminal", 1) == 4);
    setAppInputMethodStatus("com.google.Chrome", 1);

    vector<string> bundleIds;
    vector<int> statuses;
    getAllAppInputMethodStatus(bundleIds, statuses);
    check("list has two apps", bundleIds.size() == 2 && statuses.size() == 2);
    check("list content", bundleIds.size() == 2 && bundleIds[0] == "com.apple.Terminal" && statuses[0] == 4 &&
          bundleIds[1] == "com.google.Chrome" && statuses[1] == 1);

    //save and load
    vector<Byte> saved;
    getSmartSwitchKeySaveData(saved);
    initSmartSwitchKey(saved.data(), (int)saved.size());
    check("status kept after save and load", getAppInputMethodStatus("com.apple.Terminal", 1) == 4);

    check("find does not add the app", findAppInputMethodStatus("com.apple.Notes") == -1 &&
          findAppInputMethodStatus("com.apple.Notes") == -1 && findAppInputMethodStatus("com.apple.Terminal") == 4);

    //the last answer is cached: forgetting the app must clear it
    removeAppInputMethodStatus("com.apple.Terminal");
    check("forgotten app is unknown again", getAppInputMethodStatus("com.apple.Terminal", 1) == -1);
    removeAppInputMethodStatus("com.apple.Terminal");
    removeAppInputMethodStatus("com.google.Chrome");
    getAllAppInputMethodStatus(bundleIds, statuses);
    check("list is empty", bundleIds.empty());
}

int main() {
    pData = (vKeyHookState*)vKeyInit();
    testAppMemory();
    testTelex();
    testSpelling();
    testOrthography();
    testVNI();
    testConvertTool();
    testUtf8();
    testMacro();
    testDynamicMacro();
    printf("engine: %d checks, %d failures\n", checks, failures);
    return failures == 0 ? 0 : 1;
}
