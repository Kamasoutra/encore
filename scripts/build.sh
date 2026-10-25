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
for resources in "$bin_path"/Encore_*.bundle; do
    if [ -d "$resources" ]; then
        ditto "$resources" "$bundle/Contents/Resources/$(basename "$resources")"
    fi
done
for lproj in "$bundle"/Contents/Resources/Encore_EncoreCore.bundle/Contents/Resources/*.lproj; do
    code="$(basename "$lproj" .lproj)"
    /usr/libexec/PlistBuddy -c "Print :CFBundleLocalizations" "$bundle/Contents/Info.plist" | grep -qx "    $code" || { echo "CFBundleLocalizations is missing $code" >&2; exit 1; }
done
codesign --force --sign "${ENCORE_SIGNING_IDENTITY:--}" --identifier local.kama.Encore "$bundle"
printf 'Built: %s/%s\n' "$PWD" "$bundle"
