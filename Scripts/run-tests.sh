#!/bin/sh
set -eu

PROJECT_DIR=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
cd "$PROJECT_DIR"

SDK_PATH=$(xcrun --show-sdk-path)
BUILD_DIR="$PROJECT_DIR/.build/manual-tests"
mkdir -p "$BUILD_DIR/ModuleCache"

CLANG_MODULE_CACHE_PATH="$BUILD_DIR/ModuleCache" swiftc \
  -sdk "$SDK_PATH" \
  -target arm64-apple-macosx14.0 \
  -swift-version 5 \
  -parse-as-library \
  Sources/EDIT950/Models.swift \
  Sources/EDIT950/SharedTagLibrary.swift \
  Sources/EDIT950/Tools950Interop.swift \
  Sources/EDIT950/AkaiCommandBuilder.swift \
  Sources/EDIT950/AkaiOutputParser.swift \
  Sources/EDIT950/AkaiCommandController.swift \
  Sources/EDIT950/FileOperations.swift \
  Sources/EDIT950/P9Program.swift \
  Sources/EDIT950/MIDIKeygroupMonitor.swift \
  Sources/EDIT950/PLAY950Fixture.swift \
  Sources/EDIT950/AbletonDrumRackImport.swift \
  Sources/EDIT950/AbletonDrumRackExport.swift \
  Sources/EDIT950/WAVService.swift \
  Sources/EDIT950/DiagnosticLogStore.swift \
  Sources/EDIT950/VolumeCoordination.swift \
  Sources/EDIT950/AppSettings.swift \
  Tests/TestRunner.swift \
  -o "$BUILD_DIR/EDIT950Tests" \
  -framework AppKit \
  -framework AVFoundation \
  -framework CoreMIDI \
  -framework UniformTypeIdentifiers

chmod +x Tests/Fixtures/fake-akaiutil.sh
"$BUILD_DIR/EDIT950Tests"
