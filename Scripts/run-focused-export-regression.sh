#!/bin/sh
set -eu

project_dir=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
library_dir=${FIND950_DIR:-"$project_dir/../FIND950"}
akaiutil_path=${1:-${AKAIUTIL_PATH:-$project_dir/.build/akaiutil-universal/akaiutil}}
fixture_path=${2:-${FOCUSED_EXPORT_FIXTURE:-"$project_dir/!OLD/AIM fixtures/TRUE950-FILTER-ENVELOPE.img"}}
sdk_path=$(xcrun --show-sdk-path)
build_dir="$project_dir/.build/focused-export-regression"

cd "$project_dir"
mkdir -p "$build_dir/ModuleCache"

CLANG_MODULE_CACHE_PATH="$build_dir/ModuleCache" swiftc \
  -sdk "$sdk_path" \
  -target arm64-apple-macosx14.0 \
  -swift-version 5 \
  -parse-as-library \
  -emit-library \
  -emit-module \
  -module-name S950Library \
  "$library_dir/Sources/S950Library/Models.swift" \
  "$library_dir/Sources/S950Library/P9ReferenceParser.swift" \
  "$library_dir/Sources/S950Library/Tools950Protocol.swift" \
  "$library_dir/Sources/S950Library/S950ProgramTransfer.swift" \
  "$library_dir/Sources/S950Library/S950CollectionTransfer.swift" \
  -emit-module-path "$build_dir/S950Library.swiftmodule" \
  -o "$build_dir/libS950Library.dylib"

CLANG_MODULE_CACHE_PATH="$build_dir/ModuleCache" swiftc \
  -sdk "$sdk_path" \
  -target arm64-apple-macosx14.0 \
  -swift-version 5 \
  -parse-as-library \
  -D AKAI_TESTING \
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
  Sources/EDIT950/TagViews.swift \
  Sources/EDIT950/TableSelectionColor.swift \
  Sources/EDIT950/MainView.swift \
  Sources/EDIT950/Sheets.swift \
  Sources/EDIT950/SettingsView.swift \
  Tests/FocusedExportRegressionRunner.swift \
  -o "$build_dir/FocusedExportRegressionRunner" \
  -I "$build_dir" \
  -L "$build_dir" \
  -lS950Library \
  -framework AppKit \
  -framework SwiftUI \
  -framework CoreText \
  -framework AVFoundation \
  -framework CoreMIDI \
  -framework UniformTypeIdentifiers

DYLD_LIBRARY_PATH="$build_dir" \
  "$build_dir/FocusedExportRegressionRunner" "$akaiutil_path" "$fixture_path"
