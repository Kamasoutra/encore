# Encore

**Your clipboard. Yours to keep.**

A native, local-first clipboard manager for macOS. Press **⇧⌘V**, browse a visual shelf of everything you copied, and paste without breaking your flow. No subscription, account, telemetry, or runtime dependencies. MIT licensed.

## Features

- A resizable shelf at the bottom of the active display, including full-screen Spaces.
- Preview cards for text, links, images, files, code, and hex colors.
- Original pasteboard representations retained, including rich text and multiple files.
- Keyboard navigation, quick paste with ⌘1–9, plain-text paste, and multiple selection.
- Search by content, source app, type, and dates, ignoring case and accents.
- Local image OCR using Apple Vision; recognized words become searchable.
- Favorites and collections. An item can belong to several collections.
- A sequential paste queue: collect copies, then paste them in order with ⌘V.
- Preview and edit text; transform a copy using JSON formatting, Base64, case conversion, URL decoding, or tracking-parameter removal.
- Undo deletion, configurable retention, capture pause, app exclusions, and size limits.
- Light, dark, and system appearance, compact cards, launch at login.
- Portable JSON backup and restore.

The interface is currently in French. Requires **macOS 14 or later**. Builds natively for the build machine's architecture; Apple Silicon is the primary development target.

## Build and run

Install Xcode 15.3 or later (Swift 5.10+) and select its command-line tools.

```sh
git clone https://github.com/Kamasoutra/encore.git
cd encore
swift test
bash scripts/build.sh
open dist/Encore.app
```

Move `dist/Encore.app` into your Applications folder before granting permissions or enabling launch at login. The build script creates an ad-hoc signed app bundle with its icon; it does not require a paid Apple Developer account. Public distribution with Developer ID signing and notarization is not configured yet.

To inspect the UI with synthetic content without capturing or opening your real library:

```sh
open -n dist/Encore.app --args --demo
```

Demo mode uses a separate temporary library. Do not run demo and normal instances at the same time: global keyboard shortcuts are shared by all apps.

## First use

1. Quit any clipboard app already using ⇧⌘V. Encore detects shortcut conflicts and retains the fallback **⌃⌥⌘V**.
2. Copy text, an image, a link, or files in another app.
3. Open Encore with ⇧⌘V or its menu-bar icon. Select a card and press Return.
4. Enable Encore in **System Settings → Privacy & Security → Accessibility** to paste directly at the cursor and use the sequential queue. Without permission, Encore copies your selection and you press ⌘V yourself.

The first launch does not capture the pre-existing clipboard. Capture starts with the next copy. Password managers and content marked confidential or transient are excluded by default. Browser extensions do not always set these markers; exclude their host app if needed.

## Keyboard

| Action | Shortcut |
| --- | --- |
| Show / hide | ⇧⌘V (or ⌥⌘V in Settings) |
| Emergency show / hide | ⌃⌥⌘V |
| Sequential queue | ⇧⌘C |
| Navigate / extend selection | ← → / ⇧← ⇧→ |
| Paste / plain text | Return / ⇧Return |
| Quick paste | ⌘1–9 (add ⇧ for plain text) |
| Preview / edit | Space / ⌘E |
| Search | Type, or ⌘F |
| Move focus between search and cards | Tab |
| Favorite | ⌘D |
| Add selection to queue | ⇧⌘Return |
| New text / collection | ⌘N / ⇧⌘N |
| Select all / copy selection | ⌘A / ⌘C |
| Delete / undo deletion | Delete / ⌘Z |
| Next / previous collection | ⌘→ / ⌘← |
| Pause capture / settings | ⌘T / ⌘, |
| Clear search, then dismiss | Escape |

Search examples: `app:safari type:link`, `type:image invoice`, `date:today`, `after:2026-10-01 before:2026-11-01`. Dates use your Mac's time zone; `before:` excludes that day.

## Data and privacy

- No network requests, third-party SDKs, analytics, or remote link previews.
- Library: `~/Library/Application Support/Encore/`. Preferences: macOS UserDefaults under `local.kama.Encore`.
- Stored content and exported backups are **not encrypted**. The library directory is owner-only (0700), with owner-only files (0600). FileVault can protect the volume at rest.
- Files are stored as references. Moving or deleting the originals can make those clipboard entries unusable. Backups do not copy referenced files.
- Defaults: 30 days, 2,000 unprotected items, 500 MB of raw content. Favorites and collection members are exempt from time/count eviction. A single copy is limited to 25 MB. Encoding, metadata, and the OCR cache add storage overhead.
- When the content budget is full, new items are skipped and a notice is shown. Existing items are not silently evicted to make room.
- The queue only observes ⌘V while explicitly active and does not log other keystrokes. Synthetic paste events bypass the queue.
- OCR runs locally. No screen recording permission is requested.

Changing app exclusions does not delete previously saved items. Clearing history preserves favorites and collections and asks for confirmation. Deleting a collection keeps its items in history.

## Scope

Encore is an independent implementation inspired by the visual clipboard workflow. It uses no Paste code, branding, or assets, and does not change your Paste installation or library.

This initial release focuses on a complete local Mac workflow. It does **not** yet include iPhone/iPad apps, iCloud sync, collaborative boards, an MCP server, AI context suggestions, or import of Paste's proprietary database. No claims of full feature parity or a completed security audit are made.

See [the feature notes](docs/FEATURES.md), [validation and remaining interactive checks](docs/VALIDATION.md), [contributing guide](CONTRIBUTING.md), and [security policy](SECURITY.md).

## License

[MIT](LICENSE).
