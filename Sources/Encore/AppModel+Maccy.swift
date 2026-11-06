import AppKit
import EncoreCore

extension AppModel {
    /// Brings Maccy's history into encore, under the rules a copy made here would follow: excluded apps, content marked
    /// confidential, secret detection, the size of a copy and of the storage. Maccy's pinned items become favorites.
    func importFromMaccy() {
        var url = MaccyStore.defaultURL
        if !FileManager.default.isReadableFile(atPath: url.path) {
            // Missing, or macOS asked and access to Maccy's data was refused: let the person point at it.
            let panel = NSOpenPanel()
            panel.message = L("Choose Maccy's history, Storage.sqlite, in its Maccy folder.")
            panel.directoryURL = url.deletingLastPathComponent()
            panel.allowsOtherFileTypes = true
            NSApp.activate(ignoringOtherApps: true)
            guard panel.runModal() == .OK, let chosen = panel.url else { return }
            url = chosen
        }
        let items: [MaccyStore.Item]
        do { items = try MaccyStore.read(url) } catch {
            notify(L("Maccy's history could not be read.")); return
        }
        let result = mergeMaccy(items)
        guard result.added + result.merged > 0 else { notify(L("Nothing new to import from Maccy.")); return }
        notify(result.expired > 0 ? L("\(Localization.number(result.added + result.merged)) copies imported from Maccy, \(Localization.number(result.expired)) already expired under your retention rules")
                                  : L("\(Localization.number(result.added + result.merged)) copies imported from Maccy"))
    }

    /// Adds the copies in one save. A copy encore already has keeps its most recent date and gains Maccy's older first one.
    @discardableResult func mergeMaccy(_ items: [MaccyStore.Item]) -> (added: Int, merged: Int, expired: Int) {
        guard storage != nil, storageError == nil else { return (0, 0, 0) }
        let pasteboard = NSPasteboard(name: .init("local.kama.Encore.import.\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        var snapshot = library, payloads: [(UUID, ClipPayload)] = [], merged = 0, full = false, bytes = totalBytes
        for item in items {
            let bundle = item.application ?? ""
            if !bundle.isEmpty && preferences.excludedBundleIDs.contains(bundle) { continue }
            if bundle == Bundle.main.bundleIdentifier { continue }
            pasteboard.clearContents()
            pasteboard.writeObjects(item.items.map { item in
                let value = NSPasteboardItem()
                for (type, data) in item.representations { value.setData(data, forType: .init(type)) }
                return value
            })
            let name = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle).map { FileManager.default.displayName(atPath: $0.path).replacingOccurrences(of: ".app", with: "") } ?? (bundle.isEmpty ? "Maccy" : bundle)
            guard let capture = (try? PasteboardCapture.read(pasteboard, sourceName: name, sourceBundle: bundle, ignoreSensitive: preferences.ignoreSensitive)) ?? nil else { continue }
            var clip = capture.clip
            clip.copiedAt = item.lastCopiedAt; clip.firstCopiedAt = item.firstCopiedAt; clip.favorite = item.pinned
            if item.pinned { clip.favoriteChangedAt = Date() }
            if preferences.detectSecrets, [.text, .code].contains(clip.kind), let secret = SecretKind.detect(clip.text) {
                clip.secret = secret
                clip.text = SecretKind.mask(clip.text, keeping: preferences.secretPreview)
                clip.kind = .text
            }
            if let index = snapshot.clips.firstIndex(where: { $0.fingerprint == clip.fingerprint }) {
                var existing = snapshot.clips[index]
                existing.firstCopiedAt = min(existing.firstCopyDate, item.firstCopiedAt)
                existing.copiedAt = max(existing.copiedAt, item.lastCopiedAt)
                if item.pinned && !existing.favorite { existing.favorite = true; existing.favoriteChangedAt = Date() }
                snapshot.clips[index] = existing; merged += 1
                continue
            }
            guard bytes + capture.payload.byteCount <= preferences.storageLimitMB * 1_048_576 else { full = true; continue }
            bytes += capture.payload.byteCount
            snapshot.clips.append(clip); payloads.append((clip.id, capture.payload))
        }
        if full { notify(L("Storage full: increase the limit or delete some items.")) }
        guard !payloads.isEmpty || merged > 0 else { return (0, 0, 0) }
        snapshot.clips.sort { $0.copiedAt > $1.copiedAt }
        library = snapshot
        storage?.save(library, payloads: payloads)
        let imported = Set(payloads.map(\.0))
        prune()
        let expired = imported.subtracting(library.clips.map(\.id)).count
        resetSelection()
        for (id, _) in payloads where preferences.recognizeImages && library.clips.first(where: { $0.id == id })?.kind == .image { recognize(id) }
        return (payloads.count, merged, expired)
    }
}
