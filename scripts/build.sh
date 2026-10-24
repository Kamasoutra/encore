#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release
bin_path="$(swift build -c release --show-bin-path)"
bundle="dist/Encore.app"
mkdir -p "$bundle/Contents/MacOS" "$bundle/Contents/Resources"
cp "$bin_path/Encore" "$bundle/Contents/MacOS/Encore"
cp Resources/Info.plist "$bundle/Contents/Info.plist"
if [ ! -f dist/Encore.icns ]; then
    swift scripts/icon.swift dist
    iconutil -c icns dist/Encore.iconset -o dist/Encore.icns
fi
cp dist/Encore.icns "$bundle/Contents/Resources/Encore.icns"
codesign --force --sign - --identifier local.kama.Encore "$bundle"
printf 'Built: %s/%s\n' "$PWD" "$bundle"
