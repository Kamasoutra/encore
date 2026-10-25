import AppKit
import SwiftUI
import Vision
import ImageIO
import SystemConfiguration
import EncoreCore

struct PeerStatus: Identifiable, Equatable {
    var device: PeerDevice
    var online: Bool
    var id: String { device.id }
}

@MainActor final class AppModel: ObservableObject {
    @Published var library = Library()
    @Published var preferences: Preferences
    @Published var query = "" { didSet { resetSelection() } }
    @Published var kind: ClipKind? { didSet { resetSelection() } }
    @Published var source: String? { didSet { resetSelection() } }
    @Published var board = "history" { didSet { loadRemote(); resetSelection() } }
    @Published var selection: Set<UUID> = []
    @Published var cursor: UUID?
    @Published var searchFocused = false
    @Published var expanded = false { didSet { if expanded != oldValue { quickLook = false; resizePanel?() } } }
    @Published var quickLook = false { didSet { if quickLook != oldValue { updateQuickLook?() } } }
    /// Frame of the cursor card in panel coordinates, used to anchor the floating preview.
    var cursorFrame: CGRect = .zero
    var libraryColumns = 1
    @Published var inspector: Clip? { didSet { if let inspector { presentInspector?(inspector) } } }
    @Published var queue: [UUID] = []
    @Published var collecting = false { didSet { if !collecting && oldValue { stackTap?.stop() } } }
    @Published var displayTime = Date()
    @Published var queueVisible = false
    @Published var status = ""
    @Published var shortcutStatus = "⌘⇧V"
    @Published var accessibilityGranted = AXIsProcessTrusted()
    @Published var storageError: String?
    @Published private(set) var installedExcludedBundleIDs: [String] = []
    @Published private(set) var peers: [PeerStatus] = []
    @Published private(set) var nearbyMacs: [PeerDevice] = []
    @Published private(set) var pairing: PairingSession?
    @Published private(set) var pairingState: PairingSession.State?
    @Published var pairingSheet = false { didSet { if pairingSheet != oldValue { refreshPeerActivity() } } }
    var togglePanel: (() -> Void)?
    var dismissPanel: (() -> Void)?
    var showSettings: (() -> Void)?
    var activateTarget: (() -> NSRunningApplication?)?
    var updateShortcuts: (() -> Void)?
    var updateAppearance: (() -> Void)?
    var resizePanel: (() -> Void)?
    var updateScreenshotCapture: (() -> Void)?
    var presentInspector: ((Clip) -> Void)?
    var updateQuickLook: (() -> Void)?
    var updateLanguage: (() -> Void)?
    var clipboard: ClipboardService!
    var stackTap: StackTap!
    let demo: Bool
    var storage: Storage?
    let filePreviews = FilePreviews()
    private(set) var peerService: PeerService?
    let deviceName = SCDynamicStoreCopyComputerName(nil, nil) as String? ?? Host.current().localizedName ?? "Mac"
    private var richTextCache: [UUID: NSAttributedString] = [:]
    private var checkedRichText = Set<UUID>()
    private var fileURLCache: [UUID: [URL]] = [:]
    private var deleted: [(Clip, ClipPayload)] = []
    private var selectionAnchor: UUID?
    private var statusTask: Task<Void, Never>?
    private var thumbnails: [UUID: NSImage] = [:]
    @Published private(set) var remoteItems: [Clip] = []
    @Published private(set) var remoteLoading = false
    private var remoteRecords: [UUID: RemoteClip] = [:]
    private var remoteTask: Task<Void, Never>?
    private var ocrJobs = Set<UUID>()
    private let ocrQueue = DispatchQueue(label: "local.kama.Encore.ocr", qos: .utility)

    init(demo: Bool, pasteboard: NSPasteboard = .general) {
        self.demo = demo
        self.preferences = Preferences.load(demo: demo)
        Localization.language = preferences.language
        preferences.language = Localization.language
        if demo { preferences.displayTarget = "primary" }
        do {
            let root = demo ? FileManager.default.temporaryDirectory.appendingPathComponent("Encore-Demo-\(ProcessInfo.processInfo.processIdentifier)") : FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Encore")
            let store = try Storage(root: root)
            storage = store
            library = try store.load()
            store.onError = { [weak self] message in
                self?.storageError = message
                self?.preferences.captureEnabled = false
                self?.notify(L("Save failed: \(message)"))
            }
        } catch {
            storageError = error.localizedDescription
            preferences.captureEnabled = false
        }
        clipboard = ClipboardService(model: self, pasteboard: pasteboard)
        stackTap = StackTap(model: self)
        refreshInstalledExclusions()
        if demo { seedDemo() } else { refreshFileSizes(); prune() }
        resetSelection()
        if let notice = storage?.recoveryNotice { notify(notice) }
        startPeers()
    }

    var filtered: [Clip] {
        let search = ClipQuery(query: query, kind: kind, source: source, favorites: board == "favorites", collectionID: UUID(uuidString: board))
        return boardClips.filter { search.matches($0) }
    }
    /// Local history, or the recent history of the paired Mac picked as board ("peer:<device id>").
    var boardClips: [Clip] { remotePeer == nil ? library.clips : remoteItems }
    var remotePeer: PeerStatus? { board.hasPrefix("peer:") ? peers.first { "peer:\($0.id)" == board } : nil }
    var selectedClips: [Clip] { filtered.filter { selection.contains($0.id) } }
    var selected: Clip? { boardClips.first { $0.id == cursor } }
    var sources: [(String, String)] {
        var seen = Set<String>()
        return boardClips.compactMap { seen.insert($0.sourceBundle).inserted && !$0.sourceBundle.isEmpty ? ($0.sourceBundle, $0.sourceName) : nil }.sorted { $0.1.localizedStandardCompare($1.1) == .orderedAscending }
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

    /// Moves to the card above or below in the library grid, whose rows restart at each day section.
    func moveRow(_ delta: Int, extend: Bool = false) {
        let sections = ClipSection.group(filtered, now: displayTime).map { $0.items.map(\.clip.id) }
        guard let s = sections.firstIndex(where: { $0.contains(cursor ?? UUID()) }) ?? (sections.isEmpty ? nil : 0) else { return }
        let columns = max(1, libraryColumns)
        let i = sections[s].firstIndex(of: cursor ?? UUID()) ?? 0
        let column = i % columns
        var target: UUID?
        if delta > 0 {
            if i / columns < (sections[s].count - 1) / columns { target = sections[s][min(i + columns, sections[s].count - 1)] }
            else if s + 1 < sections.count { target = sections[s + 1][min(column, sections[s + 1].count - 1)] }
        } else {
            if i >= columns { target = sections[s][i - columns] }
            else if s > 0 { let above = sections[s - 1]; target = above[min((above.count - 1) / columns * columns + column, above.count - 1)] }
        }
        if let target { select(target, modifiers: extend ? .shift : []) }
    }

    @discardableResult func accept(_ clip: Clip, payload: ClipPayload) -> Bool {
        guard storage != nil, storageError == nil else { return false }
        prune()
        let existed = library.clips.contains { $0.fingerprint == clip.fingerprint }
        if !existed && totalBytes + payload.byteCount > preferences.storageLimitMB * 1_048_576 {
            notify(L("Storage full: increase the limit or delete some items."))
            return false
        }
        let id = library.upsert(clip)
        richTextCache.removeValue(forKey: id)
        checkedRichText.remove(id); fileURLCache.removeValue(forKey: id)
        if !existed { storage?.save(library, payload: (id, payload)) } else { save() }
        if collecting && !queue.contains(id) { queue.append(id) }
        if selection.isEmpty { resetSelection() }
        prune()
        if preferences.recognizeImages, clip.kind == .image { recognize(id) }
        playSound(.capture)
        return true
    }

    func save() { storage?.save(library) }

    func reloadStorage() {
        guard let root = storage?.root else { return }
        let alert = NSAlert()
        alert.messageText = L("Reload the library from disk?")
        alert.informativeText = L("Unsaved changes will be discarded. Capture will remain paused so you can check the result.")
        alert.addButton(withTitle: L("Cancel")); alert.addButton(withTitle: L("Reload"))
        guard alert.runModal() == .alertSecondButtonReturn else { return }
        do {
            storage?.flush()
            let next = try Storage(root: root)
            let restored = try next.load()
            next.onError = { [weak self] error in self?.storageError = error; self?.preferences.captureEnabled = false }
            storage = next; library = restored; storageError = nil
            collecting = false; queue = []; deleted = []
            thumbnails.removeAll(); richTextCache.removeAll(); checkedRichText.removeAll(); fileURLCache.removeAll()
            resetSelection()
            notify(next.recoveryNotice ?? L("Library reloaded. Capture is paused."))
        } catch { notify(L("Could not reload: \(error.localizedDescription)")) }
    }

    func prune(now: Date = Date()) {
        var snapshot = library
        let removed = snapshot.prune(policy: preferences.retentionPolicy, limit: preferences.historyLimit, now: now)
        if !removed.isEmpty {
            library = snapshot
            queue.removeAll { removed.contains($0) }
            for id in removed { thumbnails.removeValue(forKey: id) }
            clearPreviewCaches(Set(removed))
            filePreviews.remove(Set(removed))
            storage?.save(library, deleting: removed)
            reconcileSelection()
        }
    }

    func retentionDecision(for clip: Clip) -> RetentionDecision { preferences.retentionPolicy.decision(for: clip) }

    func relativeAge(_ date: Date) -> String { Localization.relative(date, to: displayTime) }

    func remainingRetention(for clip: Clip) -> String {
        guard let deadline = retentionDecision(for: clip).expiresAt else { return L("Forever") }
        let seconds = deadline.timeIntervalSince(displayTime)
        guard seconds > 0 else { return L("Expiring now") }
        if seconds < 60 { return L("Expires in under 1 min") }
        return L("Expires in \(Localization.duration(seconds))")
    }

    private func clearPreviewCaches(_ ids: Set<UUID>) {
        for id in ids { richTextCache.removeValue(forKey: id); checkedRichText.remove(id); fileURLCache.removeValue(forKey: id) }
    }

    func refreshFileSizes() {
        var changed = false
        for index in library.clips.indices where library.clips[index].kind == .file && library.clips[index].referencedFileBytes == nil {
            if let payload = storage?.payload(library.clips[index].id), let size = PasteboardCapture.referencedSize(of: payload.fileURLs) {
                library.clips[index].referencedFileBytes = size
                changed = true
            }
        }
        if changed { save() }
    }

    func retentionSummary(for clip: Clip) -> String {
        let decision = retentionDecision(for: clip)
        let date = Localization.date(clip.copiedAt)
        let expiration = decision.expiresAt.map { L("Expires: \(Localization.date($0))") } ?? L("Kept forever")
        let reason = decision.protected ? L("Favorite or collection") : decision.ruleName ?? L("Default retention")
        return L("Copied \(date)\n\(expiration)\n\(reason)")
    }

    func retentionRemovalCount(rules: [RetentionRule], fallbackDays: Int) -> Int {
        var snapshot = library
        let policy = RetentionPolicy(rules: rules, fallback: fallbackDays > 0 ? .init(fallbackDays, .days) : .forever)
        return snapshot.prune(policy: policy, limit: preferences.historyLimit).count
    }

    func applyRetention(rules: [RetentionRule], fallbackDays: Int) {
        guard rules.allSatisfy(\.isValid), fallbackDays >= 0 else { notify(L("A retention rule is invalid.")); return }
        preferences.retentionRules = rules
        preferences.retentionDays = fallbackDays
        preferencesChanged()
        notify(L("Retention rules saved"))
    }

    func zoomCards(_ amount: Double) {
        preferences.cardScale = min(1.5, max(0.75, preferences.cardScale + amount))
        preferencesChanged()
    }

    private func playSound(_ action: FeedbackSounds.Action) {
        guard !demo, preferences.soundsEnabled else { return }
        FeedbackSounds.play(action, preferences: preferences)
    }

    func preferencesChanged() {
        if Localization.language != preferences.language {
            Localization.language = preferences.language
            updateLanguage?()
            objectWillChange.send()
        }
        preferences.save(demo: demo)
        prune()
        updateAppearance?()
        updateScreenshotCapture?()
        refreshPeerActivity()
    }

    private func startPeers() {
        guard !demo, let storage else { return }
        let defaults = UserDefaults.standard
        let id = defaults.string(forKey: "peerDeviceID") ?? UUID().uuidString
        defaults.set(id, forKey: "peerDeviceID")
        let provider = LibraryShare(storage: storage) { [weak self] in await self?.shareSnapshot() ?? (Library(), []) }
        do {
            let service = try PeerService(identity: .init(id: id, name: deviceName), store: KeychainPeerSecretStore(), provider: provider)
            service.onChange = { [weak self] in Task { @MainActor in self?.refreshPeers() } }
            service.onIncomingPairing = { [weak self] session in Task { @MainActor in self?.presentIncoming(session) } }
            peerService = service
            refreshPeers()
            refreshPeerActivity()
        } catch { notify(L("Keychain unavailable: \(error.localizedDescription)")) }
    }

    private func shareSnapshot() -> (library: Library, excluded: Set<String>) { (library, Set(preferences.excludedBundleIDs)) }

    func refreshPeers() {
        guard let service = peerService else { return }
        let next = service.paired.map { PeerStatus(device: $0, online: service.isOnline($0.id)) }
        if next != peers { peers = next }
        let known = Set(next.map(\.id))
        let nearby = service.nearby.filter { !known.contains($0.id) }
        if nearby != nearbyMacs { nearbyMacs = nearby }
    }

    func refreshPeerActivity() {
        guard let service = peerService else { return }
        if preferences.shareWithPeers {
            Task { [weak self] in
                do { try await service.startSharing() } catch { self?.notify(L("Sharing unavailable: \(error.localizedDescription)")) }
            }
        } else { service.stopSharing() }
        if preferences.shareWithPeers || !peers.isEmpty || pairingSheet { service.startBrowsing() } else { service.stopBrowsing() }
    }

    func beginPairing(with device: PeerDevice) {
        guard let service = peerService else { return }
        attach(service.pair(with: device))
    }

    func confirmPairing() { pairing?.confirm() }

    func resetPairing() {
        if let pairing, !pairing.state.isFinal { pairing.cancel() }
        pairing = nil
        pairingState = nil
    }

    func closePairing() {
        resetPairing()
        pairingSheet = false
    }

    func revokePeer(_ id: String) {
        do { try peerService?.revoke(id) } catch { notify(L("Could not remove: \(error.localizedDescription)")) }
        refreshPeers()
        refreshPeerActivity()
    }

    func loadRemote() {
        remoteTask?.cancel()
        remoteItems = []; remoteRecords = [:]
        guard let peer = remotePeer else { remoteLoading = false; return }
        remoteLoading = true
        remoteTask = Task {
            do {
                let records = try await remoteClips(from: peer)
                guard !Task.isCancelled else { return }
                remoteRecords = Dictionary(records.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
                remoteItems = records.map { record in
                    var clip = Clip(id: record.id, kind: record.kind, text: record.preview, title: record.title, sourceName: L("\(record.sourceName) · from \(peer.device.name)"), sourceBundle: record.sourceBundle, copiedAt: record.copiedAt, byteCount: record.byteCount)
                    clip.firstCopiedAt = record.firstCopiedAt ?? record.copiedAt
                    return clip
                }
                remoteLoading = false
                resetSelection()
            } catch {
                guard !Task.isCancelled else { return }
                remoteLoading = false
                notify(L("\(peer.device.name) is unavailable."))
            }
        }
    }
    func remoteClips(from peer: PeerStatus, query: String = "", before: Date? = nil) async throws -> [RemoteClip] {
        guard let service = peerService else { throw PeerFailure.unavailable }
        return try await service.list(peer.id, request: .init(query: query.isEmpty ? nil : query, limit: 100, before: before))
    }

    @discardableResult func importRemote(_ remote: RemoteClip, from peer: PeerStatus) async throws -> Clip {
        guard let service = peerService else { throw PeerFailure.unavailable }
        let payload = try await service.payload(peer.id, id: remote.id)
        guard var clip = Self.clip(for: payload, sourceName: L("\(remote.sourceName) · from \(peer.device.name)"), sourceBundle: remote.sourceBundle) else { throw PeerFailure.malformed }
        clip.title = remote.title
        clip.firstCopiedAt = remote.firstCopiedAt ?? remote.copiedAt
        guard accept(clip, payload: payload), let stored = library.clips.first(where: { $0.fingerprint == clip.fingerprint }) else { throw PeerFailure.unavailable }
        return stored
    }

    static func clip(for payload: ClipPayload, sourceName: String, sourceBundle: String) -> Clip? {
        let pasteboard = NSPasteboard(name: .init("Encore-Remote-\(UUID())"))
        defer { pasteboard.releaseGlobally() }
        pasteboard.clearContents()
        pasteboard.writeObjects(payload.items.map { item in
            let value = NSPasteboardItem()
            for (type, data) in item.representations { value.setData(data, forType: .init(type)) }
            return value
        })
        guard var clip = (try? PasteboardCapture.read(pasteboard, sourceName: sourceName, sourceBundle: sourceBundle))??.clip else { return nil }
        clip.fingerprint = payload.fingerprint
        clip.byteCount = payload.byteCount
        return clip
    }

    private func presentIncoming(_ session: PairingSession) {
        guard pairing.map({ $0.state.isFinal }) ?? true else { session.cancel(); return }
        attach(session)
        pairingSheet = true
        showSettings?()
    }

    private func attach(_ session: PairingSession) {
        pairing = session
        session.onUpdate = { [weak self, weak session] _ in
            Task { @MainActor in
                guard let self, let session, self.pairing === session else { return }
                self.pairingState = session.state
                if session.state == .paired { self.notify(L("\(session.remote?.name ?? "Mac") is paired.")) }
            }
        }
        pairingState = session.state
    }

    func refreshInstalledExclusions() {
        let candidates = Set(Preferences.defaultExcludedBundleIDs + preferences.excludedBundleIDs)
        let installed = Set(candidates.filter { ApplicationCatalog.installedURL($0) != nil })
        var next = preferences
        next.reconcileDefaultExclusions(installed: installed)
        if next != preferences { preferences = next; preferences.save(demo: demo) }
        let visible = preferences.excludedBundleIDs.filter { installed.contains($0) }
        if visible != installedExcludedBundleIDs { ApplicationCatalog.invalidate(); installedExcludedBundleIDs = visible }
    }

    func removeExcludedApp(_ id: String) {
        preferences.removeExcludedApp(id)
        refreshInstalledExclusions()
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
        clearPreviewCaches(chosen)
        filePreviews.remove(chosen)
        let remaining = filtered
        cursor = remaining.isEmpty ? nil : remaining[min(position, remaining.count - 1)].id
        selection = Set(cursor.map { [$0] } ?? [])
        storage?.save(library, deleting: Array(chosen))
        notify(L("\(chosen.count) items deleted · ⌘Z to undo"))
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
        notify(L("Deletion undone"))
    }

    func paste(_ clips: [Clip]? = nil, plain: Bool = false, copyOnly: Bool = false) {
        let values = clips ?? selectedClips
        guard !values.isEmpty else { return }
        if let peer = remotePeer, case let records = values.compactMap({ remoteRecords[$0.id] }), !records.isEmpty {
            // Remote items are fetched in full and kept in the local history before pasting.
            Task {
                do {
                    var imported: [Clip] = []
                    for record in records { imported.append(try await importRemote(record, from: peer)) }
                    paste(imported, plain: plain, copyOnly: copyOnly)
                } catch { notify(L("\(peer.device.name) is unavailable.")) }
            }
            return
        }
        let payloads = values.compactMap { storage?.payload($0.id) }
        guard payloads.count == values.count else { notify(L("Content is unavailable on disk.")); return }
        let origin = values.count == 1 ? values[0].sourceBundle : ""
        if plain {
            let text = values.map { $0.text.isEmpty ? $0.recognizedText : $0.text }.joined(separator: "\n")
            guard !text.isEmpty else { notify(L("This item does not contain text.")); return }
            clipboard.write(.text(text), sourceBundle: origin)
        } else if values.count > 1 && values.allSatisfy({ [.text, .code, .link, .color].contains($0.kind) }) {
            clipboard.write(.text(values.map(\.text).joined(separator: "\n")), sourceBundle: origin)
        } else {
            clipboard.write(ClipPayload(items: payloads.flatMap(\.items)), sourceBundle: origin)
        }
        for index in library.clips.indices where values.contains(where: { $0.id == library.clips[index].id }) { library.clips[index].lastUsedAt = Date() }
        save()
        playSound(.paste)
        guard !copyOnly else { notify(L("Copied to clipboard")); return }
        accessibilityGranted = AXIsProcessTrusted()
        let target = activateTarget?()
        dismissPanel?()
        if accessibilityGranted, let target, !target.isTerminated {
            target.activate(options: [])
            deliverPaste(to: target, attempts: 12)
        } else {
            notify(L("Copied · press ⌘V, or enable direct paste in Settings."))
        }
    }

    private func deliverPaste(to target: NSRunningApplication, attempts: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) { [weak self] in
            guard let self else { return }
            guard target.isActive else {
                if attempts > 0 { self.deliverPaste(to: target, attempts: attempts - 1) }
                else { self.notify(L("Copied · click the destination app and press ⌘V.")) }
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
        notify(L("Added to queue · enable sequential paste in the shelf"))
    }

    func toggleCollecting() {
        if collecting { collecting = false; notify(L("Sequential paste disabled")); return }
        guard stackTap.enable() else { requestAccessibility(); notify(L("Allow Encore in Accessibility, then try again.")); return }
        collecting = true
        queueVisible = true
        notify(L("Queue active · copy, then paste in order with ⌘V"))
    }

    func advanceQueue() -> Bool {
        guard collecting, let id = queue.first else { return false }
        guard let payload = storage?.payload(id) else {
            collecting = false
            notify(L("Queue stopped: this item's content is unavailable."))
            return false
        }
        clipboard.write(payload, sourceBundle: library.clips.first(where: { $0.id == id })?.sourceBundle ?? "")
        playSound(.paste)
        queue.removeFirst()
        if queue.isEmpty { collecting = false; notify(L("Queue finished")) }
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
        guard payload.byteCount <= PasteboardCapture.maxBytes else { notify(L("Maximum 25 MiB per item.")); return false }
        let accepted = accept(Clip(fingerprint: payload.fingerprint, kind: .detect(text: text), text: text, title: title, byteCount: payload.byteCount), payload: payload)
        resetSelection()
        return accepted
    }

    @discardableResult func updateText(_ id: UUID, text: String, title: String) -> Bool {
        guard storageError == nil, let index = library.clips.firstIndex(where: { $0.id == id }) else { return false }
        let payload = ClipPayload.text(text)
        let duplicates = library.clips.filter { $0.id != id && $0.fingerprint == payload.fingerprint }
        guard payload.byteCount <= PasteboardCapture.maxBytes, totalBytes - library.clips[index].byteCount - duplicates.reduce(0, { $0 + $1.byteCount }) + payload.byteCount <= preferences.storageLimitMB * 1_048_576 else { notify(L("Storage limit reached.")); return false }
        library.clips[index].text = text
        library.clips[index].title = title
        library.clips[index].kind = .detect(text: text)
        library.clips[index].fingerprint = payload.fingerprint
        library.clips[index].byteCount = payload.byteCount
        library.clips[index].referencedFileBytes = nil
        richTextCache.removeValue(forKey: id)
        checkedRichText.remove(id); fileURLCache.removeValue(forKey: id)
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
        if let data = remoteRecords[clip.id]?.thumbnail, let image = NSImage(data: data) { thumbnails[clip.id] = image; return image }
        guard let payload = storage?.payload(clip.id), let data = Self.imageData(payload), let cg = Self.downsample(data, maxDimension: 640) else { return nil }
        let image = NSImage(cgImage: cg, size: .zero)
        if thumbnails.count >= 40 { thumbnails.removeAll() }
        thumbnails[clip.id] = image
        return image
    }

    func fileURLs(for clip: Clip) -> [URL] {
        if let cached = fileURLCache[clip.id] { return cached }
        let urls = storage?.payload(clip.id)?.fileURLs ?? []
        if fileURLCache.count >= 80 { fileURLCache.removeAll() }
        fileURLCache[clip.id] = urls
        return urls
    }

    func richText(for clip: Clip) -> NSAttributedString? {
        if checkedRichText.contains(clip.id) { return richTextCache[clip.id] }
        if checkedRichText.count >= 80 { checkedRichText.removeAll(); richTextCache.removeAll() }
        checkedRichText.insert(clip.id)
        guard let payload = storage?.payload(clip.id), let data = payload.items.first?.representations[NSPasteboard.PasteboardType.rtf.rawValue], data.count < 1_000_000,
              let attributed = NSAttributedString(rtf: data, documentAttributes: nil) else { return nil }
        let preview = attributed.attributedSubstring(from: NSRange(location: 0, length: min(6000, attributed.length)))
        richTextCache[clip.id] = preview
        return preview
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
                    if !text.isEmpty { self.notify(L("Image text recognized · ready to search")) }
                }
            } catch { DispatchQueue.main.async { self?.ocrJobs.remove(id); self?.notify(L("Recognition failed: \(error.localizedDescription)")) } }
        }
    }

    func createCollection() {
        let alert = NSAlert()
        alert.messageText = L("New collection")
        alert.informativeText = L("Group items together. They will be kept without expiration.")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 26))
        field.placeholderString = L("Collection name")
        alert.accessoryView = field
        alert.addButton(withTitle: L("Create")); alert.addButton(withTitle: L("Cancel"))
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
        notify(L("Collection deleted · its items remain in history"))
    }

    func exportLibrary() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "Encore-backup.json"
        panel.message = L("This backup contains your unencrypted history and content. Keep it somewhere safe.")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            storage?.flush()
            let entries = library.clips.compactMap { clip in storage?.payload(clip.id).map { Backup.Entry(clip: clip, payload: $0) } }
            guard entries.count == library.clips.count else { throw CocoaError(.fileReadCorruptFile) }
            try JSONEncoder().encode(Backup(version: 1, collections: library.collections, entries: entries)).write(to: url, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            notify(L("Backup exported"))
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
            refreshFileSizes(); prune(); resetSelection()
            notify(L("\(result.payloads.count) new items imported"))
        } catch { notify(L("Import failed: \(error.localizedDescription)")) }
    }

    func clearHistory() {
        let alert = NSAlert()
        alert.messageText = L("Clear history?")
        alert.informativeText = L("Favorites and collection items will be kept. This action cannot be undone.")
        alert.addButton(withTitle: L("Cancel")); alert.addButton(withTitle: L("Clear"))
        guard alert.runModal() == .alertSecondButtonReturn else { return }
        let ids = library.clips.filter { !$0.isProtected }.map(\.id)
        library.clips.removeAll { !$0.isProtected }
        queue.removeAll { ids.contains($0) }
        deleted = []; thumbnails.removeAll()
        clearPreviewCaches(Set(ids)); filePreviews.remove(Set(ids))
        storage?.save(library, deleting: ids)
        resetSelection()
    }

    private func seedDemo() {
        let samples: [(String, String, String)] = [
            ("Design is not just what it looks like and feels like.\n\nDesign is how it works.", "Notes", "com.apple.Notes"),
            ("https://developer.apple.com/design/human-interface-guidelines", "Safari", "com.apple.Safari"),
            ("#A78BFA", "Figma", "com.figma.Desktop"),
            ("struct GoodIdea {\n    let captured = true\n    let forgotten = false\n\n    func encore() {\n        paste(with: .joy)\n    }\n}", "Xcode", "com.apple.dt.Xcode"),
            ("Hi Sam,\n\nThanks for the feedback!\nI’ll take a look and get back to you today.\n\nBest,", "Mail", "com.apple.mail"),
            ("https://github.com", "Safari", "com.apple.Safari")
        ]
        for (index, value) in samples.reversed().enumerated() {
            let payload = ClipPayload.text(value.0)
            let clip = Clip(fingerprint: payload.fingerprint, kind: .detect(text: value.0), text: value.0, sourceName: value.1, sourceBundle: value.2, copiedAt: Date().addingTimeInterval(-Double(samples.count - index) * 180), favorite: index == 1, byteCount: payload.byteCount)
            accept(clip, payload: payload)
        }
        library.collections = [.init(name: "Work", colorIndex: 0), .init(name: "Inspiration", colorIndex: 1), .init(name: "Snippets", colorIndex: 2)]
        if let root = storage?.root, let urls = try? DemoFixtures.create(in: root.appendingPathComponent("Examples")) {
            for (index, url) in urls.enumerated() {
                let payload = ClipPayload(items: [.init([NSPasteboard.PasteboardType.fileURL.rawValue: Data(url.absoluteString.utf8)])])
                accept(Clip(fingerprint: payload.fingerprint, kind: .file, text: "", sourceName: "Finder", sourceBundle: "com.apple.finder", copiedAt: Date().addingTimeInterval(-Double(240 + index * 70)), byteCount: payload.byteCount, fileNames: [url.lastPathComponent], referencedFileBytes: PasteboardCapture.referencedSize(of: [url])), payload: payload)
            }
        }
        if let (text, payload) = try? DemoFixtures.richText() {
            accept(Clip(fingerprint: payload.fingerprint, kind: .text, text: text, sourceName: "Notes", sourceBundle: "com.apple.Notes", copiedAt: Date().addingTimeInterval(-90), byteCount: payload.byteCount), payload: payload)
        }
        library.clips.sort { $0.copiedAt > $1.copiedAt }
        save()
    }
}
