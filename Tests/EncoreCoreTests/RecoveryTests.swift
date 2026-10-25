import XCTest
@testable import EncoreCore

final class RecoveryTests: XCTestCase {
    func testCorruptIndexRestoresAValidBackupAndKeepsTheDamagedFile() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Encore-Recovery-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try Storage(root: root)
        var library = Library()
        let clip = Clip(kind: .text, text: "Keep me")
        library.clips = [clip]
        store.save(library, payload: (clip.id, .text(clip.text))); store.flush()
        library.collections = [.init(name: "Work")]
        store.save(library); store.flush()
        let damaged = Data("damaged JSON".utf8)
        try damaged.write(to: root.appendingPathComponent("Library.json"))
        let reopened = try Storage(root: root)
        XCTAssertEqual(try reopened.load().clips, [clip])
        XCTAssertEqual(reopened.payload(clip.id), .text("Keep me"))
        XCTAssertNotNil(reopened.recoveryNotice)
        let saved = try FileManager.default.contentsOfDirectory(at: root.appendingPathComponent("Recovery"), includingPropertiesForKeys: nil)
        XCTAssertEqual(saved.count, 1)
        XCTAssertEqual(try Data(contentsOf: saved[0]), damaged)
        XCTAssertNoThrow(try JSONDecoder().decode(Library.self, from: Data(contentsOf: root.appendingPathComponent("Library.json"))))
    }
}
