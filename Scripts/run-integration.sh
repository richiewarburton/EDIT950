#!/bin/sh
set -eu

PROJECT_DIR=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
cd "$PROJECT_DIR"

AKAIUTIL_PATH=${1:-${AKAIUTIL_PATH:-$PROJECT_DIR/.build/akaiutil-universal/akaiutil}}
SDK_PATH=$(xcrun --show-sdk-path)
BUILD_DIR="$PROJECT_DIR/.build/manual-integration"
mkdir -p "$BUILD_DIR/ModuleCache"

CLANG_MODULE_CACHE_PATH="$BUILD_DIR/ModuleCache" swiftc \
  -sdk "$SDK_PATH" \
  -target arm64-apple-macosx14.0 \
  -swift-version 5 \
  -parse-as-library \
  Sources/EDIT950/Models.swift \
  Sources/EDIT950/AkaiCommandBuilder.swift \
  Sources/EDIT950/AkaiOutputParser.swift \
  Sources/EDIT950/AkaiCommandController.swift \
  Sources/EDIT950/FileOperations.swift \
  Sources/EDIT950/WAVService.swift \
  Tests/IntegrationRunner.swift \
  -o "$BUILD_DIR/EDIT950IntegrationTests" \
  -framework AppKit \
  -framework AVFoundation

"$BUILD_DIR/EDIT950IntegrationTests" "$AKAIUTIL_PATH"
