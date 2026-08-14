#!/bin/sh
set -eu

PROJECT_DIR=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
cd "$PROJECT_DIR"

if [ "$#" -lt 1 ] || [ "$#" -gt 3 ]; then
  echo "usage: $0 <image.img> [screenshot.png] [akaiutil]" >&2
  exit 2
fi

IMAGE_PATH=$1
SCREENSHOT_PATH=${2:-/tmp/EDIT950-smoke.png}
AKAIUTIL_PATH=${3:-${AKAIUTIL_PATH:-$PROJECT_DIR/.build/akaiutil-universal/akaiutil}}
SDK_PATH=$(xcrun --show-sdk-path)
BUILD_DIR="$PROJECT_DIR/.build/manual-visual-smoke"
mkdir -p "$BUILD_DIR/ModuleCache"

CLANG_MODULE_CACHE_PATH="$BUILD_DIR/ModuleCache" swiftc \
  -sdk "$SDK_PATH" \
  -target arm64-apple-macosx14.0 \
  -swift-version 5 \
  -parse-as-library \
  Sources/EDIT950/Models.swift \
  Sources/EDIT950/SuiteDesignSystem.swift \
  Sources/EDIT950/SharedTagLibrary.swift \
  Sources/EDIT950/Tools950Interop.swift \
  Sources/EDIT950/AkaiCommandBuilder.swift \
  Sources/EDIT950/AkaiOutputParser.swift \
  Sources/EDIT950/AkaiCommandController.swift \
  Sources/EDIT950/FileOperations.swift \
  Sources/EDIT950/P9Program.swift \
  Sources/EDIT950/PLAY950Fixture.swift \
  Sources/EDIT950/AbletonDrumRackImport.swift \
  Sources/EDIT950/AbletonDrumRackExport.swift \
  Sources/EDIT950/AbletonDrumRackImportView.swift \
  Sources/EDIT950/WAVService.swift \
  Sources/EDIT950/AppSettings.swift \
  Sources/EDIT950/MIDIKeygroupMonitor.swift \
  Sources/EDIT950/P9EditorView.swift \
  Sources/EDIT950/FocusedProgramExport.swift \
  Sources/EDIT950/CollectionExport.swift \
  Sources/EDIT950/DiagnosticLogStore.swift \
  Sources/EDIT950/VolumeCoordination.swift \
  Sources/EDIT950/AppModel.swift \
  Sources/EDIT950/TagViews.swift \
  Sources/EDIT950/TableSelectionColor.swift \
  Sources/EDIT950/MainView.swift \
  Sources/EDIT950/Sheets.swift \
  Sources/EDIT950/SettingsView.swift \
  Tests/VisualSmokeRunner.swift \
  -o "$BUILD_DIR/VisualSmokeRunner" \
  -framework AppKit \
  -framework SwiftUI \
  -framework CoreText \
  -framework AVFoundation \
  -framework UniformTypeIdentifiers

EDIT950_TEST_FONT_DIRECTORY="$PROJECT_DIR/Resources/Fonts" \
  "$BUILD_DIR/VisualSmokeRunner" "$IMAGE_PATH" "$SCREENSHOT_PATH" "$AKAIUTIL_PATH"
