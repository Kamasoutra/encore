# Validation

Initial development: 25 October 2026, on an Apple Silicon Mac running macOS 26.6.2, using Xcode 27.1 / Swift 6.4 in Swift 5 language mode.

## Automated checks

`swift test`: **39 tests passing** across `EncoreCoreTests` and `EncoreAppTests`.

Covered behavior:

- Recopying preserves favorites, collection memberships, and OCR text.
- Retention and count limits never remove protected items.
- Content classification distinguishes URLs, code, colors, images, files, and ordinary numeric codes.
- Capture preserves rich/custom representations, long text, and multiple file entries.
- Sensitive/transient markers in any pasteboard item prevent capture.
- Oversize copies are rejected.
- Search combines content, source, kind, favorites, collections, local dates, and recognized image text.
- JSON, Base64, URL, and tracking-parameter transformations preserve the intended data.
- Persistence survives reopening, uses owner-only permissions, serializes writes, removes deleted payloads, and stops committing queued snapshots after a write failure.
- Corrupt metadata raises an error instead of silently returning an empty library.
- Backup restore validates payload sizes, recomputes hashes/counts, merges pins/collections, handles ID collisions, and deduplicates content.
- Model selection extends and shrinks ranges correctly and does not wrap past the ends.
- Deletion cleans the queue, and undo restores content and metadata.
- Editing to existing content merges pins without duplicate cards.
- Queue delivery preserves FIFO order, disarms on completion, and stops on a missing payload.
- Plain-text copying strips styles without modifying the retained original.
- A real Apple Vision request recognizes a generated test image, and its text becomes searchable.

Pasteboard tests use uniquely named, isolated macOS pasteboards; they do not inspect or overwrite the user's general clipboard. OCR tests generate their own image. Demo/model tests use a temporary library.

`bash scripts/build.sh` produces an arm64 app bundle on the development Mac. The bundle is checked with `plutil -lint` and `codesign --verify --strict`.

## Native visual check

The actual application was launched in demo mode and its dark horizontal shelf was visually inspected: toolbar, source-app icons, text/link/color/code cards, selection outline, collections, search, and keyboard hints were rendered. This is an app-window check, not a web mockup.

## Still requiring interactive validation

The macOS session locked during the native UI session. These end-to-end paths have not yet been verified on the development Mac:

- Global shortcuts while another app is active, including conflicts.
- Restoring focus and pasting directly into TextEdit with Accessibility permission.
- Native event-tap interception of repeated physical ⌘V presses in another app.
- Search-field focus changes, inspector sheets, drag/drop, resizing, both themes, full-screen Spaces, and multiple displays.
- Launch at login, and running on macOS 14/15 or Intel hardware.

Automated tests for the underlying behavior do not establish these interactive outcomes. Treat version 0.1.0 as an early release until these checks are completed.
