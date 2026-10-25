# Interaction lessons

- Clipboard provenance must be checked before falling back to the active app. Drain pending copies before updating the tracked application on activation; a polling delay can otherwise label a Firefox copy as coming from a terminal. macOS does not expose a universal authoritative origin when no source marker is present.
- Resize a moving window from absolute screen coordinates. Avoid publishing preferences on every pointer movement; commit the height when dragging ends.
- A copied image file needs an image thumbnail, and a PDF needs a document thumbnail. A generic file icon is only a fallback.
- Keep application UI typography consistent. Content previews may preserve their original document typography; that is separate from the app's controls and labels.
- Handle navigation keys before type-to-search. Special-key Unicode values are not ordinary text: up must not insert a hidden search character, and down can explicitly dismiss the card shelf.
- Clipboard shortcuts for the number row must work on AZERTY without requiring Shift. Resolve physical number keys and reject extra Option/Control modifiers.
- A detail view must fit independently of the shelf height. Use a resizable window and confirm before discarding text edits.
