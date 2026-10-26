#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
# Universal binary: one download for Apple Silicon and Intel.
build=(swift build -c release --arch arm64 --arch x86_64)
"${build[@]}"
bin_path="$("${build[@]}" --show-bin-path)"
bundle="dist/Encore.app"
rm -rf "$bundle"
mkdir -p "$bundle/Contents/MacOS" "$bundle/Contents/Resources" "$bundle/Contents/Frameworks"
cp "$bin_path/Encore" "$bundle/Contents/MacOS/Encore"
install_name_tool -add_rpath @executable_path/../Frameworks "$bundle/Contents/MacOS/Encore"
ditto "$bin_path/Sparkle.framework" "$bundle/Contents/Frameworks/Sparkle.framework"
cp Resources/Info.plist "$bundle/Contents/Info.plist"
if [ ! -f dist/Encore.icns ] || [ scripts/icon.swift -nt dist/Encore.icns ]; then
    swift scripts/icon.swift dist
    iconutil -c icns dist/Encore.iconset -o dist/Encore.icns
fi
cp dist/Encore.icns "$bundle/Contents/Resources/Encore.icns"
for resources in "$bin_path"/Encore_*.bundle; do
    if [ -d "$resources" ]; then
        ditto "$resources" "$bundle/Contents/Resources/$(basename "$resources")"
    fi
done
# SwiftPM versions differ on the resource bundle layout and on the case of folder names.
tables=$(find "$bundle/Contents/Resources/Encore_EncoreCore.bundle" -maxdepth 3 -type d -name '*.lproj')
[ -n "$tables" ] || { echo "No localization tables in Encore_EncoreCore.bundle:" >&2; find "$bin_path" -maxdepth 3 -name '*.bundle' >&2; exit 1; }
for lproj in $tables; do
    code="$(basename "$lproj" .lproj)"
    /usr/libexec/PlistBuddy -c "Print :CFBundleLocalizations" "$bundle/Contents/Info.plist" | grep -qix "    $code" || { echo "CFBundleLocalizations is missing $code" >&2; exit 1; }
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
