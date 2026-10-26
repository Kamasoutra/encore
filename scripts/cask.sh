#!/bin/bash
# Writes the Homebrew cask for one release: scripts/cask.sh <archive.zip> > Casks/encore.rb
set -euo pipefail
cd "$(dirname "$0")/.."
archive="$1"
version=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Resources/Info.plist)
sha256=$(shasum -a 256 "$archive" | cut -d ' ' -f 1)
cat <<EOF
cask "encore" do
  version "$version"
  sha256 "$sha256"

  url "https://github.com/Kamasoutra/encore/releases/download/v#{version}/$(basename "$archive")"
  name "encore"
  desc "Native clipboard manager"
  homepage "https://github.com/Kamasoutra/encore"

  livecheck do
    url :url
    strategy :github_latest
  end

  auto_updates true
  depends_on macos: :monterey

  app "Encore.app"

  zap trash: [
    "~/Library/Application Support/Encore",
    "~/Library/Caches/local.kama.Encore",
    "~/Library/HTTPStorages/local.kama.Encore",
    "~/Library/Preferences/local.kama.Encore.plist",
  ]

  caveats <<~CAVEATS
    encore is not notarized yet. If macOS blocks the first launch, open
    System Settings → Privacy & Security and choose Open Anyway.
    Allow encore in Accessibility so Return pastes directly.
  CAVEATS
end
EOF
