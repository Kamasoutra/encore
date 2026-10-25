# Validation

25 October 2026. Development machine: Apple Silicon, macOS 26.6.2, Xcode 27.1 / Swift 6.4, Swift 5 language mode. Minimum deployment target: macOS 14.

## Automated

`swift test`: **65 tests** across the core and app targets, with no failures. Tests cover:

- Classification, deduplication, rich/custom representations, multiple files, size limits, sensitive markers and source attribution across app switches.
- Ordered size/type retention, boundaries, fallback, calendar duration, recopy timestamps, pin/count exemptions and rule application preview.
- Finder file-reference URLs resolve to paths and follow a rename, preserving the original pasteboard representation, filename and logical size.
- A sparse 3 GB file reference: metadata used for expiry without reading/copying the file or deleting its original.
- Preference migration, retention/screenshot/sound/display options, and opt-in queue shortcut persistence.
- AZERTY/QWERTY physical number-row shortcuts and contrasting labels on white/black/transparent swatches.
- Search, transformations, selection ranges, deletion/undo, edits, FIFO queue delivery and plain-text restore.
- Storage serialization, file permissions, write-failure protection, corrupt-index failure, backup-index recovery with the damaged file preserved, and portable backup validation.
- A real local Vision OCR request on a generated image.
- Screenshot image validation, opt-in/pause/exclusion checks, preserved capture date, and unchanged isolated clipboard.
- Availability of all named system sounds; display identity/fallback behavior against the actual connected screen inventory.

Pasteboard tests use unique isolated pasteboards, not the user's general clipboard. Model tests use temporary storage and synthetic fixtures.

`bash scripts/build.sh`, `plutil -lint`, and `codesign --verify --strict` validate the local arm64 app bundle. The tag workflow repeats tests/build and publishes a ZIP/checksum only after bundle validation.

## Actual native UI

The app was launched with `--demo`, using original generated text, PNG and PDF content, separately from the user's library. Native screenshots were inspected, rather than a mockup.

Observed:

- Dark shelf renders rich text, full-size PNG/PDF thumbnails, type/source headers, centered collections, side search, and larger keyboard hints.
- Repeated Up presses retain card selection, an empty search, and all nine demo items. Right/Left changes the selected card.
- Dragging the native handle by 170 screen points changes shelf height from 380 to 550, keeping the bottom edge at the same screen coordinate.
- Space opens the independent 740 × 700 content inspector even when the shelf is below 300 points. Closing returns to the shelf.
- Down dismisses the shelf from the cards.
- Settings renders the native sidebar; clicking Privacy shows actual names/icons for excluded apps. Down from the focused sidebar advances to Retention.
- Settings and the shelf were also visually checked in light mode; the shortcut tab has readable labels/keycaps in both themes. Loading retention examples creates a draft without applying or deleting anything.

The computer-use connector's panel snapshots repeatedly failed its stale-window guard. Keyboard/drag checks were therefore performed through the macOS Accessibility API and native CGEvents against the demo process, with live AX state and window frames read back. This does not establish physical-device usability or frame-rate performance.

Public screenshots contain only synthetic demo data.

The installed 0.2.0 build exposed a Finder-specific file-reference URL case in the real library. Version 0.2.1 resolves these URLs before thumbnail/metadata operations, with two regression tests (including a rename). A diagnostic run against real image/PDF entries returned readable files and successful Quick Look representations. The macOS session then locked, so the corrected real-library thumbnails have not received a final visual check. Existing library entries were preserved during installation checks.

## Not yet established end to end

- Direct paste/focus restoration into another app and interception of repeated physical ⌘V: the newly ad-hoc-signed app lacks Accessibility authorization. Tests of payload/queue logic do not establish these outcomes.
- Audio actually heard at the speakers, including capture and Return-triggered paste. Sound resources and event wiring are checked; auditory quality needs user feedback.
- Native saved screenshot → Spotlight metadata update → watcher import. Import logic is tested; indexing delays, privacy permissions and folder exclusions still need live validation.
- Current/fixed display placement through a full user journey, mixed-DPI displays, and full-screen Spaces. Screen inventory/fallback logic is tested.
- Launch at login, VoiceOver/high contrast, macOS 14 compatibility, Intel hardware, quarantined first launch, and a complete large-library performance/security audit.

The JSON index's synchronous initial load and snapshot write cost remain known limitations. Treat 0.2.1 as a pre-release, not as fully validated parity with Paste.
