#!/bin/bash
#
# Build, sign and publish a ViKey release for macOS on GitHub.
#
# usage: scripts/release-macos.sh <version> [options]
#   <version>      for example 2.1.0; the git tag is v<version>
#   --draft        create the GitHub release as a draft (the update check does not see it)
#   --notes FILE   use FILE as release notes (default: commits since the last release)
#   --dry-run      only build and package: no commit, tag, push or release
#   --yes          do not ask before publishing
#
# The app is signed on this Mac with a certificate from the keychain: "Developer ID Application"
# if there is one, else "Apple Development". Set VIKEY_SIGN_IDENTITY to choose another one.
# Signing every release with the same certificate keeps the Accessibility permission when users update.
#
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT="$REPO_ROOT/Sources/OpenKey/macOS/OpenKey.xcodeproj"
SCHEME="OpenKey"
APP_NAME="ViKey"

die() { echo "error: $*" >&2; exit 1; }
step() { echo; echo "==> $*"; }

#--- arguments
VERSION=""
DRAFT=0
DRY_RUN=0
YES=0
NOTES_FILE=""
while [ $# -gt 0 ]; do
    case "$1" in
        --draft) DRAFT=1 ;;
        --dry-run) DRY_RUN=1 ;;
        --yes) YES=1 ;;
        --notes) shift; NOTES_FILE="${1:-}"; [ -f "$NOTES_FILE" ] || die "notes file not found: $NOTES_FILE" ;;
        -h|--help) sed -n '3,15p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        -*) die "unknown option: $1" ;;
        *) [ -z "$VERSION" ] || die "only one version"; VERSION="$1" ;;
    esac
    shift
done
[ -n "$VERSION" ] || die "missing version, for example: $0 2.1.0"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "version must look like 2.1.0"
TAG="v$VERSION"

cd "$REPO_ROOT"
OUT_DIR="$REPO_ROOT/build/release/$VERSION"

#--- checks
step "Checking"
for tool in xcodebuild hdiutil ditto shasum security openssl; do
    command -v "$tool" >/dev/null || die "$tool not found"
done
BRANCH="$(git rev-parse --abbrev-ref HEAD)"
if [ "$DRY_RUN" = 0 ]; then
    command -v gh >/dev/null || die "gh not found: brew install gh"
    gh auth status >/dev/null 2>&1 || die "gh is not logged in: gh auth login"
    [ -z "$(git status --porcelain)" ] || die "working tree has changes: commit or stash them first"
    git rev-parse -q --verify "refs/tags/$TAG" >/dev/null && die "tag $TAG already exists"
    [ -z "$(git ls-remote --tags origin "refs/tags/$TAG")" ] || die "tag $TAG already exists on origin"
fi

#--- signing identity
if [ -n "${VIKEY_SIGN_IDENTITY:-}" ]; then
    IDENTITY="$VIKEY_SIGN_IDENTITY"
else
    IDENTITIES="$(security find-identity -v -p codesigning)"
    IDENTITY="$(echo "$IDENTITIES" | sed -n 's/.*"\(Developer ID Application: [^"]*\)".*/\1/p' | sed -n 1p)"
    [ -n "$IDENTITY" ] || IDENTITY="$(echo "$IDENTITIES" | sed -n 's/.*"\(Apple Development: [^"]*\)".*/\1/p' | sed -n 1p)"
fi
[ -n "$IDENTITY" ] || die "no code signing certificate in the keychain (create one in Xcode > Settings > Accounts)"
#the team id is the OU of the certificate
TEAM_ID="$(security find-certificate -c "$IDENTITY" -p | openssl x509 -noout -subject | sed -n 's/.*OU *= *\([A-Z0-9]\{10\}\).*/\1/p')"
[ -n "$TEAM_ID" ] || die "can not read the team id of \"$IDENTITY\""

#--- version and build number
CURRENT_BUILD="$(sed -n 's/.*CURRENT_PROJECT_VERSION = \([0-9]*\);.*/\1/p' "$PROJECT/project.pbxproj" | sed -n 1p)"
BUILD_NUMBER=$((CURRENT_BUILD + 1))

echo "version:  $VERSION (build $BUILD_NUMBER), tag $TAG"
echo "branch:   $BRANCH @ $(git rev-parse --short HEAD)"
echo "identity: $IDENTITY (team $TEAM_ID)"
[ "$DRY_RUN" = 1 ] && echo "mode:     dry run (nothing is published)"

#--- tests
step "Running tests"
mkdir -p "$REPO_ROOT/build"
"$REPO_ROOT/scripts/run-tests.sh" > "$REPO_ROOT/build/tests.log" 2>&1 || { tail -20 "$REPO_ROOT/build/tests.log" >&2; die "tests failed, see build/tests.log"; }
tail -1 "$REPO_ROOT/build/tests.log"

#--- build
step "Building $APP_NAME.app"
rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR"
BUILD_LOG="$OUT_DIR/build.log"
if ! xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration Release \
        -derivedDataPath "$REPO_ROOT/build/DerivedData" \
        CODE_SIGN_IDENTITY="$IDENTITY" CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM="$TEAM_ID" PROVISIONING_PROFILE_SPECIFIER="" \
        MARKETING_VERSION="$VERSION" CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
        clean build > "$BUILD_LOG" 2>&1; then
    grep -E "error:" "$BUILD_LOG" | sort -u | head -20 >&2
    die "build failed, see $BUILD_LOG"
fi
APP="$REPO_ROOT/build/DerivedData/Build/Products/Release/$APP_NAME.app"
[ -d "$APP" ] || die "$APP not found"

step "Checking the app"
codesign --verify --deep --strict "$APP" || die "code signature is not valid"
APP_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
[ "$APP_VERSION" = "$VERSION" ] || die "app version is $APP_VERSION, not $VERSION"
codesign -d -r- "$APP" 2>&1 | sed -n 's/^designated => /requirement: /p'
echo "architectures: $(lipo -archs "$APP/Contents/MacOS/$APP_NAME")"

#--- package
step "Packaging"
DMG="$OUT_DIR/$APP_NAME-$VERSION.dmg"
ZIP="$OUT_DIR/$APP_NAME-$VERSION.zip"
STAGING="$OUT_DIR/dmg"
mkdir -p "$STAGING"
ditto "$APP" "$STAGING/$APP_NAME.app"
ln -s /Applications "$STAGING/Applications"
hdiutil create -volname "$APP_NAME $VERSION" -srcfolder "$STAGING" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGING"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"
(cd "$OUT_DIR" && shasum -a 256 "$(basename "$DMG")" "$(basename "$ZIP")" > SHA256SUMS.txt)
cat "$OUT_DIR/SHA256SUMS.txt"

#--- release notes
NOTES="$OUT_DIR/notes.md"
if [ -n "$NOTES_FILE" ]; then
    cp "$NOTES_FILE" "$NOTES"
else
    PREV_TAG="$(git describe --tags --abbrev=0 --match 'v[0-9]*' 2>/dev/null || true)"
    {
        echo "## Thay đổi"
        if [ -n "$PREV_TAG" ]; then
            git log --no-merges --pretty='- %s' "$PREV_TAG..HEAD" | grep -v "^- Release $APP_NAME " || true
        else
            echo "- Bản phát hành đầu tiên của ViKey, phát triển tiếp từ OpenKey."
        fi
    } > "$NOTES"
fi
cat >> "$NOTES" <<EOF

## Cài đặt
1. Tải \`$APP_NAME-$VERSION.dmg\`, mở ra và kéo \`$APP_NAME.app\` vào thư mục Applications.
2. Lần đầu mở, nếu macOS chặn ứng dụng: vào System Settings → Privacy & Security, bấm **Open Anyway**.
3. Cho phép ViKey trong System Settings → Privacy & Security → **Accessibility**.

## SHA-256
\`\`\`
$(cat "$OUT_DIR/SHA256SUMS.txt")
\`\`\`
EOF

if [ "$DRY_RUN" = 1 ]; then
    step "Dry run done"
    echo "files in $OUT_DIR:"
    ls -1 "$OUT_DIR"
    exit 0
fi

#--- publish
if [ "$YES" = 0 ]; then
    echo
    read -r -p "Publish $APP_NAME $VERSION from branch $BRANCH to GitHub? [y/N] " answer
    [ "$answer" = "y" ] || [ "$answer" = "Y" ] || die "cancelled"
fi

step "Committing version and tagging $TAG"
sed -i '' -e "s/MARKETING_VERSION = [^;]*;/MARKETING_VERSION = $VERSION;/" \
          -e "s/CURRENT_PROJECT_VERSION = [0-9]*;/CURRENT_PROJECT_VERSION = $BUILD_NUMBER;/" "$PROJECT/project.pbxproj"
git add "$PROJECT/project.pbxproj"
git commit -m "Release $APP_NAME $VERSION"
git tag -a "$TAG" -m "$APP_NAME $VERSION"

step "Pushing"
git push origin "$BRANCH"
git push origin "$TAG"

step "Creating the GitHub release"
DRAFT_FLAG=""
[ "$DRAFT" = 1 ] && DRAFT_FLAG="--draft"
gh release create "$TAG" "$DMG" "$ZIP" "$OUT_DIR/SHA256SUMS.txt" \
    --title "$APP_NAME $VERSION" --notes-file "$NOTES" --verify-tag $DRAFT_FLAG
echo
echo "Done: $(gh release view "$TAG" --json url --jq .url)"
