More privacy, and your cards in your order.

- **Hidden from screen sharing.** encore's windows are left out of screen sharing, recordings and screenshots: open your history during a call, and nobody else sees it. Settings → Privacy turns this off when you want a screenshot of encore.
- **Encrypted history, if you want.** Settings → Data encrypts your history on your Mac with ChaCha20-Poly1305, under a 256-bit key kept in your login keychain: a copy of the folder, or another app reading it, shows nothing readable. It is off by default for now: encore is not signed by Apple yet, so macOS would ask for your Mac password after each update, and encore is updated often. That gets tiring, and can look suspicious. Once encore is signed, it will be on by default, with no prompt.
- **Memory only.** Settings → Data can keep your history in memory only: favorites, snippets and collections are saved, everything else is never written to disk and is gone when encore quits, restarts or updates.
- **Forget a secret once pasted.** With secret detection on, a password leaves the history as soon as you paste it, and the clipboard is emptied 30 seconds later if it still holds it.
- **Stop saving an app from its card.** Right-click a copy, then Stop saving copies from…, and choose whether to delete the ones already kept. Retention rules can also target one app now: Terminal for a day, Slack for a week.
- **Pause for a while.** Right-click the menu bar icon, then Pause capture: for 5 minutes, for 1 hour, or until you resume it. Capture comes back on its own at the time shown, even after a relaunch. The icon dims while paused, and the shelf says until when.
- **Left out today.** Settings → Privacy counts what encore left out today, from excluded apps, password fields, confidential copies and detected secrets, without any of the content.
- **Pasted in the order you pick.** Select several cards with ⌘-click, or ⇧ and the arrows: each one shows its number, and they paste in that order. Drag any of them into another app to drop them all, in order, one per line, images included: Pages, TextEdit, Mail and Notes keep the images in place. The compact window selects several copies too, with ⇧↑ and ⇧↓.
- **Snippets in your order.** On the Snippets board, drag a snippet onto another to take its place in their group. New snippets arrive at the top. The order follows your snippet exports, and your paired Macs that sync snippets.
- **Fast with 10,000 copies.** A click selects at once, without waiting for a possible double-click. Search, day sections and favorites stay quick with a history of 10,000 copies, and the history file is written at most once a second, with the latest state.
- **The compact window catches up.** Its copies now open the same right-click menu as the cards, can be dragged into another app, and are read by VoiceOver. Every icon-only button has a name for VoiceOver too, and selected cards say where they will be pasted.
- **Secrets paste their real value** when several cards are pasted together or as plain text, instead of their masked text.
- **Going back to 0.6?** If you turned encryption on, turn it off in Settings → Data first: 0.6 cannot read an encrypted history, and would open on an empty one.

Download the ZIP, unzip, and move Encore.app to Applications. SHA256SUMS contains its checksum. Installed copies update themselves.

encore is not notarized yet. [Apple's first-launch instructions](https://support.apple.com/en-us/102445). History encryption is optional and off by default; exports are not encrypted; files are references; embedded payloads are limited to 25 MiB.
