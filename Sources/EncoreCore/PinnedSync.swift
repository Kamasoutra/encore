import Foundation

/// The two kinds of kept items that paired Macs can sync, each with its own setting, change dates and removals.
public enum PinnedCategory: String, Codable, CaseIterable, Sendable {
    case favorites, snippets
}

/// A favorite or snippet as another Mac sees it when syncing. Items are matched by content fingerprint, since ids differ between Macs.
/// Fields of a category the sending Mac does not sync are left empty and ignored.
public struct PinnedClip: Codable, Equatable, Sendable {
    public var id: UUID
    public var fingerprint: String
    public var kind: ClipKind
    public var title: String
    public var byteCount: Int
    public var copiedAt: Date
    public var sourceName: String
    public var sourceBundle: String
    public var favorite: Bool
    public var favoriteChangedAt: Date
    public var snippet: Bool
    public var name: String
    public var tags: [String]
    public var language: String?
    public var snippetChangedAt: Date

    public init(_ clip: Clip, categories: Set<PinnedCategory>) {
        id = clip.id; fingerprint = clip.fingerprint; kind = clip.kind; title = clip.title; byteCount = clip.byteCount
        copiedAt = clip.copiedAt; sourceName = clip.sourceName; sourceBundle = clip.sourceBundle
        let favorites = categories.contains(.favorites), snippets = categories.contains(.snippets)
        favorite = favorites && clip.favorite
        favoriteChangedAt = favorites ? clip.favoriteChangedAt ?? .distantPast : .distantPast
        snippet = snippets && clip.snippet
        name = snippets ? clip.name : ""
        tags = snippets ? clip.tags : []
        language = snippets ? clip.language : nil
        snippetChangedAt = snippets ? clip.snippetChangedAt ?? .distantPast : .distantPast
    }
}

/// What a Mac shares when syncing: the categories it syncs, its items in them, and the items it removed from them recently so the others remove them too.
public struct PinnedState: Codable, Equatable, Sendable {
    public var categories: Set<PinnedCategory>
    public var items: [PinnedClip]
    public var removedFavorites: [String: Date]
    public var removedSnippets: [String: Date]
}

extension Clip {
    public var isPinned: Bool { favorite || snippet }

    func pinned(in category: PinnedCategory) -> Bool { category == .favorites ? favorite : snippet }

    func changedAt(_ category: PinnedCategory) -> Date { (category == .favorites ? favoriteChangedAt : snippetChangedAt) ?? .distantPast }

    /// Copies one category's state from another Mac's item.
    mutating func take(_ category: PinnedCategory, from item: PinnedClip) {
        switch category {
        case .favorites:
            favorite = item.favorite; favoriteChangedAt = item.favoriteChangedAt
        case .snippets:
            snippet = item.snippet; name = item.name; tags = item.tags; language = item.language; snippetChangedAt = item.snippetChangedAt
        }
    }

    /// Copies the synced state of an item fetched from another Mac.
    public mutating func adopt(_ item: PinnedClip, categories: Set<PinnedCategory>) {
        for category in categories { take(category, from: item) }
        title = item.title; copiedAt = item.copiedAt
    }
}

extension Library {
    /// Removals are remembered this long, enough for a Mac that was away to learn about them.
    public static let removalMemory: TimeInterval = 90 * 86_400

    private func removed(_ category: PinnedCategory) -> [String: Date] { (category == .favorites ? removedFavorites : removedSnippets) ?? [:] }

    private mutating func remember(_ category: PinnedCategory, _ fingerprint: String, at date: Date) {
        guard !fingerprint.isEmpty, removed(category)[fingerprint].map({ $0 < date }) ?? true else { return }
        var values = removed(category)
        values[fingerprint] = date
        if category == .favorites { removedFavorites = values } else { removedSnippets = values }
    }

    private mutating func forget(_ category: PinnedCategory, _ fingerprint: String) {
        if category == .favorites { removedFavorites?.removeValue(forKey: fingerprint) } else { removedSnippets?.removeValue(forKey: fingerprint) }
    }

    /// Records a local change to an item's favorite, or to its snippet state or details, so the newest change wins between Macs.
    public mutating func changed(_ category: PinnedCategory, _ index: Int, was: Bool, at date: Date = Date()) {
        if category == .favorites { clips[index].favoriteChangedAt = date } else { clips[index].snippetChangedAt = date }
        let fingerprint = clips[index].fingerprint
        if clips[index].pinned(in: category) { forget(category, fingerprint) } else if was { remember(category, fingerprint, at: date) }
    }

    /// A pinned item being deleted is remembered, so other Macs do not bring it back.
    public mutating func pinnedDeleted(_ clip: Clip, at date: Date = Date()) {
        for category in PinnedCategory.allCases where clip.pinned(in: category) { remember(category, clip.fingerprint, at: date) }
    }

    public func pinnedState(categories: Set<PinnedCategory>, excluded: Set<String>, now: Date = Date()) -> PinnedState {
        let recent = { (values: [String: Date]) in values.filter { now.timeIntervalSince($0.value) < Self.removalMemory } }
        return PinnedState(
            categories: categories,
            items: clips.filter { clip in !clip.fingerprint.isEmpty && categories.contains(where: clip.pinned(in:)) && LibraryShare.shareable(clip, excluded: excluded) }
                .map { PinnedClip($0, categories: categories) },
            removedFavorites: categories.contains(.favorites) ? recent(removed(.favorites)) : [:],
            removedSnippets: categories.contains(.snippets) ? recent(removed(.snippets)) : [:])
    }

    /// Applies another Mac's state for the categories both Macs sync. The newer change wins for an item both have;
    /// equal changes, such as two libraries that never synced, are merged. Returns the items this library lacks, to fetch and `adopt`.
    public mutating func merge(_ state: PinnedState, categories local: Set<PinnedCategory>, now: Date = Date()) -> [PinnedClip] {
        let categories = local.intersection(state.categories)
        var indices = Dictionary(clips.enumerated().map { ($0.element.fingerprint, $0.offset) }, uniquingKeysWith: { first, _ in first })
        for category in categories {
            for (fingerprint, date) in category == .favorites ? state.removedFavorites : state.removedSnippets where now.timeIntervalSince(date) < Self.removalMemory {
                if let index = indices[fingerprint], clips[index].changedAt(category) < date {
                    if category == .favorites { clips[index].favorite = false; clips[index].favoriteChangedAt = date }
                    else { clips[index].snippet = false; clips[index].snippetChangedAt = date }
                }
                remember(category, fingerprint, at: date)
            }
        }
        var missing: [PinnedClip] = []
        for item in state.items where !item.fingerprint.isEmpty {
            guard let index = indices[item.fingerprint] else {
                // Fetched only if pinned in a shared category that this Mac has not removed it from since.
                let wanted = categories.contains { category in
                    let (pinned, changed) = category == .favorites ? (item.favorite, item.favoriteChangedAt) : (item.snippet, item.snippetChangedAt)
                    return pinned && removed(category)[item.fingerprint].map { $0 < changed } ?? true
                }
                if wanted { missing.append(item); indices[item.fingerprint] = -1 }
                continue
            }
            guard index >= 0 else { continue }
            for category in categories {
                let remote = category == .favorites ? item.favoriteChangedAt : item.snippetChangedAt
                if remote > clips[index].changedAt(category) {
                    clips[index].take(category, from: item)
                } else if remote == clips[index].changedAt(category) {
                    if category == .favorites { clips[index].favorite = clips[index].favorite || item.favorite }
                    else {
                        var incoming = Clip(kind: item.kind, text: "")
                        incoming.snippet = item.snippet; incoming.name = item.name; incoming.tags = item.tags; incoming.language = item.language
                        clips[index].adoptSnippetDetails(of: incoming)
                    }
                }
                if clips[index].pinned(in: category) { forget(category, item.fingerprint) }
            }
        }
        removedFavorites = removedFavorites?.filter { now.timeIntervalSince($0.value) < Self.removalMemory }
        removedSnippets = removedSnippets?.filter { now.timeIntervalSince($0.value) < Self.removalMemory }
        return missing
    }
}
