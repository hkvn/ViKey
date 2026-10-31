#!/bin/bash
#
# Build the ViKey input method (InputMethodKit, test version) without Xcode.
#
# usage: scripts/build-input-method.sh [--install] [--uninstall]
#
#   output       build/input-method/ViKeyInput.app
#   --install    copy it to ~/Library/Input Methods and turn it on. Then choose "ViKey" in the
#                input menu of the menu bar (or System Settings > Keyboard > Input Sources)
#   --uninstall  turn it off and remove it
#
# It is signed like the app: "Developer ID Application" if there is one, else "Apple Development".
# Set VIKEY_SIGN_IDENTITY to choose another one.
#
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ENGINE="$REPO_ROOT/Sources/OpenKey/engine"
SOURCES="$REPO_ROOT/Sources/OpenKey/macOS/InputMethod"
RESOURCES="$REPO_ROOT/Sources/OpenKey/macOS/ModernKey/Resources"
OUT="$REPO_ROOT/build/input-method"
APP="$OUT/ViKeyInput.app"
INSTALLED="$HOME/Library/Input Methods/ViKeyInput.app"

die() { echo "error: $*" >&2; exit 1; }

if [ "${1:-}" = "--uninstall" ]; then
    [ -d "$INSTALLED" ] && "$INSTALLED/Contents/MacOS/ViKeyInput" --disable || true
    pkill -x ViKeyInput || true
    rm -rf "$INSTALLED"
    echo "removed $INSTALLED"
    exit 0
fi

ARCHS=(-arch arm64 -arch x86_64)
FLAGS=(-mmacosx-version-min=13.0 -O2 "${ARCHS[@]}" -I"$ENGINE" -I"$SOURCES")
rm -rf "$OUT"
mkdir -p "$OUT/objects" "$APP/Contents/MacOS" "$APP/Contents/Resources"

echo "==> Compile"
for source in Engine Vietnamese Macro ConvertTool SmartSwitchKey; do
    clang++ -std=c++17 -w "${FLAGS[@]}" -c "$ENGINE/$source.cpp" -o "$OUT/objects/$source.o"
done
clang++ -std=c++17 "${FLAGS[@]}" -c "$SOURCES/EngineGlobals.cpp" -o "$OUT/objects/EngineGlobals.o"
clang++ -std=c++17 -fobjc-arc "${FLAGS[@]}" -c "$SOURCES/Composer.mm" -o "$OUT/objects/Composer.o"
clang++ -std=c++17 -fobjc-arc "${FLAGS[@]}" -c "$SOURCES/InputController.mm" -o "$OUT/objects/InputController.o"
clang -fobjc-arc "${FLAGS[@]}" -c "$SOURCES/main.m" -o "$OUT/objects/main.o"
clang++ "${ARCHS[@]}" -mmacosx-version-min=13.0 "$OUT"/objects/*.o \
    -framework Cocoa -framework InputMethodKit -framework Carbon -o "$APP/Contents/MacOS/ViKeyInput"

echo "==> Bundle"
cp "$SOURCES/Info.plist" "$APP/Contents/Info.plist"
#menu bar icon of the input source, from the status icon of the app
tiffutil -cathidpicheck "$RESOURCES/Status.png" "$RESOURCES/Status@2x.png" -out "$APP/Contents/Resources/ViKey.tiff" >/dev/null 2>&1
cp "$RESOURCES/Icon.icns" "$APP/Contents/Resources/Icon.icns"

echo "==> Sign"
if [ -n "${VIKEY_SIGN_IDENTITY:-}" ]; then
    IDENTITY="$VIKEY_SIGN_IDENTITY"
else
    IDENTITIES="$(security find-identity -v -p codesigning)"
    IDENTITY="$(echo "$IDENTITIES" | sed -n 's/.*"\(Developer ID Application: [^"]*\)".*/\1/p' | sed -n 1p)"
    [ -n "$IDENTITY" ] || IDENTITY="$(echo "$IDENTITIES" | sed -n 's/.*"\(Apple Development: [^"]*\)".*/\1/p' | sed -n 1p)"
fi
[ -n "$IDENTITY" ] || die "no code signing certificate in the keychain"
codesign --force --options runtime --timestamp=none --sign "$IDENTITY" "$APP"
codesign --verify --strict "$APP"
echo "built $APP ($IDENTITY)"

if [ "${1:-}" = "--install" ]; then
    echo "==> Install"
    #macOS starts the input method again when it is needed
    pkill -x ViKeyInput || true
    mkdir -p "$HOME/Library/Input Methods"
    rm -rf "$INSTALLED"
    ditto "$APP" "$INSTALLED"
    "$INSTALLED/Contents/MacOS/ViKeyInput" --register
    echo "Choose \"ViKey\" in the input menu of the menu bar to use it."
fi
