#!/bin/sh
set -eu

PROJECT_DIR=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
SOURCE_DIR="$PROJECT_DIR/ThirdParty/akaiutil-4.6.7"
OUTPUT=${1:-"$PROJECT_DIR/.build/akaiutil-universal/akaiutil"}
case "$OUTPUT" in /*) ;; *) OUTPUT="$PROJECT_DIR/$OUTPUT" ;; esac
OUTPUT_DIR=$(dirname "$OUTPUT")
INTERMEDIATE_DIR="$PROJECT_DIR/.build/akaiutil-universal/slices"
SDK_PATH=$(xcrun --show-sdk-path)
SOURCES="akaiutil_main.c akaiutil_tar.c akaiutil_file.c akaiutil_take.c akaiutil_wav.c akaiutil.c akaiutil_io.c commonlib.c"

mkdir -p "$OUTPUT_DIR" "$INTERMEDIATE_DIR"
cd "$SOURCE_DIR"
for HELPER_ARCH in arm64 x86_64; do
  # shellcheck disable=SC2086
  xcrun clang -isysroot "$SDK_PATH" -arch "$HELPER_ARCH" \
    -mmacosx-version-min=14.0 -Wall -Wextra -O2 \
    $SOURCES -lm -o "$INTERMEDIATE_DIR/akaiutil-$HELPER_ARCH"
done

/usr/bin/lipo -create \
  "$INTERMEDIATE_DIR/akaiutil-arm64" "$INTERMEDIATE_DIR/akaiutil-x86_64" \
  -output "$OUTPUT"
chmod 755 "$OUTPUT"

ARCHS=$(/usr/bin/lipo -archs "$OUTPUT")
case " $ARCHS " in *" arm64 "*) ;; *) echo "missing arm64 slice" >&2; exit 1 ;; esac
case " $ARCHS " in *" x86_64 "*) ;; *) echo "missing x86_64 slice" >&2; exit 1 ;; esac
printf '%s\n' "$ARCHS"
