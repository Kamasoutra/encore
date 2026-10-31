import XCTest
@testable import EncoreCore

final class StorageTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("Encore-test-\(UUID())")
    }

    override func tearDownWithError() throws {
        if FileManager.default.fileExists(atPath: directory.path) { try FileManager.default.removeItem(at: directory) }
    }

    func testPersistenceSurvivesReopenWithAllRepresentations() throws {
        let store = try Storage(root: directory)
        var library = try store.load()
        let payload = ClipPayload(items: [.init(["public.utf8-plain-text": Data("Bonjour".utf8), "public.rtf": Data([0, 1, 255])])])
        let clip = Clip(fingerprint: payload.fingerprint, kind: .text, text: "Bonjour", favorite: true, byteCount: payload.byteCount)
        library.upsert(clip)
        store.save(library, payload: (clip.id, payload))
        store.flush()
        let reopened = try Storage(root: directory)
        XCTAssertEqual(try reopened.load().clips, [clip])
        XCTAssertEqual(reopened.payload(clip.id), payload)
    }

    func testMemoryOnlyKeepsCopiesOffTheDiskButFavorites() throws {
        let store = try Storage(root: directory)
        func clip(_ text: String, favorite: Bool = false) -> (Clip, ClipPayload) {
            let payload = ClipPayload.text(text)
            return (Clip(fingerprint: payload.fingerprint, kind: .text, text: text, favorite: favorite, byteCount: payload.byteCount), payload)
        }
        let (before, beforePayload) = clip("copied before")
        var library = Library(); library.upsert(before)
        store.save(library, payload: (before.id, beforePayload)); store.flush()
        // Damaged libraries kept for recovery: a readable one keeps only kept items, an unreadable one goes.
        let recovery = directory.appendingPathComponent("Recovery")
        try FileManager.default.createDirectory(at: recovery, withIntermediateDirectories: true)
        try JSONEncoder().encode(library).write(to: recovery.appendingPathComponent("Library-damaged-a.json"))
        try Data("not json".utf8).write(to: recovery.appendingPathComponent("Library-damaged-b.json"))
        store.setEphemeral(true, library: library); store.flush()
        XCTAssertEqual(try JSONDecoder().decode(Library.self, from: Data(contentsOf: recovery.appendingPathComponent("Library-damaged-a.json"))).clips, [])
        XCTAssertFalse(FileManager.default.fileExists(atPath: recovery.appendingPathComponent("Library-damaged-b.json").path))
        let itemFile = { (id: UUID) in self.directory.appendingPathComponent("Items/\(id.uuidString).json") }
        let onDisk = { try Storage(root: self.directory).load().clips.map(\.text) }
        XCTAssertFalse(FileManager.default.fileExists(atPath: itemFile(before.id).path), "An earlier copy leaves the disk")
        XCTAssertEqual(store.payload(before.id), beforePayload, "and still pastes from memory")
        XCTAssertEqual(try onDisk(), [], "Its text is not in the library file either")

        let (secret, secretPayload) = clip("new copy")
        let (kept, keptPayload) = clip("a favorite", favorite: true)
        library.upsert(secret); library.upsert(kept)
        store.save(library, payloads: [(secret.id, secretPayload), (kept.id, keptPayload)]); store.flush()
        XCTAssertFalse(FileManager.default.fileExists(atPath: itemFile(secret.id).path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: itemFile(kept.id).path))
        XCTAssertEqual(try onDisk(), ["a favorite"])

        // Favorited later, a copy goes to disk; no longer a favorite, it leaves it again.
        let index = try XCTUnwrap(library.clips.firstIndex { $0.id == secret.id })
        library.clips[index].favorite = true
        store.save(library); store.flush()
        XCTAssertTrue(FileManager.default.fileExists(atPath: itemFile(secret.id).path))
        library.clips[index].favorite = false
        store.save(library); store.flush()
        XCTAssertFalse(FileManager.default.fileExists(atPath: itemFile(secret.id).path))
        XCTAssertEqual(store.payload(secret.id), secretPayload)

        store.setEphemeral(false, library: library); store.flush()
        XCTAssertEqual(Set(try onDisk()), ["copied before", "new copy", "a favorite"], "Turned off, everything is written again")
        XCTAssertEqual(try Storage(root: directory).payload(secret.id), secretPayload)
    }

    func testSerialSavesPreserveLatestStateAndDeletionRemovesPayload() throws {
        let store = try Storage(root: directory)
        var library = Library()
        let clip = Clip(kind: .text, text: "delete me")
        library.clips = [clip]
        store.save(library, payload: (clip.id, .text(clip.text)))
        library.clips = []
        store.save(library, deleting: [clip.id])
        store.flush()
        XCTAssertTrue(try store.load().clips.isEmpty)
        XCTAssertNil(store.payload(clip.id))
    }

    func testSavesWithinTheDelayMakeOneWriteAndAContentWrittenAgainSurvivesItsDeletion() throws {
        let store = try Storage(root: directory)
        store.writeDelay = 30
        var library = Library()
        let clip = Clip(kind: .text, text: "keep me")
        library.clips = [clip]
        store.save(library, payload: (clip.id, .text(clip.text)))
        library.clips = []
        store.save(library, deleting: [clip.id])
        XCTAssertNil(store.payload(clip.id), "A pending deletion already reads as gone")
        library.clips = [clip]
        store.save(library, payload: (clip.id, .text(clip.text)))
        // Nothing written yet: the delay is not over.
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("Library.json").path))
        store.flush()
        XCTAssertEqual(try store.load().clips.map(\.id), [clip.id])
        XCTAssertEqual(store.payload(clip.id)?.items.count, 1, "Undoing a deletion keeps the content")
    }

    func testLibraryAndPayloadAreOwnerOnly() throws {
        let store = try Storage(root: directory)
        let clip = Clip(kind: .text, text: "private")
        var library = Library()
        library.clips = [clip]
        store.save(library, payload: (clip.id, .text(clip.text)))
        store.flush()
        let root = try FileManager.default.attributesOfItem(atPath: directory.path)
        let metadata = try FileManager.default.attributesOfItem(atPath: directory.appendingPathComponent("Library.json").path)
        let payload = try FileManager.default.attributesOfItem(atPath: directory.appendingPathComponent("Items/\(clip.id.uuidString).json").path)
        XCTAssertEqual((root[.posixPermissions] as? NSNumber)?.intValue, 0o700)
        XCTAssertEqual((metadata[.posixPermissions] as? NSNumber)?.intValue, 0o600)
        XCTAssertEqual((payload[.posixPermissions] as? NSNumber)?.intValue, 0o600)
    }

    func testCorruptMetadataThrowsInsteadOfReturningAnEmptyLibrary() throws {
        let store = try Storage(root: directory)
        let data = Data("not JSON".utf8)
        try data.write(to: directory.appendingPathComponent("Library.json"))
        XCTAssertThrowsError(try store.load())
        XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent("Library.json")), data)
    }

    func testWriteFailurePreventsLaterQueuedSnapshotsFromCommitting() throws {
        let store = try Storage(root: directory)
        try FileManager.default.createDirectory(at: directory.appendingPathComponent("Library.json"), withIntermediateDirectories: true)
        let first = Clip(kind: .text, text: "first")
        let second = Clip(kind: .text, text: "second")
        var library = Library()
        library.clips = [first]
        store.save(library, payload: (first.id, .text(first.text)))
        library.clips.append(second)
        store.save(library, payload: (second.id, .text(second.text)))
        store.flush()
        // Both saves fall in one write, which fails: nothing saved after that commits.
        let third = Clip(kind: .text, text: "third")
        library.clips.append(third)
        store.save(library, payload: (third.id, .text(third.text)))
        store.flush()
        XCTAssertNil(store.payload(third.id))
        var isDirectory: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent("Library.json").path, isDirectory: &isDirectory))
        XCTAssertTrue(isDirectory.boolValue)
    }
}
