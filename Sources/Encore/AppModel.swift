import AppKit
import SwiftUI
import Vision
import ImageIO
import SystemConfiguration
import EncoreCore

struct SnippetForm: Identifiable {
    let id = UUID()
    let clip: Clip
    let fields: [String]
    let plain: Bool
    let copyOnly: Bool
}

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
    /// A detected secret only holds its masked text: editing and saving it would replace the real value with dots.
    @Published var inspector: Clip? {
        didSet {
            if inspector?.secret != nil { inspector = nil; notify(L("A masked secret cannot be edited. It still pastes as it is.")); return }
            if let inspector { presentInspector?(inspector) }
        }
    }
    /// Set by ⌘R so the inspector opens with its name field focused.
    /// The card whose name is being edited in place, from ⌘R or a click on a selected card's header.
    @Published var renamingID: UUID?
    private var pendingRename: DispatchWorkItem?
    /// A snippet waiting for its {{fields}} before being pasted.
    @Published var snippetForm: SnippetForm?
    /// The card being filed as a snippet with ⌘S.
    @Published var snippetEditor: UUID?
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
    var suspendShortcuts: (() -> Void)?
    var compactMoved: (() -> Void)?
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
    private var syncTimer: Timer?
    private var syncing = false
    /// The demo shows a generic name, so screenshots do not reveal the real one.
    var deviceName: String { demo ? "MacBook Pro" : SCDynamicStoreCopyComputerName(nil, nil) as String? ?? Host.current().localizedName ?? "Mac" }
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

    /// Matching items in display order: snippets grouped by language or tag, name matches first while searching.
    var filtered: [Clip] {
        let search = ClipQuery(query: query, kind: kind, source: source, favorites: board == "favorites", snippets: board == "snippets", collectionID: UUID(uuidString: board))
        let matches = boardClips.filter { search.matches($0) }
        if board == "snippets" {
            // Groups in alphabetical order, untagged last; most recent first inside a group.
            return matches.enumerated().sorted { a, b in
                let (left, right) = (a.element.snippetGroup, b.element.snippetGroup)
                if left == right { return a.offset < b.offset }
                if left.isEmpty || right.isEmpty { return right.isEmpty }
                return left.localizedStandardCompare(right) == .orderedAscending
            }.map(\.element)
        }
        let named = matches.filter(search.matchesName)
        return named.isEmpty ? matches : named + matches.filter { !search.matchesName($0) }
    }
    /// Cards in sections: by group on Snippets, otherwise name matches then days.
    var sections: [ClipSection] {
        let clips = filtered
        if board == "snippets" { return ClipSection.snippets(clips) }
        let search = ClipQuery(query: query)
        return ClipSection.group(clips, now: displayTime, named: clips.prefix(while: search.matchesName).count)
    }
    /// Local history, or the recent history of the paired Mac picked as board ("peer:<device id>").
    var boardClips: [Clip] { remotePeer == nil ? library.clips : remoteItems }
    /// The Snippets board appears with the first snippet.
    var hasSnippets: Bool { library.clips.contains(where: \.snippet) }
    var boards: [String] { ["history", "favorites"] + (hasSnippets ? ["snippets"] : []) + library.collections.map(\.id.uuidString) + peers.map { "peer:\($0.id)" } }
    var remotePeer: PeerStatus? { board.hasPrefix("peer:") ? peers.first { "peer:\($0.id)" == board } : nil }
    /// The narrow column on a side of the screen, instead of the shelf.
    var sideColumn: Bool { preferences.placement == "compact" }
    /// The column is on screen: the library opened from it replaces it until ↓ is held.
    var columnShown: Bool { sideColumn && !expanded }
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
        let sections = self.sections.map { $0.items.map(\.clip.id) }
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
        // A secret goes as soon as its time is up, without waiting for the minute's pruning.
        if clip.secret != nil && preferences.detectSecrets {
            DispatchQueue.main.asyncAfter(deadline: .now() + preferences.secretLifetime + 1) { [weak self] in self?.prune() }
        }
        playSound(.capture)
        return true
    }

    func save() { storage?.save(library) }

    /// The app a copy came from cleared the clipboard soon after: that copy was meant to be temporary.
    func forgetCleared(_ id: UUID) {
        guard let clip = library.clips.first(where: { $0.id == id }), !clip.isProtected else { return }
        library.clips.removeAll { $0.id == id }
        queue.removeAll { $0 == id }
        thumbnails.removeValue(forKey: id)
        clearPreviewCaches([id]); filePreviews.remove([id])
        storage?.save(library, deleting: [id])
        reconcileSelection()
        notify(L("Removed from history: its app cleared the clipboard"))
    }

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

    /// Something expires within the minute: the cards then count down by the second.
    var expiresWithinAMinute: Bool {
        let now = Date()
        return library.clips.contains { clip in
            guard let deadline = retentionDecision(for: clip).expiresAt else { return false }
            return deadline.timeIntervalSince(now) < 61
        }
    }

    func relativeAge(_ date: Date) -> String { Localization.relative(date, to: displayTime) }

    func remainingRetention(for clip: Clip) -> String {
        guard let deadline = retentionDecision(for: clip).expiresAt else { return L("Forever") }
        let seconds = deadline.timeIntervalSince(displayTime)
        guard seconds > 0 else { return L("Expiring now") }
        if seconds < 60 { return L("Expires in \(Localization.seconds(seconds))") }
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
        let provider = LibraryShare(storage: storage, access: { [weak self] in await self?.shareAccess() ?? ShareAccess(history: false, synced: []) }) { [weak self] in await self?.shareSnapshot() ?? (Library(), []) }
        do {
            let service = try PeerService(identity: .init(id: id, name: deviceName), store: FilePeerSecretStore(url: storage.root.appendingPathComponent("Peers.json"), legacy: KeychainPeerSecretStore()), provider: provider)
            service.onChange = { [weak self] in Task { @MainActor in self?.refreshPeers() } }
            service.onIncomingPairing = { [weak self] session in Task { @MainActor in self?.presentIncoming(session) } }
            peerService = service
            refreshPeers()
            refreshPeerActivity()
        } catch { notify(L("Pairing unavailable: \(error.localizedDescription)")) }
    }

    private func shareSnapshot() -> (library: Library, excluded: Set<String>) { (library, Set(preferences.excludedBundleIDs)) }
    private func shareAccess() -> ShareAccess { ShareAccess(history: preferences.shareWithPeers, synced: syncedCategories) }
    /// Favorites and snippets each have their own sync setting.
    var syncedCategories: Set<PinnedCategory> {
        Set([preferences.syncFavorites ? .favorites : nil, preferences.syncSnippets ? .snippets : nil].compactMap { $0 })
    }

    func refreshPeers() {
        guard let service = peerService else { return }
        let next = service.paired.map { PeerStatus(device: $0, online: service.isOnline($0.id)) }
        if next != peers {
            // A Mac that just came online is synced right away rather than at the next round.
            let cameOnline = next.contains { peer in peer.online && !peers.contains { $0.id == peer.id && $0.online } }
            peers = next
            updateSyncTimer()
            if cameOnline { syncPinnedNow() }
        }
        let known = Set(next.map(\.id))
        let nearby = service.nearby.filter { !known.contains($0.id) }
        if nearby != nearbyMacs { nearbyMacs = nearby }
    }

    func refreshPeerActivity() {
        guard let service = peerService else { return }
        // Syncing needs this Mac to answer its peers too, but only favorites and snippets are served unless history sharing is on.
        if preferences.shareWithPeers || !syncedCategories.isEmpty {
            Task { [weak self] in
                do { try await service.startSharing() } catch { self?.notify(L("Sharing unavailable: \(error.localizedDescription)")) }
            }
        } else { service.stopSharing() }
        if preferences.shareWithPeers || !syncedCategories.isEmpty || !peers.isEmpty || pairingSheet { service.startBrowsing() } else { service.stopBrowsing() }
        updateSyncTimer()
    }

    private static let syncInterval: TimeInterval = 30

    private func updateSyncTimer() {
        if !syncedCategories.isEmpty && !peers.isEmpty {
            guard syncTimer == nil else { return }
            syncTimer = Timer.scheduledTimer(withTimeInterval: Self.syncInterval, repeats: true) { [weak self] _ in Task { @MainActor in self?.syncPinnedNow() } }
            syncPinnedNow()
        } else { syncTimer?.invalidate(); syncTimer = nil }
    }

    /// Pulls the favorites and snippets of each connected Mac and merges them. Each Mac pulls from the others, so changes travel both ways.
    func syncPinnedNow() {
        guard !syncedCategories.isEmpty, !syncing, let service = peerService, storage != nil, storageError == nil else { return }
        let online = peers.filter(\.online)
        guard !online.isEmpty else { return }
        syncing = true
        Task {
            defer { syncing = false }
            for peer in online {
                // A Mac without syncing, or with it turned off, answers with an error: it is skipped until the next round.
                guard let state = try? await service.pinned(peer.id) else { continue }
                await merge(state, from: peer, service: service)
            }
        }
    }

    private func merge(_ state: PinnedState, from peer: PeerStatus, service: PeerService) async {
        let before = pinnedSignature
        let missing = library.merge(state, categories: syncedCategories)
        let adopted = syncedCategories.intersection(state.categories)
        var added: [(UUID, ClipPayload)] = []
        for item in missing {
            guard let payload = try? await service.payload(peer.id, id: item.id), payload.fingerprint == item.fingerprint,
                  !library.clips.contains(where: { $0.fingerprint == item.fingerprint }),
                  totalBytes + payload.byteCount <= preferences.storageLimitMB * 1_048_576,
                  var clip = Self.clip(for: payload, sourceName: L("\(item.sourceName) · from \(peer.device.name)"), sourceBundle: item.sourceBundle) else { continue }
            clip.fingerprint = payload.fingerprint
            clip.adopt(item, categories: adopted)
            library.clips.append(clip)
            added.append((clip.id, payload))
        }
        guard !added.isEmpty || pinnedSignature != before else { return }
        library.clips.sort { $0.copiedAt > $1.copiedAt }
        if added.isEmpty { save() } else { storage?.save(library, payloads: added) }
        if board == "snippets" && !hasSnippets { board = "history" } else { reconcileSelection() }
    }

    /// Changes only when a sync altered favorites, snippets or their details, so an idle sync never rewrites the library.
    private var pinnedSignature: Int {
        var hasher = Hasher()
        for clip in library.clips where clip.isPinned || clip.favoriteChangedAt != nil || clip.snippetChangedAt != nil {
            hasher.combine(clip.fingerprint); hasher.combine(clip.favorite); hasher.combine(clip.snippet); hasher.combine(clip.name)
            hasher.combine(clip.tags); hasher.combine(clip.language); hasher.combine(clip.favoriteChangedAt); hasher.combine(clip.snippetChangedAt)
        }
        hasher.combine(library.removedFavorites)
        hasher.combine(library.removedSnippets)
        hasher.combine(library.clips.count)
        return hasher.finalize()
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

    /// Whether Return and double-click paste into the front app rather than only copy.
    var pastesDirectly: Bool { preferences.pasteDirectly && accessibilityGranted }

    func notify(_ message: String) {
        statusTask?.cancel()
        status = message
        statusTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            guard !Task.isCancelled else { return }
            self?.status = ""
        }
    }

    func toggleFavorite(_ ids: Set<UUID>? = nil) {
        let chosen = ids ?? selection
        let shouldPin = !library.clips.filter { chosen.contains($0.id) }.allSatisfy(\.favorite)
        for index in library.clips.indices where chosen.contains(library.clips[index].id) {
            let was = library.clips[index].favorite
            library.clips[index].favorite = shouldPin
            library.changed(.favorites, index, was: was)
        }
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
        for clip in library.clips where chosen.contains(clip.id) { library.pinnedDeleted(clip) }
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
            if clip.favorite { library.changed(.favorites, library.clips.count - 1, was: false) }
            if clip.snippet { library.changed(.snippets, library.clips.count - 1, was: false) }
            storage?.save(library, payload: (clip.id, payload))
        }
        library.clips.sort { $0.copiedAt > $1.copiedAt }
        deleted = []
        save()
        resetSelection()
        notify(L("Deletion undone"))
    }

    /// `fields` holds the values typed in the snippet form; without them a snippet with {{fields}} opens the form first.
    func paste(_ clips: [Clip]? = nil, plain: Bool = false, copyOnly: Bool = false, fields: [String: String]? = nil) {
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
        var charactersAfterCursor: Int?
        var exact = false
        if values.count == 1, values[0].snippet, let template = SnippetTemplate(values[0].text) {
            if fields == nil, !template.fields.isEmpty { snippetForm = SnippetForm(clip: values[0], fields: template.fields, plain: plain, copyOnly: copyOnly); return }
            let rendered = template.render(values: fields ?? [:], clipboard: clipboard.currentText)
            clipboard.write(.text(rendered.text), sourceBundle: origin)
            charactersAfterCursor = rendered.charactersAfterCursor
        } else if plain {
            let text = values.map { $0.text.isEmpty ? $0.recognizedText : $0.text }.joined(separator: "\n")
            guard !text.isEmpty else { notify(L("This item does not contain text.")); return }
            clipboard.write(.text(text), sourceBundle: origin)
        } else if values.count > 1 && values.allSatisfy({ [.text, .code, .link, .color].contains($0.kind) }) {
            clipboard.write(.text(values.map(\.text).joined(separator: "\n")), sourceBundle: origin)
        } else {
            clipboard.write(ClipPayload(items: payloads.flatMap(\.items)), sourceBundle: origin)
            exact = values.count == 1
        }
        for index in library.clips.indices where values.contains(where: { $0.id == library.clips[index].id }) { library.clips[index].lastUsedAt = Date() }
        let pasting = !copyOnly && preferences.pasteDirectly
        if !pasting, exact, let index = library.clips.firstIndex(where: { $0.id == values[0].id }) {
            // The item is now the current clipboard, so it moves back to the top like a fresh copy. Plain text or a filled snippet is a different content and leaves it in place.
            library.clips[index].firstCopiedAt = library.clips[index].firstCopyDate
            library.clips[index].copiedAt = Date()
            library.clips.sort { $0.copiedAt > $1.copiedAt }
        }
        save()
        playSound(.paste)
        guard pasting else { if !copyOnly { dismissPanel?() }; notify(L("Copied to clipboard")); return }
        accessibilityGranted = AXIsProcessTrusted()
        let target = activateTarget?()
        dismissPanel?()
        if accessibilityGranted, let target, !target.isTerminated {
            target.activate(options: [])
            deliverPaste(to: target, attempts: 12, charactersAfterCursor: charactersAfterCursor ?? 0)
        } else {
            notify(L("Copied · press ⌘V, or enable direct paste in Settings."))
        }
    }

    /// After ⌘V, a snippet's {{cursor}} is reached with ← presses, one per character pasted after it.
    private func deliverPaste(to target: NSRunningApplication, attempts: Int, charactersAfterCursor: Int = 0) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) { [weak self] in
            guard let self else { return }
            guard target.isActive else {
                if attempts > 0 { self.deliverPaste(to: target, attempts: attempts - 1, charactersAfterCursor: charactersAfterCursor) }
                else { self.notify(L("Copied · click the destination app and press ⌘V.")) }
                return
            }
            let source = CGEventSource(stateID: .combinedSessionState)
            Self.postKey(9, flags: .maskCommand, source: source)
            for _ in 0..<min(charactersAfterCursor, 2000) { Self.postKey(123, source: source) }
        }
    }

    private static func postKey(_ key: CGKeyCode, flags: CGEventFlags = [], source: CGEventSource?) {
        let down = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false)
        down?.flags = flags; up?.flags = flags
        down?.setIntegerValueField(.eventSourceUserData, value: StackTap.syntheticTag)
        up?.setIntegerValueField(.eventSourceUserData, value: StackTap.syntheticTag)
        down?.post(tap: .cghidEventTap); up?.post(tap: .cghidEventTap)
    }

    /// Saves a name, tags and language. Naming or tagging an item makes it a snippet.
    func updateSnippet(_ id: UUID, name: String, tags: [String], language: String?, snippet: Bool = false) {
        guard let index = library.clips.firstIndex(where: { $0.id == id }) else { return }
        let was = library.clips[index].snippet
        library.clips[index].name = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(100))
        library.clips[index].tags = tags
        library.clips[index].language = language
        if snippet || !library.clips[index].name.isEmpty || !tags.isEmpty { library.clips[index].snippet = true }
        library.changed(.snippets, index, was: was)
        save()
        reconcileSelection()
    }

    /// A click on a selected card's header renames it, unless a second click turns it into a double-click.
    func scheduleRename(_ id: UUID) {
        pendingRename?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.cursor == id, self.selection == [id] else { return }
            self.renamingID = id
        }
        pendingRename = work
        DispatchQueue.main.asyncAfter(deadline: .now() + NSEvent.doubleClickInterval, execute: work)
    }

    func cancelRename() { pendingRename?.cancel(); pendingRename = nil }

    func rename(_ id: UUID, to name: String) {
        renamingID = nil
        guard let clip = library.clips.first(where: { $0.id == id }), clip.name != name.trimmingCharacters(in: .whitespacesAndNewlines) else { return }
        updateSnippet(id, name: name, tags: clip.tags, language: clip.language)
    }

    /// Tags used on the current board, for the library filters.
    var tags: [String] { Array(Set(boardClips.flatMap(\.tags))).sorted { $0.localizedStandardCompare($1) == .orderedAscending } }

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
        // Other Macs know the item by its content: the old content is removed there and the new one added.
        if library.clips[index].fingerprint != payload.fingerprint { library.pinnedDeleted(library.clips[index]) }
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
            library.clips[index].adoptSnippetDetails(of: duplicate)
        }
        let removed = Set(duplicates.map(\.id))
        library.clips.removeAll { removed.contains($0.id) }
        if let index = library.clips.firstIndex(where: { $0.id == id }) {
            if library.clips[index].favorite { library.changed(.favorites, index, was: true) }
            if library.clips[index].snippet { library.changed(.snippets, index, was: true) }
        }
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
        // A secret shows its masked text only, even when it was copied with formatting.
        guard clip.secret == nil else { return nil }
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
            if #available(macOS 13, *) { request.automaticallyDetectsLanguage = true }
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

    /// Removes items from the snippets; they keep their name, tags and language, and return to the normal history lifetime.
    func removeSnippets(_ ids: Set<UUID>) {
        for index in library.clips.indices where ids.contains(library.clips[index].id) {
            let was = library.clips[index].snippet
            library.clips[index].snippet = false
            library.changed(.snippets, index, was: was)
        }
        save()
        if board == "snippets" && !hasSnippets { board = "history" } else { reconcileSelection() }
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
        panel.nameFieldStringValue = "encore-backup.json"
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

    func exportSnippets() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "encore-snippets.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            let file = SnippetFile(library: library)
            try encoder.encode(file).write(to: url, options: .atomic)
            notify(L("Snippets exported: \(file.snippets.count)"))
        } catch { notify(error.localizedDescription) }
    }

    func importSnippets() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size < 100_000_000 else { throw CocoaError(.fileReadTooLarge) }
            let result = try JSONDecoder().decode(SnippetFile.self, from: Data(contentsOf: url)).merged(into: library)
            guard totalBytes + result.payloads.reduce(0, { $0 + $1.1.byteCount }) <= preferences.storageLimitMB * 1_048_576 else { throw CocoaError(.fileWriteOutOfSpace) }
            library = result.library
            storage?.save(library, payloads: result.payloads)
            resetSelection()
            notify(L("\(result.payloads.count) new items imported"))
        } catch { notify(L("Import failed: \(error.localizedDescription)")) }
    }

    /// Asks first, then clears the history, keeping favorites, snippets and collection items, or clears everything.
    /// Reached from Settings, the menu bar icon and `open encore://clear-history`.
    /// A link can open this from a web page: Return cancels, both ways to clear need a click, and only one confirmation shows at a time.
    func clearHistory() {
        guard !confirmingClear else { return }
        confirmingClear = true
        defer { confirmingClear = false }
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = L("Clear history?")
        alert.informativeText = L("Clear History keeps favorites, snippets and collection items. Clear Everything removes them too. This cannot be undone.")
        alert.addButton(withTitle: L("Clear History")); alert.addButton(withTitle: L("Clear Everything")); alert.addButton(withTitle: L("Cancel"))
        alert.buttons[0].keyEquivalent = ""
        alert.buttons[1].hasDestructiveAction = true
        alert.buttons[2].keyEquivalent = "\r"
        switch alert.runModal() {
        case .alertFirstButtonReturn: clear(everything: false)
        case .alertSecondButtonReturn: clear(everything: true)
        default: break
        }
    }

    private var confirmingClear = false

    func clear(everything: Bool) {
        let ids = library.clips.filter { everything || !$0.isProtected }.map(\.id)
        library.clips.removeAll { everything || !$0.isProtected }
        queue.removeAll { ids.contains($0) }
        deleted = []; thumbnails.removeAll()
        clearPreviewCaches(Set(ids)); filePreviews.remove(Set(ids))
        storage?.save(library, deleting: ids)
        resetSelection()
    }

    private func seedDemo() {
        let samples: [(String, String, String)] = [
            (DemoFixtures.text("Design is not just what it looks like and feels like.\n\nDesign is how it works.", "Le design, ce n’est pas seulement ce qu’on voit et ce qu’on ressent.\n\nLe design, c’est comment ça marche."), "Notes", "com.apple.Notes"),
            ("https://developer.apple.com/design/human-interface-guidelines", "Safari", "com.apple.Safari"),
            ("#A78BFA", "Figma", "com.figma.Desktop"),
            ("struct GoodIdea {\n    let captured = true\n    let forgotten = false\n\n    func encore() {\n        paste(with: .joy)\n    }\n}", "Xcode", "com.apple.dt.Xcode"),
            (DemoFixtures.text("Hi Sam,\n\nThanks for the feedback!\nI’ll take a look and get back to you today.\n\nBest,", "Bonjour Sam,\n\nMerci pour ton retour !\nJe regarde ça et je te réponds aujourd’hui.\n\nBonne journée,"), "Mail", "com.apple.mail"),
            ("https://github.com", "Safari", "com.apple.Safari")
        ]
        for (index, value) in samples.reversed().enumerated() {
            let payload = ClipPayload.text(value.0)
            let clip = Clip(fingerprint: payload.fingerprint, kind: .detect(text: value.0), text: value.0, sourceName: value.1, sourceBundle: value.2, copiedAt: Date().addingTimeInterval(-Double(samples.count - index) * 180), favorite: index == 1, byteCount: payload.byteCount)
            accept(clip, payload: payload)
        }
        library.collections = [.init(name: DemoFixtures.text("Work", "Travail"), colorIndex: 0), .init(name: "Inspiration", colorIndex: 1), .init(name: DemoFixtures.text("Snippets", "Extraits"), colorIndex: 2)]
        if let root = storage?.root, let urls = try? DemoFixtures.create(in: root.appendingPathComponent("Examples")) {
            for (index, url) in urls.enumerated() {
                let payload = ClipPayload(items: [.init([NSPasteboard.PasteboardType.fileURL.rawValue: Data(url.absoluteString.utf8)])])
                accept(Clip(fingerprint: payload.fingerprint, kind: .file, text: "", sourceName: "Finder", sourceBundle: "com.apple.finder", copiedAt: Date().addingTimeInterval(-Double(240 + index * 70)), byteCount: payload.byteCount, fileNames: [url.lastPathComponent], referencedFileBytes: PasteboardCapture.referencedSize(of: [url])), payload: payload)
            }
        }
        if let (text, payload) = try? DemoFixtures.richText() {
            accept(Clip(fingerprint: payload.fingerprint, kind: .text, text: text, sourceName: "Notes", sourceBundle: "com.apple.Notes", copiedAt: Date().addingTimeInterval(-90), byteCount: payload.byteCount), payload: payload)
        }
        // `--demo --secrets` adds masked secrets with detection on, for screenshots of the feature.
        if CommandLine.arguments.contains("--secrets") {
            preferences.detectSecrets = true
            for (value, kind, source, bundle, age) in [("k9#Lm2!qZxP4", SecretKind.password, "Firefox", "org.mozilla.firefox", 20.0), ("sk-ant-api03-Zq8xV2mN5pL1kR7tY4wB", .apiKey, "Terminal", "com.apple.Terminal", 45)] {
                let payload = ClipPayload.text(value)
                var clip = Clip(fingerprint: payload.fingerprint, kind: .text, text: SecretKind.mask(value, keeping: preferences.secretPreview), sourceName: source, sourceBundle: bundle, copiedAt: Date().addingTimeInterval(-age), byteCount: payload.byteCount)
                clip.secret = kind
                accept(clip, payload: payload)
            }
        }
        library.clips.sort { $0.copiedAt > $1.copiedAt }
        save()
    }
}
