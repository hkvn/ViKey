#!/bin/bash
#
# Build and run the ViKey tests. Exits with an error when a test fails.
#
# usage: scripts/run-tests.sh
#
#   Tests/engine    typing engine, convert tool, macros (C++, no Xcode project needed)
#   Tests/inputmethod  word building of the input method (InputMethodKit test version)
#   Tests/settings  settings model of the settings window, macro files and macro sync (Swift + stubs of the app)
#
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ENGINE="$REPO_ROOT/Sources/OpenKey/engine"
APP_SOURCES="$REPO_ROOT/Sources/OpenKey/macOS/ModernKey"
OUT="$REPO_ROOT/build/tests"
mkdir -p "$OUT"
cd "$REPO_ROOT"

echo "==> Engine tests"
clang++ -std=c++17 -O1 -Wall -Wno-sign-compare -I"$ENGINE" \
    "$ENGINE/Engine.cpp" "$ENGINE/Vietnamese.cpp" "$ENGINE/Macro.cpp" "$ENGINE/ConvertTool.cpp" "$ENGINE/SmartSwitchKey.cpp" \
    Tests/engine/TestGlobals.cpp Tests/engine/EngineTests.cpp -o "$OUT/engine-tests"
"$OUT/engine-tests"

echo "==> Input method tests"
IM_SOURCES="$REPO_ROOT/Sources/OpenKey/macOS/InputMethod"
clang++ -std=c++17 -O1 -fobjc-arc -Wall -Wno-sign-compare -mmacosx-version-min=13.0 -I"$ENGINE" -I"$IM_SOURCES" \
    "$ENGINE/Engine.cpp" "$ENGINE/Vietnamese.cpp" "$ENGINE/Macro.cpp" "$ENGINE/ConvertTool.cpp" "$ENGINE/SmartSwitchKey.cpp" \
    "$IM_SOURCES/EngineGlobals.cpp" "$IM_SOURCES/Composer.mm" Tests/inputmethod/ComposerTests.mm \
    -framework Foundation -o "$OUT/inputmethod-tests"
clang++ -std=c++17 -O1 -fobjc-arc -w -mmacosx-version-min=13.0 -I"$ENGINE" -I"$IM_SOURCES" \
    "$ENGINE/Engine.cpp" "$ENGINE/Vietnamese.cpp" "$ENGINE/Macro.cpp" "$ENGINE/ConvertTool.cpp" "$ENGINE/SmartSwitchKey.cpp" \
    "$IM_SOURCES/EngineGlobals.cpp" "$IM_SOURCES/Composer.mm" "$IM_SOURCES/InputController.mm" Tests/inputmethod/ControllerTests.mm \
    -framework Cocoa -framework InputMethodKit -framework Carbon -o "$OUT/inputmethod-controller-tests"
"$OUT/inputmethod-controller-tests"
defaults delete inputmethod-controller-tests >/dev/null 2>&1 || true
rm -f "$HOME/Library/Preferences/inputmethod-controller-tests.plist"
"$OUT/inputmethod-tests"

echo "==> Settings tests"
#the settings windows use the engine through EngineBridge; the rest of the app is replaced by AppStubs
mkdir -p "$OUT/objects"
clang -fobjc-arc -w -mmacosx-version-min=13.0 -I"$APP_SOURCES" -I"$ENGINE" -c Tests/settings/AppStubs.m -o "$OUT/objects/AppStubs.o"
clang -fobjc-arc -w -mmacosx-version-min=13.0 -I"$APP_SOURCES" -c "$APP_SOURCES/Logging.m" -o "$OUT/objects/Logging.o"
clang++ -fobjc-arc -w -std=c++17 -mmacosx-version-min=13.0 -I"$APP_SOURCES" -I"$ENGINE" -c "$APP_SOURCES/EngineBridge.mm" -o "$OUT/objects/EngineBridge.o"
for source in Engine Vietnamese Macro ConvertTool SmartSwitchKey; do
    clang++ -std=c++17 -O1 -w -mmacosx-version-min=13.0 -I"$ENGINE" -c "$ENGINE/$source.cpp" -o "$OUT/objects/$source.o"
done
swiftc -O -suppress-warnings -target "$(uname -m)-apple-macos13.0" \
    -import-objc-header "$APP_SOURCES/OpenKey-Bridging-Header.h" -I"$APP_SOURCES" -I"$ENGINE" \
    "$APP_SOURCES/SettingsModel.swift" "$APP_SOURCES/SettingsView.swift" "$APP_SOURCES/SettingsWindowController.swift" \
    "$APP_SOURCES/AppsModel.swift" "$APP_SOURCES/MacroFile.swift" "$APP_SOURCES/MacroSync.swift" \
    Tests/settings/SettingsModelTests.swift "$OUT"/objects/*.o -lc++ -o "$OUT/settings-tests"
"$OUT/settings-tests"
#remove the test settings domain (macOS keeps an empty file)
defaults delete vikey.settings.tests >/dev/null 2>&1 || true
rm -f "$HOME/Library/Preferences/vikey.settings.tests.plist"

echo "==> All tests passed"
