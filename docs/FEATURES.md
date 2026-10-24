# Feature reference

The reference product was reviewed on 25 October 2026 through its public documentation and current official screenshots. The installed legacy version was not upgraded or modified.

Primary references:

- [Paste on Mac](https://pasteapp.io/help/paste-on-mac)
- [Keyboard shortcuts](https://pasteapp.io/help/keyboard-shortcuts)
- [Search and filters](https://pasteapp.io/help/search-and-filters)
- [Pinboards](https://pasteapp.io/help/organize-with-pinboards)
- [Sequential paste](https://pasteapp.io/help/using-paste-stack)
- [Capture and privacy](https://pasteapp.io/help/what-paste-captures)
- [Intelligent Clipboard](https://pasteapp.io/help/intelligent-clipboard)

## Encore's implementation

| Workflow | Encore |
| --- | --- |
| Recall copied content visually | Resizable horizontal card shelf |
| Keep the familiar shortcut | ⇧⌘V, with conflict detection and an emergency shortcut |
| Reuse rich content | Original data representations and multi-item pasteboards |
| Find old copies | Text, source, type, date, and local OCR search |
| Keep reusable content | Favorites and multiple collections per item |
| Paste a sequence | Explicit queue using a macOS event tap |
| Adjust copied text | Editor and non-destructive transformation copies |
| Keep data private | No network access in app code, local storage, exclusions |
| Recover deleted items | One-level undo until the app exits or another deletion replaces it |
| Move your library | JSON export/import of metadata and retained representations |

## Deliberate differences

- Links have a locally generated preview. Opening history does not contact their hosts.
- Deleting a collection keeps its items in history.
- An item can be in multiple collections.
- Suggestions do not require reading the screen; contextual AI is not implemented.
- The queue is temporary and does not survive app restart.
- Sequential paste assumes the destination app handles the standard macOS ⌘V shortcut.
- Storage is not encrypted and this is disclosed in the settings.

## Future work

- Native English localization and additional translations.
- Developer ID signing, notarization, and reproducible release packaging.
- Optional encryption with a clear recovery story.
- Larger-library indexing and a transactional database if measurements warrant it.
- Quick Look for files and more image editing tools.
- Opt-in sync after conflict, privacy, and recovery design.

New functionality should preserve the primary contract: opening, choosing, and pasting must remain fast and work entirely from the keyboard.
