import XCTest
@testable import EncoreCore

final class PinnedSyncTests: XCTestCase {
    private let both = Set(PinnedCategory.allCases)

    private func clip(_ text: String, favorite: Bool = false, snippet: Bool = false, favoriteChanged: Date? = nil, snippetChanged: Date? = nil) -> Clip {
        var clip = Clip(fingerprint: ClipPayload.text(text).fingerprint, kind: .text, text: text, favorite: favorite)
        clip.snippet = snippet
        clip.favoriteChangedAt = favoriteChanged
        clip.snippetChangedAt = snippetChanged
        return clip
    }

    func testFirstSyncMergesBothSides() {
        var mine = Library(), theirs = Library()
        mine.clips = [clip("shared", favorite: true), clip("only mine", snippet: true)]
        var shared = clip("shared", snippet: true)
        shared.name = "Shared"
        theirs.clips = [shared, clip("only theirs", favorite: true), clip("not pinned")]
        let missing = mine.merge(theirs.pinnedState(categories: both, excluded: []), categories: both)
        XCTAssertEqual(missing.map(\.fingerprint), [ClipPayload.text("only theirs").fingerprint])
        XCTAssertTrue(mine.clips[0].favorite && mine.clips[0].snippet)
        XCTAssertEqual(mine.clips[0].name, "Shared")
        var fetched = Clip(fingerprint: missing[0].fingerprint, kind: .text, text: "only theirs")
        fetched.adopt(missing[0], categories: both)
        XCTAssertTrue(fetched.favorite)
    }

    func testNewerChangeWinsEitherWay() {
        let old = Date(timeIntervalSince1970: 1_000), new = Date(timeIntervalSince1970: 2_000)
        var mine = Library(), theirs = Library()
        var renamed = clip("text", snippet: true, snippetChanged: new)
        renamed.name = "New name"
        mine.clips = [clip("text", snippet: true, snippetChanged: old)]
        theirs.clips = [renamed]
        _ = mine.merge(theirs.pinnedState(categories: both, excluded: []), categories: both)
        XCTAssertEqual(mine.clips[0].name, "New name")
        XCTAssertEqual(mine.clips[0].snippetChangedAt, new)

        // An older remote state does not undo a newer local edit.
        var stale = Library()
        stale.clips = [clip("text", snippet: true, snippetChanged: old)]
        _ = mine.merge(stale.pinnedState(categories: both, excluded: []), categories: both)
        XCTAssertEqual(mine.clips[0].name, "New name")
    }

    func testEachCategorySyncsOnItsOwn() {
        let old = Date(timeIntervalSince1970: 1_000), new = Date(timeIntervalSince1970: 2_000)
        var mine = Library(), theirs = Library()
        // Favorited here; there, only its snippet was renamed later. With favorites synced, the later rename must not unfavorite it.
        mine.clips = [clip("x", favorite: true, favoriteChanged: old), clip("their snippet only")]
        var renamed = clip("x", snippet: true, snippetChanged: new)
        renamed.name = "Theirs"
        theirs.clips = [renamed, clip("their snippet only", snippet: true)]
        let missing = mine.merge(theirs.pinnedState(categories: both, excluded: []), categories: [.favorites])
        XCTAssertTrue(missing.isEmpty)
        XCTAssertTrue(mine.clips[0].favorite)
        XCTAssertFalse(mine.clips[0].snippet, "snippets are not synced on this Mac")
        XCTAssertEqual(mine.clips[0].name, "")
        XCTAssertFalse(mine.clips[1].snippet)

        // A Mac that syncs only snippets shares nothing about its favorites.
        var favoritesOnly = Library()
        favoritesOnly.clips = [clip("fav", favorite: true)]
        XCTAssertTrue(favoritesOnly.pinnedState(categories: [.snippets], excluded: []).items.isEmpty)
        var other = Library()
        XCTAssertTrue(other.merge(favoritesOnly.pinnedState(categories: [.favorites], excluded: []), categories: [.snippets]).isEmpty)
    }

    func testRemovalsTravelAndAreNotUndone() {
        let now = Date(), before = now.addingTimeInterval(-60)
        var mine = Library(), theirs = Library()
        mine.clips = [clip("a", favorite: true, favoriteChanged: before), clip("b", snippet: true, snippetChanged: before)]
        theirs.clips = [clip("a", favorite: true, favoriteChanged: before)]
        // They unfavorite "a", and delete "b" which they had as a snippet.
        theirs.clips[0].favorite = false
        theirs.changed(.favorites, 0, was: true, at: now)
        theirs.pinnedDeleted(clip("b", snippet: true), at: now)
        XCTAssertTrue(theirs.pinnedState(categories: both, excluded: []).items.isEmpty)

        _ = mine.merge(theirs.pinnedState(categories: both, excluded: [], now: now), categories: both, now: now)
        XCTAssertFalse(mine.clips[0].isPinned)
        XCTAssertFalse(mine.clips[1].isPinned)
        XCTAssertEqual(mine.clips.count, 2, "a removal unpins; the item stays in the history")

        // A third Mac still holding the old snippet "b" does not bring it back.
        var third = Library()
        third.clips = [clip("b", snippet: true, snippetChanged: before)]
        var fresh = Library()
        fresh.removedSnippets = mine.removedSnippets
        XCTAssertTrue(fresh.merge(third.pinnedState(categories: both, excluded: []), categories: both, now: now).isEmpty)
        // But making it a snippet again later wins over the removal.
        third.clips[0].snippetChangedAt = now.addingTimeInterval(60)
        XCTAssertEqual(fresh.merge(third.pinnedState(categories: both, excluded: []), categories: both, now: now).count, 1)
    }

    func testExcludedAppsAndOldRemovalsAreNotShared() {
        var library = Library()
        var excluded = clip("vault", favorite: true)
        excluded.sourceBundle = "com.example.vault"
        library.clips = [excluded, clip("kept", favorite: true)]
        let now = Date()
        library.removedFavorites = ["recent": now, "old": now.addingTimeInterval(-Library.removalMemory - 1)]
        let state = library.pinnedState(categories: both, excluded: ["com.example.vault"], now: now)
        XCTAssertEqual(state.items.map(\.fingerprint), [ClipPayload.text("kept").fingerprint])
        XCTAssertEqual(Array(state.removedFavorites.keys), ["recent"])
    }
}
