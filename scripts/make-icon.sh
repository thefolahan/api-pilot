#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

WORK=$(mktemp -d)
ICONSET="$WORK/AppIcon.iconset"
mkdir -p "$ICONSET" docs

swift scripts/draw-icon.swift "$WORK/icon.png"

for size in 16 32 128 256 512; do
    sips -z $size $size "$WORK/icon.png" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
    sips -z $((size * 2)) $((size * 2)) "$WORK/icon.png" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done

iconutil -c icns "$ICONSET" -o Resources/AppIcon.icns
cp "$WORK/icon.png" docs/icon.png
rm -rf "$WORK"
echo "Wrote Resources/AppIcon.icns"
