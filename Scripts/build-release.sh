#!/bin/sh
set -eu

PROJECT_DIR=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
cd "$PROJECT_DIR"

SDK_PATH=$(xcrun --show-sdk-path)
BUILD_DIR="$PROJECT_DIR/.build/release-manual"
APP_DIR="$PROJECT_DIR/Build/EDIT950.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
FONTS_DIR="$RESOURCES_DIR/Fonts"
LICENCES_DIR="$RESOURCES_DIR/Licenses"
BRAND_ASSETS_DIR="$RESOURCES_DIR/BrandAssets"
CUSTOM_ICON="$PROJECT_DIR/Resources/EDIT950.icns"

if [ ! -f "$CUSTOM_ICON" ]; then
  echo "Approved EDIT950 icon is missing: $CUSTOM_ICON" >&2
  exit 1
fi

mkdir -p "$BUILD_DIR/ModuleCache" "$PROJECT_DIR/Build"

for APP_ARCH in arm64 x86_64; do
  CLANG_MODULE_CACHE_PATH="$BUILD_DIR/ModuleCache-$APP_ARCH" swiftc \
    -sdk "$SDK_PATH" \
    -target "$APP_ARCH-apple-macosx14.0" \
    -swift-version 5 \
    -parse-as-library \
    -O \
    -whole-module-optimization \
    Sources/EDIT950/*.swift \
    -o "$BUILD_DIR/EDIT950-$APP_ARCH" \
    -framework AppKit \
    -framework SwiftUI \
    -framework AVFoundation \
    -framework CoreMIDI \
    -framework CoreText \
    -framework UniformTypeIdentifiers
done

/usr/bin/lipo -create \
  "$BUILD_DIR/EDIT950-arm64" \
  "$BUILD_DIR/EDIT950-x86_64" \
  -output "$BUILD_DIR/EDIT950"

if [ -d "$APP_DIR" ]; then
  mv "$APP_DIR" "$BUILD_DIR/previous-app-$(date +%s)"
fi
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR" "$FONTS_DIR" "$LICENCES_DIR" "$BRAND_ASSETS_DIR"
cp "$CUSTOM_ICON" "$RESOURCES_DIR/AppIcon.icns"

cp "$BUILD_DIR/EDIT950" "$MACOS_DIR/EDIT950"
cp Resources/Info.plist "$CONTENTS_DIR/Info.plist"
cp Resources/Fonts/JetBrainsMono-Regular.ttf "$FONTS_DIR/"
cp Resources/Fonts/JetBrainsMono-Medium.ttf "$FONTS_DIR/"
cp Resources/Fonts/JetBrainsMono-Bold.ttf "$FONTS_DIR/"
cp Resources/Fonts/fonts.sha256 "$FONTS_DIR/"
cp Resources/Licenses/JetBrainsMono-OFL-1.1.txt "$LICENCES_DIR/"
cp Resources/BrandAssets/EDIT950-brand-mark.png "$BRAND_ASSETS_DIR/"
cp Resources/BrandAssets/launcher-FIND950.png "$BRAND_ASSETS_DIR/"
cp Resources/BrandAssets/launcher-PLAY950.png "$BRAND_ASSETS_DIR/"
cp Sources/EDIT950/Resources/AKAI-S950-Sampler-Template.adg \
  "$RESOURCES_DIR/AKAI-S950-Sampler-Template.adg"
"$PROJECT_DIR/Scripts/build-akaiutil-universal.sh" "$RESOURCES_DIR/akaiutil"
# Remove intermediates left by earlier local builds; only the Universal helper ships.
for LEGACY_HELPER_SLICE in \
  "$RESOURCES_DIR/akaiutil-arm64" \
  "$RESOURCES_DIR/akaiutil-x86_64"
do
  if [ -f "$LEGACY_HELPER_SLICE" ]; then
    unlink "$LEGACY_HELPER_SLICE"
  fi
done
chmod 755 "$MACOS_DIR/EDIT950"
chmod 755 "$RESOURCES_DIR/akaiutil"

HELPER_ARCHS=$(/usr/bin/lipo -archs "$RESOURCES_DIR/akaiutil")
case " $HELPER_ARCHS " in *" arm64 "*) ;; *) echo "Bundled AKAI Util is missing arm64" >&2; exit 1 ;; esac
case " $HELPER_ARCHS " in *" x86_64 "*) ;; *) echo "Bundled AKAI Util is missing x86_64" >&2; exit 1 ;; esac

# Nested code is signed first; the completed outer bundle is signed last.
codesign --force --sign - "$RESOURCES_DIR/akaiutil"
codesign --force --sign - "$APP_DIR"
plutil -lint "$CONTENTS_DIR/Info.plist"
test "$(/usr/libexec/PlistBuddy -c 'Print :ATSApplicationFontsPath' "$CONTENTS_DIR/Info.plist")" = "Fonts/"
(cd "$FONTS_DIR" && shasum -a 256 -c fonts.sha256)
codesign --verify --deep --strict --verbose=2 "$APP_DIR"

APP_ARCHS=$(/usr/bin/lipo -archs "$MACOS_DIR/EDIT950")
case " $APP_ARCHS " in *" arm64 "*) ;; *) echo "Application is missing arm64" >&2; exit 1 ;; esac
case " $APP_ARCHS " in *" x86_64 "*) ;; *) echo "Application is missing x86_64" >&2; exit 1 ;; esac

if strings "$MACOS_DIR/EDIT950" "$RESOURCES_DIR/akaiutil" | grep -q '/Users/'; then
  echo "A packaged executable contains a /Users/ development path" >&2
  exit 1
fi

echo "$APP_DIR"
