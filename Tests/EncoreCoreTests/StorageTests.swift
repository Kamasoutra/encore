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
        XCTAssertNil(store.payload(second.id))
        var isDirectory: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent("Library.json").path, isDirectory: &isDirectory))
        XCTAssertTrue(isDirectory.boolValue)
    }
}
