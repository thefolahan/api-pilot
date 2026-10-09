#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

APP=build/Specline.app
ARCHS=(--arch arm64 --arch x86_64)

swift build -c release "${ARCHS[@]}"
BIN="$(swift build -c release "${ARCHS[@]}" --show-bin-path)/Specline"

[ -f Resources/AppIcon.icns ] || scripts/make-icon.sh

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Specline"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

codesign --force --options runtime --sign "${SIGN_IDENTITY:--}" "$APP"
echo "Built $APP"

if [ "${1:-}" = "--dmg" ]; then
    STAGE=build/dmg
    rm -rf "$STAGE" build/Specline.dmg
    mkdir -p "$STAGE"
    cp -R "$APP" "$STAGE/"
    ln -s /Applications "$STAGE/Applications"
    hdiutil create -volname Specline -srcfolder "$STAGE" -ov -format UDZO build/Specline.dmg >/dev/null
    rm -rf "$STAGE"
    echo "Built build/Specline.dmg"
fi
