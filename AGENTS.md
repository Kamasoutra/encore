# Agent notes

Read CONTRIBUTING.md first. These rules cover what the code does not make obvious.

## Build and verify

- `swift test` must pass before every commit.
- `bash scripts/build.sh` builds `dist/Encore.app`. Interface or keyboard changes are verified in the running app, not only in tests.
- `--demo` runs a separate, synthetic library for screenshots.

## Localization

- Every user-facing string goes through `L("English source text")`. The key is the English text itself, with interpolations as `\(value)`.
- A new key is added to `Localizable.strings` in all 30 folders under `Sources/EncoreCore/Resources/`. `LocalizationTests` fails if a language misses a key or has an empty value.
- Plurals go in `Localizable.stringsdict`, never in `L("…(s)")`.
- When the same English word needs two translations, disambiguate the key (`"Edit menu" = "Edit";`).
- Dates, durations, sizes and numbers use the `Localization` helpers, never a fixed format.
- Remove a key from every language when the code stops using it.

## Commits

- One focused change per commit. Subject in English, imperative, one line, no prefix (`Add …`, `Allow …`, `Show …`).
- No co-author, tool or agent attribution in commits.

## Releases and signing

- A release bumps `CFBundleShortVersionString` and always increases `CFBundleVersion`: Sparkle compares the build number.
- Update `.github/RELEASE_NOTES.md`, then push a `v<version>` tag. The workflow signs with the "Encore Developer" certificate, signs the archive for Sparkle and publishes `appcast.xml`.
- Never change `SUFeedURL`, `SUPublicEDKey` or the signing identity: installed copies would stop updating or lose their Accessibility grant.
- Signing keys live outside the repository and in GitHub secrets. Never commit them.

## Generated assets

- Sounds: `scripts/sounds.py` (deterministic). The default theme is Paper; keep the older themes.
- App icon: `scripts/icon.swift`, run by the build. The menu bar icon is drawn in `EncoreApp.statusImage`.

## Peer sharing

- Messages are versioned by `PeerProtocol.version`. Bump it for any incompatible message change.
- Sharing stays local network only, end-to-end encrypted, with no server or account.

## Interface

- The shelf and the library share `ClipCard`. Keep both modes consistent when changing a card.
- Propose larger visual changes as a mockup before implementing them.
