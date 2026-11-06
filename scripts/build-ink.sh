#!/bin/bash
# Baut native/bin/kt-ink (Handschrift → Text mit Vision) für Apple Silicon und Intel, ab macOS 13.
# Signiert wird es später von electron-builder zusammen mit der App.
set -euo pipefail
cd "$(dirname "$0")/.."
OUT=native/bin; TMP=$(mktemp -d); mkdir -p "$OUT"
for a in arm64 x86_64; do
  xcrun swiftc -O -target "$a-apple-macos13" native/ink/main.swift -o "$TMP/kt-ink-$a"
done
lipo -create "$TMP/kt-ink-arm64" "$TMP/kt-ink-x86_64" -output "$OUT/kt-ink"
rm -rf "$TMP"
lipo -info "$OUT/kt-ink"
