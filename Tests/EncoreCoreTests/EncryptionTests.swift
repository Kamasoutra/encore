import XCTest
import CryptoKit
@testable import EncoreCore

final class EncryptionTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("Encore-Encryption-\(UUID())")
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: directory) }

    private func files() throws -> [URL] {
        let items = try FileManager.default.contentsOfDirectory(at: directory.appendingPathComponent("Items"), includingPropertiesForKeys: nil)
        return items + [directory.appendingPathComponent("Library.json")]
    }

    private func change(_ store: Storage, to key: SymmetricKey?, _ library: Library) throws {
        let done = expectation(description: "converted")
        var failure: Error?
        store.changeKey(to: key, library: library) { error in failure = error; done.fulfill() }
        wait(for: [done], timeout: 10)
        if let failure { throw failure }
    }

    func testAnEncryptedHistoryHasNothingReadableOnDiskAndReadsBackWithItsKey() throws {
        let key = SymmetricKey(size: .bits256)
        let store = try Storage(root: directory, key: key)
        var library = Library()
        let clip = Clip(kind: .text, text: "my bank password is hunter2")
        library.clips = [clip]
        store.save(library, payload: (clip.id, .text(clip.text)))
        store.flush()
        for url in try files() {
            let data = try Data(contentsOf: url)
            XCTAssertNil(data.range(of: Data("hunter2".utf8)), url.lastPathComponent)
            XCTAssertNotEqual(data.first, UInt8(ascii: "{"), url.lastPathComponent)
        }
        let reopened = try Storage(root: directory, key: key)
        XCTAssertEqual(try reopened.load().clips.map(\.text), [clip.text])
        XCTAssertNotNil(reopened.payload(clip.id))
        XCTAssertThrowsError(try Storage(root: directory).load()) { error in
            XCTAssertTrue(error is Storage.StorageError, "Without the key, encore says so instead of losing the history")
        }
        XCTAssertThrowsError(try Storage(root: directory, key: SymmetricKey(size: .bits256)).load(), "Another key reads nothing")
    }

    func testTurningEncryptionOnAndOffConvertsEveryFileBothWays() throws {
        let store = try Storage(root: directory)
        var library = Library()
        let clips = (0..<5).map { Clip(kind: .text, text: "secret \($0)") }
        library.clips = clips
        store.save(library, payloads: clips.map { ($0.id, .text($0.text)) })
        store.flush()
        let key = SymmetricKey(size: .bits256)
        try change(store, to: key, library)
        XCTAssertTrue(store.isEncrypted)
        for url in try files() { XCTAssertNil(try Data(contentsOf: url).range(of: Data("secret".utf8)), url.lastPathComponent) }
        XCTAssertEqual(try Storage(root: directory, key: key).load().clips.count, 5)
        try change(store, to: nil, library)
        XCTAssertFalse(store.isEncrypted)
        let plain = try Storage(root: directory)
        XCTAssertEqual(try plain.load().clips.count, 5)
        XCTAssertNotNil(plain.payload(clips[3].id))
    }

    func testAHistoryHalfConvertedStaysReadable() throws {
        let plainStore = try Storage(root: directory)
        var library = Library()
        let first = Clip(kind: .text, text: "plain one")
        library.clips = [first]
        plainStore.save(library, payload: (first.id, .text(first.text)))
        plainStore.flush()
        let key = SymmetricKey(size: .bits256)
        let sealedStore = try Storage(root: directory, key: key)
        let second = Clip(kind: .text, text: "sealed one")
        library.clips.append(second)
        sealedStore.save(library, payload: (second.id, .text(second.text)))
        sealedStore.flush()
        let reader = try Storage(root: directory, key: key)
        XCTAssertEqual(try reader.load().clips.count, 2)
        XCTAssertNotNil(reader.payload(first.id), "A content written before encryption is still read")
        XCTAssertNotNil(reader.payload(second.id))
    }
}
