A native, local clipboard shelf for macOS 14+. Early Apple Silicon pre-release.

Download **Encore-0.2.0-macOS-arm64.zip**, unzip, and move Encore.app to Applications. No build tools are required. SHA256SUMS contains the archive checksum.

- Native image and PDF thumbnails, rich text cards, clearer keyboard hints and settings.
- Ordered size/type retention rules, explicit first/last-copy timestamps, expiry preview before applying rules.
- Configurable capture/paste sounds, custom files and volume.
- Current, primary, or fixed display placement.
- Opt-in import of new saved macOS screenshots through Spotlight metadata.
- Screen-coordinate resizing and explicit Up/Down navigation.
- Clipboard origin handling across app switches, including explicit source markers.
- Cached previews, an event tap that stops with the queue, and previous-index recovery.

This build is **ad-hoc signed, not notarized**. Follow [Apple's Open Anyway instructions](https://support.apple.com/en-us/102445) if Gatekeeper blocks the first launch. Grant Accessibility only after placing the app in its final location. Replacing an ad-hoc build can require granting that permission again.

Embedded clipboard payloads are limited to 25 MiB. Large files are kept as references. Storage is unencrypted. Saved screenshot import depends on Spotlight. No automatic updates, Intel binary, Homebrew package, or sync yet.

See [validation](https://github.com/Kamasoutra/encore/blob/main/docs/VALIDATION.md) and [feature status](https://github.com/Kamasoutra/encore/blob/main/docs/FEATURES.md) for verified behavior and remaining work.
