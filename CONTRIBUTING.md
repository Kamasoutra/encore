# Contributing

Use Xcode 15.3+ with macOS 14+. Open `Package.swift` in Xcode or build from the command line.

```sh
swift test
bash scripts/build.sh
```

`EncoreCore` contains the content model, retention policy, filters, and text transformations. `Encore` contains the AppKit lifecycle and integrations, SwiftUI interface, and local Vision OCR. Core also owns persistence and portable backup validation. The only third-party dependency is Sparkle, for updates.

Keep changes focused. Include meaningful tests for data preservation, privacy decisions, filters, retention, and transformations. For interface or keyboard changes, verify the actual app and report the macOS version, architecture, and behavior you observed.

Test at least: ⇧⌘V from another app; arrows and Return; Escape returning to the source app; search then Return; plain-text paste; image and multiple-file capture; a restart; and queue order. Accessibility permission is necessary for direct paste and the queue. Test both with and without that permission.

Use `--demo` for screenshots. Never commit clipboard databases, backups, receipts, credentials, personal screenshots, or build output. Do not include real clipboard content in bug reports.

Please discuss changes that introduce networking, telemetry, cloud synchronization, or new permissions before implementing them. Sharing between paired Macs stays on the local network and end-to-end encrypted. The default experience must remain local and usable without an account.

Tagged releases use `.github/workflows/release.yml`: a matching `v<CFBundleShortVersionString>` tag tests and packages a signed universal (arm64 and x86_64) build, then publishes the ZIP, a SHA-256 checksum and the Sparkle `appcast.xml`. Never include signing credentials or clipboard data in the repository.
