<p align="center"><img src="assets/icon.png" width="128" alt="Encore"></p>
<h1 align="center">Encore</h1>
<p align="center"><strong>Your clipboard. Yours to keep.</strong></p>
<p align="center">A native clipboard manager for macOS. Free, open source, and local.<br>No account, no subscription, no cloud.</p>
<p align="center"><a href="https://github.com/Kamasoutra/encore/releases/latest/download/Encore-macOS-arm64.zip"><strong>Download for Apple Silicon ↓</strong></a> · <a href="https://github.com/Kamasoutra/encore/releases">Releases</a></p>
<p align="center">macOS 14+ · 30 languages · MIT</p>

![Encore shelf](assets/shelf-dark.png)

Press **⇧⌘V**, pick an item, press **Return**: it is pasted where you were typing. Press **↑** to grow the shelf into a full library with filters and a large preview.

![Encore library](assets/workspace.png)

## Why Encore

- **Everything you copy.** Text, rich text, links, images, files, code, and colors, each with a card that shows what it is.
- **Find it in seconds.** Search by content, app, type, date, or text recognized in images, on your Mac.
- **Keep what matters.** Favorites, collections, and retention rules by size and type. Every card shows how long it stays.
- **Paste the way you need.** Plain text, multiple items, ⌘1–9 quick paste, and a sequential paste queue.
- **Your other Macs.** Pair two Macs on the same network and browse each other's recent history. End-to-end encrypted, no server.
- **Stays up to date.** Signed updates straight from GitHub releases.
- **Feels native.** Built with SwiftUI and AppKit. Light and dark, right-to-left languages, and quiet sounds you can pick and preview.

## Install

1. [Download the ZIP](https://github.com/Kamasoutra/encore/releases/latest/download/Encore-macOS-arm64.zip), unzip, and move **Encore.app** to **Applications**.
2. Open it. Encore is not notarized yet: if macOS blocks the first launch, follow [Apple's Open Anyway steps](https://support.apple.com/en-us/102445).
3. Allow **System Settings → Privacy & Security → Accessibility** so Return pastes directly. Without it, Encore copies the item and you press ⌘V. The shelf shows a warning until access is granted.

Quit any other clipboard app that uses ⇧⌘V. Encore also lives in the menu bar and answers to **⌃⌥⌘V**. Each release includes a SHA-256 checksum. Intel builds and Homebrew are not available yet.

## Keyboard

| Action | Shortcut |
| --- | --- |
| Show / hide | ⇧⌘V |
| Library | ↑ from the shelf |
| Back to the shelf | Hold ↓ in the library |
| Move / extend selection | Arrows / ⇧ + arrows |
| Paste / plain text | Return / ⇧Return |
| Quick paste | ⌘1–9, including AZERTY |
| Search / preview | ⌘F or type / Space |
| Switch board | ⌘← / ⌘→ |
| Favorite / settings | ⌘D / ⌘, |
| Delete / undo | Delete / ⌘Z |
| Card size | ⌘+ / ⌘− |

Search understands `app:safari type:link`, `date:today`, `date:7d`, `date:30d`, and `after:2026-10-01 before:2026-11-01`. The optional global queue shortcut ⇧⌘C is off by default.

## Keep the useful things

Retention rules are evaluated from top to bottom, and the first match wins. The presets use explicit ranges:

| Content size | Retention |
| --- | --- |
| 3 GB and above | 1 hour |
| 500 MB to less than 3 GB | 2 days |
| 300 MB to less than 500 MB | 1 week |
| Text below 1 MB | Forever |
| Everything else | Your default duration |

Copying an item again renews its expiry. Favorites and collection items stay indefinitely. Changes are previewed before you apply them.

Files are referenced rather than copied into Encore, so a multi-gigabyte file uses little storage. Moving or deleting the original can make an entry unavailable. Embedded clipboard data is limited to **25 MiB per copy**.

## Your data

History lives in `~/Library/Application Support/Encore/` and never leaves your Mac unless you turn on sharing. There is no account, telemetry, or remote link preview. Storage and exported backups are **unencrypted** and restricted to your macOS account.

Encore makes two kinds of network requests, both optional:

- **Updates.** Encore checks GitHub for a new release, and installs it only if it is signed with the project's key. You can turn this off in Settings.
- **Other Macs.** Off until you enable it. Macs find each other on the local network with Bonjour and pair with a 6-digit code. Traffic is end-to-end encrypted, and the keys stay in each Mac's Keychain.

Defaults are 30 days, 2,000 unprotected items, and a 500 MiB content budget. Password-manager exclusions depend on installed apps. Confidential clipboard markers are honored, but not every app sets them. Screenshot import is off by default.

## Development

Swift 5.10+, macOS 14+. The only dependency is [Sparkle](https://sparkle-project.org) for updates.

```sh
git clone https://github.com/Kamasoutra/encore.git
cd encore
swift test
bash scripts/build.sh
open dist/Encore.app
```

Use `open -n dist/Encore.app --args --demo` for a separate, synthetic library. Quit the normal instance first. Without the release certificate, the build script signs ad hoc.

Encore is independently implemented and includes no code or assets from other clipboard apps. The default sound sets are synthesized by `scripts/sounds.py`. The Soft, Crisp and Wood sets are adapted from [Kenney's Interface Sounds](https://kenney.nl/assets/interface-sounds), released under CC0.

[Contributing](CONTRIBUTING.md) · [Security](SECURITY.md) · [MIT license](LICENSE)
