import AppKit
import SwiftUI
import Vision
import ImageIO
import EncoreCore

@MainActor final class AppModel: ObservableObject {
    @Published var library = Library()
    @Published var preferences: Preferences
    @Published var query = "" { didSet { resetSelection() } }
    @Published var kind: ClipKind? { didSet { resetSelection() } }
    @Published var source: String? { didSet { resetSelection() } }
    @Published var board = "history" { didSet { resetSelection() } }
    @Published var selection: Set<UUID> = []
    @Published var cursor: UUID?
    @Published var searchFocused = false
    @Published var inspector: Clip?
    @Published var queue: [UUID] = []
    @Published var collecting = false
    @Published var queueVisible = false
    @Published var status = ""
    @Published var shortcutStatus = "⌘⇧V"
    @Published var accessibilityGranted = AXIsProcessTrusted()
    @Published var storageError: String?
    var togglePanel: (() -> Void)?
    var dismissPanel: (() -> Void)?
    var showSettings: (() -> Void)?
    var activateTarget: (() -> NSRunningApplication?)?
    var updateShortcuts: (() -> Void)?
    var updateAppearance: (() -> Void)?
    var resizePanel: (() -> Void)?
    var clipboard: ClipboardService!
    var stackTap: StackTap!
    let demo: Bool
    var storage: Storage?
    private var deleted: [(Clip, ClipPayload)] = []
    private var selectionAnchor: UUID?
    private var statusTask: Task<Void, Never>?
    private var thumbnails: [UUID: NSImage] = [:]
    private var ocrJobs = Set<UUID>()
    private let ocrQueue = DispatchQueue(label: "local.kama.Encore.ocr", qos: .utility)

    init(demo: Bool, pasteboard: NSPasteboard = .general) {
        self.demo = demo
        self.preferences = Preferences.load(demo: demo)
        do {
            let root = demo ? FileManager.default.temporaryDirectory.appendingPathComponent("Encore-Demo-\(ProcessInfo.processInfo.processIdentifier)") : FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Encore")
            let store = try Storage(root: root)
            library = try store.load()
            storage = store
            store.onError = { [weak self] message in
                self?.storageError = message
                self?.preferences.captureEnabled = false
                self?.notify("Échec de sauvegarde : \(message)")
            }
        } catch {
            storageError = error.localizedDescription
            preferences.captureEnabled = false
        }
        clipboard = ClipboardService(model: self, pasteboard: pasteboard)
        stackTap = StackTap(model: self)
        if demo { seedDemo() } else { prune() }
        resetSelection()
    }

    var filtered: [Clip] {
        let search = ClipQuery(query: query, kind: kind, source: source, favorites: board == "favorites", collectionID: UUID(uuidString: board))
        return library.clips.filter { search.matches($0) }
    }
    var selectedClips: [Clip] { filtered.filter { selection.contains($0.id) } }
    var selected: Clip? { library.clips.first { $0.id == cursor } }
    var sources: [(String, String)] {
        var seen = Set<String>()
        return library.clips.compactMap { seen.insert($0.sourceBundle).inserted && !$0.sourceBundle.isEmpty ? ($0.sourceBundle, $0.sourceName) : nil }.sorted { $0.1.localizedStandardCompare($1.1) == .orderedAscending }
    }
    var totalBytes: Int { library.clips.reduce(0) { $0 + $1.byteCount } }

    func resetSelection() {
        let first = filtered.first?.id
        cursor = first
        selection = Set(first.map { [$0] } ?? [])
        selectionAnchor = first
    }

    func reconcileSelection() {
        let valid = Set(filtered.map(\.id))
        selection.formIntersection(valid)
        if let cursor, valid.contains(cursor), !selection.isEmpty { return }
        resetSelection()
    }

    func select(_ id: UUID, modifiers: NSEvent.ModifierFlags = []) {
        let ids = filtered.map(\.id)
        if modifiers.contains(.shift), let anchor = selectionAnchor ?? cursor, let start = ids.firstIndex(of: anchor), let end = ids.firstIndex(of: id) {
            selection = Set(ids[min(start, end)...max(start, end)])
        } else if modifiers.contains(.command) {
            if selection.contains(id) { selection.remove(id) } else { selection.insert(id) }
            selectionAnchor = id
        } else { selection = [id]; selectionAnchor = id }
        cursor = id
        searchFocused = false
    }

    func move(_ delta: Int, extend: Bool = false) {
        let items = filtered
        guard !items.isEmpty else { return }
        let position = items.firstIndex { $0.id == cursor } ?? 0
        let next = max(0, min(items.count - 1, position + delta))
        let id = items[next].id
        select(id, modifiers: extend ? .shift : [])
    }

    @discardableResult func accept(_ clip: Clip, payload: ClipPayload) -> Bool {
        guard storage != nil, storageError == nil else { return false }
        let existed = library.clips.contains { $0.fingerprint == clip.fingerprint }
        if !existed && totalBytes + payload.byteCount > preferences.storageLimitMB * 1_048_576 {
            notify("Stockage plein : augmentez la limite ou supprimez des éléments.")
            return false
        }
        let id = library.upsert(clip)
        if !existed { storage?.save(library, payload: (id, payload)) } else { save() }
        if collecting && !queue.contains(id) { queue.append(id) }
        if selection.isEmpty { resetSelection() }
        prune()
        if preferences.recognizeImages, clip.kind == .image { recognize(id) }
        return true
    }

    func save() { storage?.save(library) }

    func prune() {
        let removed = library.prune(days: preferences.retentionDays, limit: preferences.historyLimit)
        if !removed.isEmpty {
            queue.removeAll { removed.contains($0) }
            for id in removed { thumbnails.removeValue(forKey: id) }
            storage?.save(library, deleting: removed)
            reconcileSelection()
        }
    }

    func preferencesChanged() {
        preferences.save(demo: demo)
        prune()
        updateAppearance?()
    }

    func notify(_ message: String) {
        statusTask?.cancel()
        status = message
        statusTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            self?.status = ""
        }
    }

    func toggleFavorite(_ ids: Set<UUID>? = nil) {
        let chosen = ids ?? selection
        let shouldPin = !library.clips.filter { chosen.contains($0.id) }.allSatisfy(\.favorite)
        for index in library.clips.indices where chosen.contains(library.clips[index].id) { library.clips[index].favorite = shouldPin }
        save()
        reconcileSelection()
    }

    func assignCollection(_ collection: UUID, ids: Set<UUID>? = nil, toggle: Bool = true) {
        let chosen = ids ?? selection
        let allMembers = library.clips.filter { chosen.contains($0.id) }.allSatisfy { $0.collectionIDs.contains(collection) }
        for index in library.clips.indices where chosen.contains(library.clips[index].id) {
            if toggle && allMembers { library.clips[index].collectionIDs.remove(collection) }
            else { library.clips[index].collectionIDs.insert(collection) }
        }
        save()
        reconcileSelection()
    }

    func remove(_ ids: Set<UUID>? = nil) {
        let chosen = ids ?? selection
        deleted = library.clips.filter { chosen.contains($0.id) }.compactMap { clip in storage?.payload(clip.id).map { (clip, $0) } }
        let position = filtered.firstIndex { $0.id == cursor } ?? 0
        library.clips.removeAll { chosen.contains($0.id) }
        queue.removeAll { chosen.contains($0) }
        selection.subtract(chosen)
        for id in chosen { thumbnails.removeValue(forKey: id) }
        let remaining = filtered
        cursor = remaining.isEmpty ? nil : remaining[min(position, remaining.count - 1)].id
        selection = Set(cursor.map { [$0] } ?? [])
        storage?.save(library, deleting: Array(chosen))
        notify("\(chosen.count) élément(s) supprimé(s) · ⌘Z pour annuler")
    }

    func undoDelete() {
        guard !deleted.isEmpty else { return }
        for (clip, payload) in deleted.reversed() where !library.clips.contains(where: { $0.id == clip.id }) {
            library.clips.append(clip)
            storage?.save(library, payload: (clip.id, payload))
        }
        library.clips.sort { $0.copiedAt > $1.copiedAt }
        deleted = []
        save()
        resetSelection()
        notify("Suppression annulée")
    }

    func paste(_ clips: [Clip]? = nil, plain: Bool = false, copyOnly: Bool = false) {
        let values = clips ?? selectedClips
        guard !values.isEmpty else { return }
        let payloads = values.compactMap { storage?.payload($0.id) }
        guard payloads.count == values.count else { notify("Le contenu est indisponible sur le disque."); return }
        if plain {
            let text = values.map { $0.text.isEmpty ? $0.recognizedText : $0.text }.joined(separator: "\n")
            guard !text.isEmpty else { notify("Cet élément ne contient pas de texte."); return }
            clipboard.write(.text(text))
        } else if values.count > 1 && values.allSatisfy({ [.text, .code, .link, .color].contains($0.kind) }) {
            clipboard.write(.text(values.map(\.text).joined(separator: "\n")))
        } else {
            clipboard.write(ClipPayload(items: payloads.flatMap(\.items)))
        }
        for index in library.clips.indices where values.contains(where: { $0.id == library.clips[index].id }) { library.clips[index].lastUsedAt = Date() }
        save()
        guard !copyOnly else { notify("Copié dans le presse-papiers"); return }
        accessibilityGranted = AXIsProcessTrusted()
        let target = activateTarget?()
        dismissPanel?()
        if accessibilityGranted, let target, !target.isTerminated {
            target.activate(options: [])
            deliverPaste(to: target, attempts: 12)
        } else {
            notify("Copié · utilisez ⌘V, ou activez le collage direct dans les réglages.")
        }
    }

    private func deliverPaste(to target: NSRunningApplication, attempts: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) { [weak self] in
            guard let self else { return }
            guard target.isActive else {
                if attempts > 0 { self.deliverPaste(to: target, attempts: attempts - 1) }
                else { self.notify("Copié · cliquez dans l’application et faites ⌘V.") }
                return
            }
            let source = CGEventSource(stateID: .combinedSessionState)
            let down = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true)
            let up = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false)
            down?.flags = .maskCommand; up?.flags = .maskCommand
            down?.setIntegerValueField(.eventSourceUserData, value: StackTap.syntheticTag)
            up?.setIntegerValueField(.eventSourceUserData, value: StackTap.syntheticTag)
            down?.post(tap: .cghidEventTap); up?.post(tap: .cghidEventTap)
        }
    }

    func enqueue(_ ids: [UUID]? = nil) {
        for id in ids ?? selectedClips.map(\.id) where !queue.contains(id) { queue.append(id) }
        queueVisible = true
        notify("Ajouté à la file · ⌘⇧C pour activer le collage en série")
    }

    func toggleCollecting() {
        if collecting { collecting = false; notify("Collage en série désactivé"); return }
        guard stackTap.enable() else { requestAccessibility(); notify("Autorisez Encore dans Accessibilité, puis réessayez."); return }
        collecting = true
        queueVisible = true
        notify("File active · copiez, puis collez dans l’ordre avec ⌘V")
    }

    func advanceQueue() -> Bool {
        guard collecting, let id = queue.first else { return false }
        guard let payload = storage?.payload(id) else {
            collecting = false
            notify("File arrêtée : le contenu de l’élément est indisponible.")
            return false
        }
        clipboard.write(payload)
        queue.removeFirst()
        if queue.isEmpty { collecting = false; notify("File terminée") }
        return true
    }

    func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        accessibilityGranted = AXIsProcessTrustedWithOptions(options)
        if !accessibilityGranted { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!) }
    }

    @discardableResult func addText(_ text: String, title: String = "") -> Bool {
        guard !text.isEmpty else { return false }
        let payload = ClipPayload.text(text)
        guard payload.byteCount <= PasteboardCapture.maxBytes else { notify("Limite de 25 Mo par élément."); return false }
        let accepted = accept(Clip(fingerprint: payload.fingerprint, kind: .detect(text: text), text: text, title: title, byteCount: payload.byteCount), payload: payload)
        resetSelection()
        return accepted
    }

    @discardableResult func updateText(_ id: UUID, text: String, title: String) -> Bool {
        guard storageError == nil, let index = library.clips.firstIndex(where: { $0.id == id }) else { return false }
        let payload = ClipPayload.text(text)
        let duplicates = library.clips.filter { $0.id != id && $0.fingerprint == payload.fingerprint }
        guard payload.byteCount <= PasteboardCapture.maxBytes, totalBytes - library.clips[index].byteCount - duplicates.reduce(0, { $0 + $1.byteCount }) + payload.byteCount <= preferences.storageLimitMB * 1_048_576 else { notify("Limite de stockage atteinte."); return false }
        library.clips[index].text = text
        library.clips[index].title = title
        library.clips[index].kind = .detect(text: text)
        library.clips[index].fingerprint = payload.fingerprint
        library.clips[index].byteCount = payload.byteCount
        for duplicate in duplicates {
            library.clips[index].favorite = library.clips[index].favorite || duplicate.favorite
            library.clips[index].collectionIDs.formUnion(duplicate.collectionIDs)
        }
        let removed = Set(duplicates.map(\.id))
        library.clips.removeAll { removed.contains($0.id) }
        if cursor.map(removed.contains) == true { cursor = id }
        if !selection.isDisjoint(with: removed) { selection.subtract(removed); selection.insert(id) }
        var seen = Set<UUID>()
        queue = queue.map { removed.contains($0) ? id : $0 }.filter { seen.insert($0).inserted }
        storage?.save(library, payload: (id, payload), deleting: Array(removed))
        reconcileSelection()
        return true
    }

    func transform(_ action: TextAction, clip: Clip) {
        do { if addText(try action.apply(clip.text), title: clip.title) { notify(action.title) } }
        catch { notify(error.localizedDescription) }
    }

    func image(for clip: Clip) -> NSImage? {
        if let image = thumbnails[clip.id] { return image }
        guard let payload = storage?.payload(clip.id), let data = Self.imageData(payload), let cg = Self.downsample(data, maxDimension: 640) else { return nil }
        let image = NSImage(cgImage: cg, size: .zero)
        if thumbnails.count >= 40 { thumbnails.removeAll() }
        thumbnails[clip.id] = image
        return image
    }

    nonisolated private static func imageData(_ payload: ClipPayload) -> Data? {
        for item in payload.items {
            for type in [NSPasteboard.PasteboardType.png.rawValue, NSPasteboard.PasteboardType.tiff.rawValue, "public.jpeg", "public.heic"] {
                if let data = item.representations[type] { return data }
            }
        }
        return nil
    }

    nonisolated private static func downsample(_ data: Data, maxDimension: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary) else { return nil }
        return CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: maxDimension, kCGImageSourceShouldCacheImmediately: true] as CFDictionary)
    }

    func recognize(_ id: UUID) {
        guard !ocrJobs.contains(id), let clip = library.clips.first(where: { $0.id == id }), clip.recognizedText.isEmpty, let storage else { return }
        ocrJobs.insert(id)
        ocrQueue.async { [weak self] in
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.automaticallyDetectsLanguage = true
            do {
                guard let payload = storage.payload(id), let data = Self.imageData(payload), let cg = Self.downsample(data, maxDimension: 4096) else { throw CocoaError(.fileReadCorruptFile) }
                try VNImageRequestHandler(cgImage: cg).perform([request])
                let text = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.ocrJobs.remove(id)
                    guard let index = self.library.clips.firstIndex(where: { $0.id == id }) else { return }
                    self.library.clips[index].recognizedText = text
                    self.save()
                    if !text.isEmpty { self.notify("Texte de l’image reconnu · recherche disponible") }
                }
            } catch { DispatchQueue.main.async { self?.ocrJobs.remove(id); self?.notify("Reconnaissance impossible : \(error.localizedDescription)") } }
        }
    }

    func createCollection() {
        let alert = NSAlert()
        alert.messageText = "Nouvelle collection"
        alert.informativeText = "Gardez vos éléments ensemble. Ils seront conservés sans expiration."
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 26))
        field.placeholderString = "Nom de la collection"
        alert.accessoryView = field
        alert.addButton(withTitle: "Créer"); alert.addButton(withTitle: "Annuler")
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        let collection = ClipCollection(name: name, colorIndex: library.collections.count % 5)
        library.collections.append(collection)
        board = collection.id.uuidString
        save()
    }

    func deleteCollection(_ collection: ClipCollection) {
        library.collections.removeAll { $0.id == collection.id }
        for index in library.clips.indices { library.clips[index].collectionIDs.remove(collection.id) }
        if board == collection.id.uuidString { board = "history" }
        save()
        notify("Collection supprimée · ses éléments restent dans l’historique")
    }

    func exportLibrary() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "Encore-backup.json"
        panel.message = "Cette sauvegarde contient votre historique et ses contenus en clair. Conservez-la dans un endroit sûr."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            storage?.flush()
            let entries = library.clips.compactMap { clip in storage?.payload(clip.id).map { Backup.Entry(clip: clip, payload: $0) } }
            guard entries.count == library.clips.count else { throw CocoaError(.fileReadCorruptFile) }
            try JSONEncoder().encode(Backup(version: 1, collections: library.collections, entries: entries)).write(to: url, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            notify("Sauvegarde exportée")
        } catch { notify(error.localizedDescription) }
    }

    func importLibrary() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size < 1_000_000_000 else { throw CocoaError(.fileReadTooLarge) }
            let backup = try JSONDecoder().decode(Backup.self, from: Data(contentsOf: url))
            let result = try backup.merged(into: library, budgetBytes: preferences.storageLimitMB * 1_048_576)
            library = result.library
            storage?.save(library, payloads: result.payloads)
            prune(); resetSelection()
            notify("\(result.payloads.count) nouvel élément(s) importé(s)")
        } catch { notify("Import impossible : \(error.localizedDescription)") }
    }

    func clearHistory() {
        let alert = NSAlert()
        alert.messageText = "Effacer l’historique ?"
        alert.informativeText = "Les favoris et les éléments des collections seront conservés. Cette action est définitive."
        alert.addButton(withTitle: "Annuler"); alert.addButton(withTitle: "Effacer")
        guard alert.runModal() == .alertSecondButtonReturn else { return }
        let ids = library.clips.filter { !$0.isProtected }.map(\.id)
        library.clips.removeAll { !$0.isProtected }
        queue.removeAll { ids.contains($0) }
        deleted = []; thumbnails.removeAll()
        storage?.save(library, deleting: ids)
        resetSelection()
    }

    private func seedDemo() {
        let samples: [(String, String, String)] = [
            ("Design is how it works.\n\nLes bonnes idées méritent\nd’être retrouvées.", "Notes", "com.apple.Notes"),
            ("https://developer.apple.com/design/human-interface-guidelines", "Safari", "com.apple.Safari"),
            ("#A78BFA", "Figma", "com.figma.Desktop"),
            ("struct GoodIdea {\n    let captured = true\n    let forgotten = false\n\n    func encore() {\n        paste(with: .joy)\n    }\n}", "Xcode", "com.apple.dt.Xcode"),
            ("Bonjour,\n\nMerci pour votre retour !\nJe regarde ça et reviens vers vous dans la journée.\n\nBonne journée,", "Mail", "com.apple.mail"),
            ("https://github.com", "Safari", "com.apple.Safari")
        ]
        for (index, value) in samples.reversed().enumerated() {
            let payload = ClipPayload.text(value.0)
            let clip = Clip(fingerprint: payload.fingerprint, kind: .detect(text: value.0), text: value.0, sourceName: value.1, sourceBundle: value.2, copiedAt: Date().addingTimeInterval(-Double(samples.count - index) * 180), favorite: index == 1, byteCount: payload.byteCount)
            accept(clip, payload: payload)
        }
        library.collections = [.init(name: "Travail", colorIndex: 0), .init(name: "Inspiration", colorIndex: 1), .init(name: "Snippets", colorIndex: 2)]
        save()
    }
}
