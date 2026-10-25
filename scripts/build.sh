#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release
bin_path="$(swift build -c release --show-bin-path)"
bundle="dist/Encore.app"
rm -rf "$bundle"
mkdir -p "$bundle/Contents/MacOS" "$bundle/Contents/Resources" "$bundle/Contents/Frameworks"
cp "$bin_path/Encore" "$bundle/Contents/MacOS/Encore"
install_name_tool -add_rpath @executable_path/../Frameworks "$bundle/Contents/MacOS/Encore"
ditto "$bin_path/Sparkle.framework" "$bundle/Contents/Frameworks/Sparkle.framework"
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
# A stable identity keeps macOS privacy permissions across updates; ad-hoc signing is the fallback.
identity="${ENCORE_SIGNING_IDENTITY:-}"
if [ -z "$identity" ]; then
    if security find-certificate -c "Encore Developer" >/dev/null 2>&1; then identity="Encore Developer"; else identity="-"; fi
fi
sparkle="$bundle/Contents/Frameworks/Sparkle.framework/Versions/B"
for item in "$sparkle"/XPCServices/*.xpc "$sparkle/Autoupdate" "$sparkle/Updater.app"; do
    codesign --force --sign "$identity" --preserve-metadata=entitlements "$item"
done
codesign --force --sign "$identity" "$bundle/Contents/Frameworks/Sparkle.framework"
codesign --force --sign "$identity" --identifier local.kama.Encore "$bundle"
printf 'Built: %s/%s (signed with %s)\n' "$PWD" "$bundle" "$identity"
