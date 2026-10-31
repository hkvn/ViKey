#!/bin/bash
#
# Build and run the ViKey tests. Exits with an error when a test fails.
#
# usage: scripts/run-tests.sh
#
#   Tests/engine    typing engine, convert tool, macros (C++, no Xcode project needed)
#   Tests/settings  settings model of the settings window (Swift + stubs of the app)
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

echo "==> Settings tests"
clang -fobjc-arc -w -mmacosx-version-min=13.0 -I"$APP_SOURCES" -c Tests/settings/AppStubs.m -o "$OUT/AppStubs.o"
swiftc -O -suppress-warnings -target "$(uname -m)-apple-macos13.0" \
    -import-objc-header "$APP_SOURCES/OpenKey-Bridging-Header.h" -I"$APP_SOURCES" \
    "$APP_SOURCES/SettingsModel.swift" "$APP_SOURCES/SettingsView.swift" "$APP_SOURCES/SettingsWindowController.swift" \
    Tests/settings/SettingsModelTests.swift "$OUT/AppStubs.o" -o "$OUT/settings-tests"
"$OUT/settings-tests"
#remove the test settings domain (macOS keeps an empty file)
defaults delete vikey.settings.tests >/dev/null 2>&1 || true
rm -f "$HOME/Library/Preferences/vikey.settings.tests.plist"

echo "==> All tests passed"
