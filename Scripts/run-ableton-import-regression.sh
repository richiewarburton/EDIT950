#!/bin/sh
set -eu

if [ "$#" -lt 1 ]; then
  echo "usage: $0 <rack.adg> [akaiutil]" >&2
  exit 2
fi

PROJECT_DIR=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
cd "$PROJECT_DIR"

SOURCE_ADG=$1
AKAIUTIL_PATH=${2:-${AKAIUTIL_PATH:-$PROJECT_DIR/.build/akaiutil-universal/akaiutil}}
SDK_PATH=$(xcrun --show-sdk-path)
BUILD_DIR="$PROJECT_DIR/.build/manual-ableton-import-regression"
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
  Sources/EDIT950/ProgramAudition.swift \
  Sources/EDIT950/ProgramAuditionViews.swift \
  Sources/EDIT950/P9EditorView.swift \
  Sources/EDIT950/FocusedProgramExport.swift \
  Sources/EDIT950/CollectionExport.swift \
  Sources/EDIT950/DiagnosticLogStore.swift \
  Sources/EDIT950/VolumeCoordination.swift \
  Sources/EDIT950/AppModel.swift \
  Sources/EDIT950/Sheets.swift \
  Tests/AbletonImportRegressionRunner.swift \
  -o "$BUILD_DIR/AbletonImportRegressionRunner" \
  -framework AppKit \
  -framework SwiftUI \
  -framework CoreText \
  -framework AVFoundation \
  -framework UniformTypeIdentifiers

"$BUILD_DIR/AbletonImportRegressionRunner" "$SOURCE_ADG" "$AKAIUTIL_PATH"
