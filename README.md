<p align="center"><img src="assets/icon.png" width="104" alt="Encore"></p>
<h1 align="center">Encore</h1>
<p align="center"><strong>Your clipboard. Yours to keep.</strong></p>
<p align="center">A native clipboard manager for macOS. Local, open source, subscription-free.</p>
<p align="center"><a href="https://github.com/Kamasoutra/encore/releases/download/v0.3.0/Encore-0.3.0-macOS-arm64.zip"><strong>Download for Apple Silicon ↓</strong></a> · <a href="https://github.com/Kamasoutra/encore/releases">Releases</a></p>
<p align="center">macOS 14+ · Français / English · MIT</p>

![Encore clipboard shelf](assets/shelf-dark.png)

<details>
<summary>Full library view</summary>

![Searchable library with filters and preview](assets/workspace.png)

</details>

Press **⇧⌘V** to open your clipboard history. Choose an item and press **Return** to paste. Press **↑** for the full library, with a searchable list, filters, and a preview. **↓** brings you back to the shelf.

- Text, rich text, links, images, files, code, and colors.
- Native image and document thumbnails, including files copied from Finder.
- Search by content, application, type, date, and locally recognized image text.
- Favorites, collections, plain-text paste, multi-selection, and a sequential paste queue.
- Retention rules by size and type, with first/last-copy timestamps and time remaining before expiry.
- Quiet sound sets, custom audio, card zoom, and a choice of display.
- Installed-app exclusions and optional import of newly saved macOS screenshots.
- French and English, with automatic or manual language selection.

## Install

[Download the ZIP](https://github.com/Kamasoutra/encore/releases/download/v0.3.0/Encore-0.3.0-macOS-arm64.zip), unzip, and move **Encore.app** to Applications. Quit any clipboard app already using ⇧⌘V. Encore also has a menu-bar button and the fallback shortcut **⌃⌥⌘V**.

These early builds are **ad-hoc signed and not notarized**. If macOS blocks the first launch, follow [Apple's Open Anyway instructions](https://support.apple.com/en-us/102445). Releases include a SHA-256 checksum. Intel builds, automatic updates, and Homebrew are not available yet.

Direct paste needs **System Settings → Privacy & Security → Accessibility**. Ad-hoc updates can invalidate an earlier grant even when Encore still appears enabled: turn the entry off and on, or remove it and add the installed app again. Without access, Encore copies the item and you paste with ⌘V.

## Keep the useful things

Retention rules are evaluated from top to bottom. The first match wins. The presets use explicit ranges:

| Content size | Retention |
| --- | --- |
| 3 GB and above | 1 hour |
| 500 MB to less than 3 GB | 2 days |
| 300 MB to less than 500 MB | 1 week |
| Text below 1 MB | Forever |
| Everything else | Your default duration |

Re-copying an item renews its expiry. Favorites and collection items stay indefinitely. Changes are previewed before you apply them; existing rules are never silently replaced by a new preset.

File rules use the original files' logical size. Files are referenced rather than copied into Encore, so a multi-gigabyte file reference uses little storage. Moving or deleting originals can make an entry unavailable. Embedded clipboard data is limited to **25 MiB per copy**.

## Keyboard

| Action | Shortcut |
| --- | --- |
| Show / hide | ⇧⌘V |
| Full library / reduce | ↑ / ↓ |
| Select / extend selection | ← → / ⇧← ⇧→ |
| Paste / plain text | Return / ⇧Return |
| Quick paste | ⌘1–9, including AZERTY |
| Search / preview | ⌘F / Space |
| Favorite / settings | ⌘D / ⌘, |
| Delete / undo | Delete / ⌘Z |
| Card size | ⌘+ / ⌘− |

Search supports `app:safari type:link`, `date:today`, `date:week`, and `after:2026-10-01 before:2026-11-01`. The optional global queue shortcut ⇧⌘C is off by default.

## Your data

No account, telemetry, remote link previews, or network requests in the app. History lives in `~/Library/Application Support/Encore/`; preferences use the `local.kama.Encore` defaults domain. Storage and exported backups are **unencrypted** and restricted to your macOS account.

Defaults are 30 days, 2,000 unmatched/unprotected items, and a 500 MiB raw-content budget. Pins and rule-managed items bypass the count limit. A full content budget refuses new copies with a notice. Metadata, encoding, and recovery files add disk overhead.

Password-manager exclusions depend on installed apps. Confidential/transient clipboard markers are honored, but not every app supplies them. Screenshot import is off by default, depends on Spotlight, and watches only newly saved screenshots in your chosen folder while Encore is running.

## Development

Swift 5.10+, macOS 14+, no third-party runtime dependencies.

```sh
git clone https://github.com/Kamasoutra/encore.git
cd encore
swift test
bash scripts/build.sh
open dist/Encore.app
```

Use `open -n dist/Encore.app --args --demo` for a separate, synthetic library. Quit the normal instance first. For development builds, `ENCORE_SIGNING_IDENTITY` lets the build script reuse an existing code-signing identity; the default is ad hoc.

Encore is independently implemented and includes no Paste code or assets. The default sound sets are synthesized by `scripts/sounds.py`; the Soft, Crisp and Wood sets are adapted from [Kenney's Interface Sounds](https://kenney.nl/assets/interface-sounds), released under CC0. Attribution and source notes are bundled with the sounds.

[Contributing](CONTRIBUTING.md) · [Security](SECURITY.md) · [MIT license](LICENSE)
