# Feature status

Updated 25 October 2026 for the 0.2.1 pre-release. “Implemented” describes the code; it does not mean every macOS interaction has been validated. See [validation evidence and limits](VALIDATION.md).

| Area | Implemented | Remaining work |
| --- | --- | --- |
| Clipboard history | Text, links, code, colors, images, rich representations, multi-file references, deduplication | Measure very large libraries; transactional storage/indexing |
| Shelf | Native horizontal panel, thumbnails, rich text, type headers, source icons, clearer shortcut hints, zoom | Further visual polish; contrast/high-contrast and VoiceOver audit |
| Resizing | Native drag handle using fixed screen coordinates, final height committed on mouse-up | Longer physical-use testing across mixed display scaling |
| Keyboard | Arrows, Up no-op, Down dismiss, quick paste on physical number keys including AZERTY, search, plain paste, selections | Fully configurable shortcut recorder |
| Shortcuts | Main ⇧⌘V or ⌥⌘V, emergency fallback, optional global queue shortcut off by default | Additional shortcut choices and richer conflict UI |
| Origin | Explicit pasteboard source marker; drain pending copies before an active-app change | Universal reliable attribution is unavailable without source markers |
| Retention | Ordered size/type rules, first match, duration/forever, timestamps, recopy renewal, impact preview, fallback | More rule templates, usage visualization |
| Large files | Referenced logical size used by rules, no copy of file contents | Embedded payloads remain limited to 25 MiB; directories have unknown size |
| Organization | Favorites and multiple collections per item | Collection rename/reorder, more metadata and snippet workflows |
| Search | Content, kind, app, dates, accents, local Vision OCR | Full-text database index, saved searches |
| Preview/editor | Native file thumbnails, independent resizable inspector, text transforms, unsaved-edit confirmation | Full QLPreviewPanel, richer image tools |
| Sequential paste | Temporary FIFO queue, event tap removed when inactive | End-to-end physical ⌘V validation after Accessibility authorization |
| Sounds | Capture/paste events, soft/crystal/retro pairs, volume, custom files, preview buttons | Auditory usability feedback and more original sound sets |
| Displays | Pointer/current, macOS primary, fixed monitor UUID, disconnected fallback | Interactive mixed-DPI/full-screen/multi-monitor validation |
| Screenshots | Opt-in new saved screenshot import, selected folder, pause/exclusions, original date, no clipboard replacement | End-to-end Spotlight watcher checks on supported macOS versions |
| Settings | Native keyboard-navigable sidebar, consistent SF controls, app names/icons, readable shortcut rows | English localization and accessibility review |
| Recovery | Serialized writes, visible error/pause, reload action, previous-index backup and damaged-index preservation | Transactional payload/index recovery; complete versioned automatic backups |
| Privacy | Local-only app, excluded apps, confidential/transient markers, owner-only files | Optional encryption with Keychain/recovery design; secret-expiry policy |
| Distribution | Tagged CI packaging, ZIP and checksum, download-first README | Developer ID/notarization, auto-updates, Intel builds, Homebrew |

## Retention contract

First matching enabled rule wins. Minimum size is inclusive, maximum size exclusive. Recopying updates the last-copy time and renews expiry without losing the first-copy time. Pins are indefinite. Rule-matched items bypass the generic item-count limit; the raw embedded-content budget still applies.

File references use their known logical size. Images/text use stored payload bytes. A file that is a directory, missing, inaccessible, or has an unknown size uses the fallback policy. References are not backups of original files.

A full raw-content budget refuses new items with a visible notice. Existing items are not silently deleted to make room: automatic oldest-first budget eviction is a possible future policy, not a bug fix to apply without defining protection precedence.

## Known engineering debt

- The JSON index still contains searchable text/OCR, is decoded synchronously at launch, and is rewritten as snapshots. Preview caches reduce repeated UI disk reads; they do not solve scaling of the index.
- Previous-index recovery can lose changes since the saved index and cannot restore deleted/replaced payloads or original referenced files. Portable exports are separate.
- Ad-hoc signatures cannot provide a stable Developer ID identity across builds. Accessibility may need to be granted again.
- Thumbnail generation uses Quick Look; this is not the full system Quick Look panel.

## Later projects

Snippets with variables, optional link fetching (off by default), opt-in encryption, URL scheme/integrations, mobile apps, synchronization, shared boards, AI, and MCP require separate design and validation.

## Reference

Encore is independently implemented. Public reference material reviewed during development includes [Paste on Mac](https://pasteapp.io/help/paste-on-mac), [keyboard shortcuts](https://pasteapp.io/help/keyboard-shortcuts), [search](https://pasteapp.io/help/search-and-filters), [pinboards](https://pasteapp.io/help/organize-with-pinboards), [sequential paste](https://pasteapp.io/help/using-paste-stack), and [capture/privacy](https://pasteapp.io/help/what-paste-captures). No reference product code or assets are included.
