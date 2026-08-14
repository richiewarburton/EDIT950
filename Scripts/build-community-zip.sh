#!/bin/sh
set -eu

PROJECT_DIR=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
cd "$PROJECT_DIR"

APP_DIR="$PROJECT_DIR/Build/EDIT950.app"
INFO_PLIST="$APP_DIR/Contents/Info.plist"
VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$INFO_PLIST")
BUILD_NUMBER=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$INFO_PLIST")
DIST_DIR="$PROJECT_DIR/Build/Distribution"
PACKAGE_NAME="EDIT950 $VERSION"
PACKAGE_DIR="$DIST_DIR/$PACKAGE_NAME"
ZIP_PATH="$DIST_DIR/EDIT950-$VERSION-macOS-Universal.zip"
ARCHIVE_DIR="$PROJECT_DIR/.build/community-archive"

test -d "$APP_DIR"
mkdir -p "$DIST_DIR" "$ARCHIVE_DIR"

if [ -e "$PACKAGE_DIR" ]; then
  mv "$PACKAGE_DIR" "$ARCHIVE_DIR/$PACKAGE_NAME-$(date +%s)"
fi
if [ -e "$ZIP_PATH" ]; then
  mv "$ZIP_PATH" "$ARCHIVE_DIR/$(basename "$ZIP_PATH").$(date +%s)"
fi

mkdir -p "$PACKAGE_DIR"
/usr/bin/ditto "$APP_DIR" "$PACKAGE_DIR/EDIT950.app"
mkdir -p "$PACKAGE_DIR/Screenshots"
cp Documentation/Images/edit950-browser.png "$PACKAGE_DIR/Screenshots/"
cp Documentation/Images/edit950-p9-editor.png "$PACKAGE_DIR/Screenshots/"
cp Documentation/Images/edit950-shared-tag-settings.png "$PACKAGE_DIR/Screenshots/"
cp Documentation/Images/edit950-verified-overwrite.png "$PACKAGE_DIR/Screenshots/"
cp ReleaseDocs/COMMUNITY_README.md "$PACKAGE_DIR/README.md"
cp LICENSE "$PACKAGE_DIR/LICENSE"
cp LICENSING.md "$PACKAGE_DIR/LICENSING.md"
cp ReleaseDocs/THIRD-PARTY-NOTICES.txt "$PACKAGE_DIR/THIRD-PARTY-NOTICES.txt"
cp TEST_REPORT.md "$PACKAGE_DIR/TEST_REPORT.md"
/usr/bin/ditto Documentation "$PACKAGE_DIR/Documentation"
/usr/bin/ditto ThirdParty/akaiutil-4.6.7 "$PACKAGE_DIR/AKAI Util 4.6.7 Source"

(
  cd "$PACKAGE_DIR"
  /usr/bin/shasum -a 256 \
    "EDIT950.app/Contents/MacOS/EDIT950" \
    "EDIT950.app/Contents/Resources/akaiutil" \
    "README.md" \
    "LICENSE" \
    "LICENSING.md" \
    "THIRD-PARTY-NOTICES.txt" \
    "TEST_REPORT.md" \
    "Documentation/USER_GUIDE.md" \
    "Documentation/AKAI_UTIL_UNIVERSAL.md" \
    "Screenshots/edit950-browser.png" \
    "Screenshots/edit950-p9-editor.png" \
    "Screenshots/edit950-shared-tag-settings.png" \
    "Screenshots/edit950-verified-overwrite.png" \
    > "SHA256SUMS.txt"
)

/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$PACKAGE_DIR" "$ZIP_PATH"
/usr/bin/unzip -t "$ZIP_PATH" >/dev/null

printf 'Version: %s (%s)\n' "$VERSION" "$BUILD_NUMBER"
printf 'Package: %s\n' "$PACKAGE_DIR"
printf 'ZIP: %s\n' "$ZIP_PATH"
/usr/bin/shasum -a 256 "$ZIP_PATH"
