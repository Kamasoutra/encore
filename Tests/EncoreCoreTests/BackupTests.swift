import XCTest
@testable import EncoreCore

final class BackupTests: XCTestCase {
    private func entry(_ text: String, id: UUID = UUID()) -> Backup.Entry {
        let payload = ClipPayload.text(text)
        return .init(clip: .init(id: id, fingerprint: payload.fingerprint, kind: .text, text: text, byteCount: payload.byteCount), payload: payload)
    }

    func testRestoreDeduplicatesByContentMergesPinsAndHandlesIDCollision() throws {
        let id = UUID()
        var original = Library()
        original.clips = [entry("existing", id: id).clip]
        let board = ClipCollection(name: "Work", colorIndex: -99)
        var duplicate = entry("existing")
        duplicate.clip.favorite = true
        duplicate.clip.collectionIDs = [board.id]
        let backup = Backup(collections: [board], entries: [duplicate, entry("new", id: id), entry("new")])
        let result = try backup.merged(into: original, budgetBytes: 1000)
        XCTAssertEqual(result.library.clips.count, 2)
        XCTAssertEqual(result.payloads.count, 1)
        XCTAssertNotEqual(result.payloads[0].0, id)
        XCTAssertEqual(result.library.collections[0].colorIndex, 0)
        let existing = try XCTUnwrap(result.library.clips.first { $0.id == id })
        XCTAssertTrue(existing.favorite)
        XCTAssertEqual(existing.collectionIDs, [board.id])
    }

    func testRestoreRejectsOverBudgetAndInvalidVersionsBeforeChangingAnything() throws {
        let original = Library()
        let backup = Backup(collections: [], entries: [entry("too much")])
        XCTAssertThrowsError(try backup.merged(into: original, budgetBytes: 1))
        XCTAssertTrue(original.clips.isEmpty)
        XCTAssertThrowsError(try Backup(version: 2, collections: [], entries: []).merged(into: original, budgetBytes: 1000))
    }

    func testRestoreDoesNotTrustArchivedHashOrByteCountOrDanglingCollections() throws {
        var imported = entry("actual payload")
        imported.clip.fingerprint = "forged"
        imported.clip.byteCount = -1000
        imported.clip.collectionIDs = [UUID()]
        let result = try Backup(collections: [], entries: [imported]).merged(into: Library(), budgetBytes: 1000)
        XCTAssertEqual(result.library.clips[0].fingerprint, imported.payload.fingerprint)
        XCTAssertEqual(result.library.clips[0].byteCount, imported.payload.byteCount)
        XCTAssertTrue(result.library.clips[0].collectionIDs.isEmpty)
    }
}
