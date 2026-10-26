Native clipboard history for macOS 12+, now on Apple Silicon and Intel.

- Intel Macs are supported: encore ships as a single universal app.
- encore now runs on macOS 12 Monterey and 13 Ventura. Launch at login and Share need macOS 13.
- Fixed a freeze when a rich-text email with tables was shown on a card.
- The Space preview is larger and scrolls through long content.
- Preview & edit shows rich text as laid out; Edit switches to plain text.
- Paired Macs no longer ask for your login password after each update, and the app no longer freezes waiting for it: pairing keys moved from the Keychain to a private file. Existing pairings move over automatically, after one last prompt.
- Arrow keys, the shelf and the library stay smooth on older Macs: a card now redraws only when it changes.
- Holding an arrow key in the library keeps the selected card in view, and the first row no longer slides under the day title on opening.
- Each opening of the shelf starts on the history.
- The app name is now written encore everywhere.

Download the ZIP, unzip, and move Encore.app to Applications. SHA256SUMS contains its checksum. Installed copies update themselves.

encore is not notarized yet. [Apple's first-launch instructions](https://support.apple.com/en-us/102445). History is unencrypted; files are references; embedded payloads are limited to 25 MiB.
