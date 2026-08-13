#!/bin/sh
set -eu

PROJECT_DIR=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
cd "$PROJECT_DIR"

P9_PATH=${1:-${AKAI_P9_FIXTURE:-}}
if [ -z "$P9_PATH" ]; then
  echo "usage: $0 <fixture.p9>" >&2
  exit 2
fi
SCREENSHOT_PATH=${2:-/tmp/EDIT950-P9-editor-smoke.png}
SELECTION_MODE=${3:-}
SDK_PATH=$(xcrun --show-sdk-path)
BUILD_DIR="$PROJECT_DIR/.build/manual-p9-editor-smoke"
mkdir -p "$BUILD_DIR/ModuleCache"

CLANG_MODULE_CACHE_PATH="$BUILD_DIR/ModuleCache" swiftc \
  -sdk "$SDK_PATH" \
  -target arm64-apple-macosx14.0 \
  -swift-version 5 \
  -parse-as-library \
  Sources/EDIT950/Models.swift \
  Sources/EDIT950/SuiteDesignSystem.swift \
  Sources/EDIT950/AkaiCommandBuilder.swift \
  Sources/EDIT950/P9Program.swift \
  Sources/EDIT950/AbletonDrumRackImport.swift \
  Sources/EDIT950/AbletonDrumRackExport.swift \
  Sources/EDIT950/AbletonDrumRackImportView.swift \
  Sources/EDIT950/MIDIKeygroupMonitor.swift \
  Sources/EDIT950/P9EditorView.swift \
  Tests/P9EditorVisualRunner.swift \
  -o "$BUILD_DIR/P9EditorVisualRunner" \
  -framework AppKit \
  -framework SwiftUI \
  -framework CoreText \
  -framework UniformTypeIdentifiers

if [ "$SELECTION_MODE" = "--all" ] \
    || [ "$SELECTION_MODE" = "--spread" ] \
    || [ "$SELECTION_MODE" = "--overwrite" ]; then
  "$BUILD_DIR/P9EditorVisualRunner" "$P9_PATH" "$SCREENSHOT_PATH" "$SELECTION_MODE"
else
  "$BUILD_DIR/P9EditorVisualRunner" "$P9_PATH" "$SCREENSHOT_PATH"
fi
