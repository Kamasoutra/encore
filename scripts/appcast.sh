#!/bin/bash
# Writes the Sparkle feed for one release: scripts/appcast.sh <archive.zip> '<sign_update output>' > appcast.xml
set -euo pipefail
cd "$(dirname "$0")/.."
archive="$1"
signature="$2"
version=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Resources/Info.plist)
build=$(/usr/libexec/PlistBuddy -c 'Print CFBundleVersion' Resources/Info.plist)
minimum=$(/usr/libexec/PlistBuddy -c 'Print LSMinimumSystemVersion' Resources/Info.plist)
repository="https://github.com/Kamasoutra/encore"
notes=$(sed -n 's/^- \(.*\)$/<li>\1<\/li>/p' .github/RELEASE_NOTES.md)
cat <<EOF
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
<channel>
<title>Encore</title>
<link>$repository</link>
<item>
<title>Encore $version</title>
<pubDate>$(LC_ALL=C date -u '+%a, %d %b %Y %H:%M:%S +0000')</pubDate>
<sparkle:version>$build</sparkle:version>
<sparkle:shortVersionString>$version</sparkle:shortVersionString>
<sparkle:minimumSystemVersion>$minimum</sparkle:minimumSystemVersion>
<sparkle:fullReleaseNotesLink>$repository/releases/tag/v$version</sparkle:fullReleaseNotesLink>
<description><![CDATA[<ul>$notes</ul>]]></description>
<enclosure url="$repository/releases/download/v$version/$(basename "$archive")" type="application/octet-stream" $signature />
</item>
</channel>
</rss>
EOF
