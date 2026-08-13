#!/bin/sh
set -eu

if [ "$#" -ne 2 ]; then
  echo "usage: $0 <fixture.img> <trusted-upstream-x86_64-akaiutil>" >&2
  exit 2
fi

PROJECT_DIR=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
FIXTURE=$1
TRUSTED=$2
HELPER="$PROJECT_DIR/.build/akaiutil-equivalence/akaiutil"
ROOT=$(mktemp -d "${TMPDIR:-/tmp}/akaiutil-equivalence.XXXXXX")
trap 'rm -rf "$ROOT"' EXIT HUP INT TERM

test -f "$FIXTURE"
test -x "$TRUSTED"
"$PROJECT_DIR/Scripts/build-akaiutil-universal.sh" "$HELPER" >/dev/null

for MODE in arm64 x86_64 upstream; do
  mkdir "$ROOT/$MODE"
  if [ "$MODE" = upstream ]; then
    RUN_ARCH=x86_64
    EXECUTABLE=$TRUSTED
  else
    RUN_ARCH=$MODE
    EXECUTABLE=$HELPER
  fi

  printf 'dirrec\nq\n' \
    | arch -"$RUN_ARCH" "$EXECUTABLE" -r "$FIXTURE" \
      > "$ROOT/$MODE/directory.log" 2>&1
  VOLUME=$(sed -n 's/^\(\/disk[0-9][0-9]*\/[A-Z]\/[^>]*\).*/\1/p' "$ROOT/$MODE/directory.log" \
    | sed 's/[[:space:]]*$//' | head -1)
  if [ -z "$VOLUME" ]; then
    echo "could not discover a volume in $FIXTURE" >&2
    exit 1
  fi
  (cd "$ROOT/$MODE" && printf 'cd %s\ngetall\nq\n' "$(printf '%s' "$VOLUME" | tr ' ' '_')" \
    | arch -"$RUN_ARCH" "$EXECUTABLE" -r "$FIXTURE" > export.log 2>&1)
  (cd "$ROOT/$MODE" && find . -maxdepth 1 -type f \
    ! -name '*.log' ! -name manifest.txt -print | LC_ALL=C sort \
    | while IFS= read -r FILE; do shasum -a 256 "$FILE"; done > manifest.txt)
done

cmp "$ROOT/arm64/manifest.txt" "$ROOT/x86_64/manifest.txt"
cmp "$ROOT/arm64/manifest.txt" "$ROOT/upstream/manifest.txt"

SDK_PATH=$(xcrun --show-sdk-path)
swiftc -sdk "$SDK_PATH" -target arm64-apple-macosx14.0 -parse-as-library \
  "$PROJECT_DIR/Sources/EDIT950/P9Program.swift" \
  "$PROJECT_DIR/Tests/NativeP9LoadRunner.swift" \
  -o "$ROOT/NativeP9LoadRunner"
for MODE in arm64 x86_64 upstream; do
  "$ROOT/NativeP9LoadRunner" "$ROOT/$MODE"
done

COUNT=$(wc -l < "$ROOT/arm64/manifest.txt" | tr -d ' ')
printf 'byte-equivalent exports: %s files (%s)\n' "$COUNT" "$(basename "$FIXTURE")"
