import XCTest
import AppKit
import SQLite3
import EncoreCore
@testable import Encore

/// A Maccy store with the schema of Maccy 2.8, as read from a real one.
private func makeMaccyStore(_ rows: [(app: String?, first: Double, last: Double, pin: String?, contents: [(String, Data)])]) throws -> URL {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("maccy-test-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let url = folder.appendingPathComponent("Storage.sqlite")
    var db: OpaquePointer?
    XCTAssertEqual(sqlite3_open(url.path, &db), SQLITE_OK)
    defer { sqlite3_close(db) }
    sqlite3_exec(db, """
        PRAGMA journal_mode=WAL;
        CREATE TABLE ZHISTORYITEM ( Z_PK INTEGER PRIMARY KEY, Z_ENT INTEGER, Z_OPT INTEGER, ZNUMBEROFCOPIES INTEGER, ZFIRSTCOPIEDAT TIMESTAMP, ZLASTCOPIEDAT TIMESTAMP, ZAPPLICATION VARCHAR, ZPIN VARCHAR, ZTITLE VARCHAR );
        CREATE TABLE ZHISTORYITEMCONTENT ( Z_PK INTEGER PRIMARY KEY, Z_ENT INTEGER, Z_OPT INTEGER, ZITEM INTEGER, ZTYPE VARCHAR, ZVALUE BLOB );
        """, nil, nil, nil)
    let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
    for (index, row) in rows.enumerated() {
        var item: OpaquePointer?
        sqlite3_prepare_v2(db, "INSERT INTO ZHISTORYITEM (Z_PK, ZNUMBEROFCOPIES, ZFIRSTCOPIEDAT, ZLASTCOPIEDAT, ZAPPLICATION, ZPIN) VALUES (?, 1, ?, ?, ?, ?)", -1, &item, nil)
        sqlite3_bind_int64(item, 1, Int64(index + 1)); sqlite3_bind_double(item, 2, row.first); sqlite3_bind_double(item, 3, row.last)
        if let app = row.app { sqlite3_bind_text(item, 4, app, -1, transient) } else { sqlite3_bind_null(item, 4) }
        if let pin = row.pin { sqlite3_bind_text(item, 5, pin, -1, transient) } else { sqlite3_bind_null(item, 5) }
        XCTAssertEqual(sqlite3_step(item), SQLITE_DONE); sqlite3_finalize(item)
        for (type, data) in row.contents {
            var content: OpaquePointer?
            sqlite3_prepare_v2(db, "INSERT INTO ZHISTORYITEMCONTENT (ZITEM, ZTYPE, ZVALUE) VALUES (?, ?, ?)", -1, &content, nil)
            sqlite3_bind_int64(content, 1, Int64(index + 1)); sqlite3_bind_text(content, 2, type, -1, transient)
            _ = data.withUnsafeBytes { sqlite3_bind_blob(content, 3, $0.baseAddress, Int32(data.count), transient) }
            XCTAssertEqual(sqlite3_step(content), SQLITE_DONE); sqlite3_finalize(content)
        }
    }
    return url
}

private let text = "public.utf8-plain-text"

final class MaccyImportTests: XCTestCase {
    func testTheStoreIsReadOldestFirstWithEachFileAsItsOwnItemAndWithoutMaccysOwnTypes() throws {
        let url = try makeMaccyStore([
            (app: "com.apple.finder", first: 2_000, last: 2_000, pin: nil, contents: [("public.file-url", Data("file:///a.md".utf8)), ("public.file-url", Data("file:///b.md".utf8))]),
            (app: "org.mozilla.firefox", first: 100, last: 1_000, pin: "b", contents: [(text, Data("hello".utf8)), ("org.p0deje.Maccy.fromMaccy", Data())]),
        ])
        let items = try MaccyStore.read(url)
        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(items[0].items, [PasteItem([text: Data("hello".utf8)])])
        XCTAssertTrue(items[0].pinned)
        XCTAssertEqual(items[0].firstCopiedAt, Date(timeIntervalSinceReferenceDate: 100))
        XCTAssertEqual(items[0].lastCopiedAt, Date(timeIntervalSinceReferenceDate: 1_000))
        XCTAssertEqual(items[1].items.count, 2, "two files, two items")
        XCTAssertFalse(items[1].pinned)
        XCTAssertThrowsError(try MaccyStore.read(url.deletingLastPathComponent().appendingPathComponent("missing.sqlite")))
    }

    @MainActor func testImportFollowsTheRulesOfACopyAndMergesWhatEncoreHas() throws {
        let pasteboard = NSPasteboard(name: .init("Encore-Maccy-Test-\(UUID())"))
        let model = AppModel(demo: true, pasteboard: pasteboard)
        defer { model.storage?.flush(); if let root = model.storage?.root { try? FileManager.default.removeItem(at: root) }; pasteboard.releaseGlobally() }
        model.library = Library(); model.preferences.retentionDays = 0
        model.preferences.excludedBundleIDs = ["com.bitwarden.desktop"]
        model.preferences.detectSecrets = true
        model.addText("already here")
        let recent = try XCTUnwrap(model.library.clips.first).copiedAt
        let now = Date().timeIntervalSinceReferenceDate
        let png = try XCTUnwrap(NSImage(size: .init(width: 4, height: 4), flipped: false) { NSColor.red.setFill(); $0.fill(); return true }.tiffRepresentation.flatMap { NSBitmapImageRep(data: $0)?.representation(using: .png, properties: [:]) })
        let url = try makeMaccyStore([
            (app: "org.mozilla.firefox", first: now - 500, last: now - 400, pin: "b", contents: [(text, Data("from Maccy".utf8))]),
            (app: "com.bitwarden.desktop", first: now - 300, last: now - 300, pin: nil, contents: [(text, Data("excluded app".utf8))]),
            (app: "org.mozilla.firefox", first: now - 5, last: now - 5, pin: nil, contents: [(text, Data("sk-proj-Ab3dEf6hIj9kLm2nOp5qRs8tUv1wXy4zAb7cDe0fGh3".utf8))]),
            (app: "com.apple.Preview", first: now - 100, last: now - 100, pin: nil, contents: [("public.png", png)]),
            (app: "org.mozilla.firefox", first: now - 9_000, last: now - 9_000, pin: "c", contents: [(text, Data("already here".utf8))]),
            (app: nil, first: now - 3, last: now - 3, pin: nil, contents: [(text, Data("confidential".utf8)), ("org.nspasteboard.ConcealedType", Data("1".utf8))]),
        ])
        let result = model.mergeMaccy(try MaccyStore.read(url))
        XCTAssertEqual(result.added, 3, "text, secret and image; not the excluded app nor the confidential copy")
        XCTAssertEqual(result.merged, 1)
        let imported = try XCTUnwrap(model.library.clips.first { $0.text == "from Maccy" })
        XCTAssertTrue(imported.favorite)
        XCTAssertEqual(imported.copiedAt.timeIntervalSinceReferenceDate, now - 400, accuracy: 0.01)
        XCTAssertEqual(imported.sourceBundle, "org.mozilla.firefox")
        XCTAssertNotNil(model.library.clips.first { $0.secret != nil }, "secrets are detected as on a real copy")
        XCTAssertFalse(model.library.clips.contains { $0.text.contains("sk-proj") }, "and masked")
        XCTAssertNotNil(model.library.clips.first { $0.kind == .image })
        let existing = try XCTUnwrap(model.library.clips.first { $0.text == "already here" })
        XCTAssertEqual(existing.copiedAt, recent, "keeps encore's more recent date")
        XCTAssertEqual(existing.firstCopyDate.timeIntervalSinceReferenceDate, now - 9_000, accuracy: 0.01)
        XCTAssertTrue(existing.favorite)
        XCTAssertEqual(model.library.clips.map(\.copiedAt), model.library.clips.map(\.copiedAt).sorted(by: >))
        XCTAssertEqual(model.mergeMaccy(try MaccyStore.read(url)).added, 0, "importing twice adds nothing")
    }

    @MainActor func testCopiesOlderThanTheRetentionRulesAreCountedAsExpired() throws {
        let pasteboard = NSPasteboard(name: .init("Encore-Maccy-Test-\(UUID())"))
        let model = AppModel(demo: true, pasteboard: pasteboard)
        defer { model.storage?.flush(); if let root = model.storage?.root { try? FileManager.default.removeItem(at: root) }; pasteboard.releaseGlobally() }
        model.library = Library(); model.preferences.retentionDays = 30
        let now = Date().timeIntervalSinceReferenceDate
        let url = try makeMaccyStore([
            (app: "org.mozilla.firefox", first: now - 40 * 86_400, last: now - 40 * 86_400, pin: nil, contents: [(text, Data("old".utf8))]),
            (app: "org.mozilla.firefox", first: now - 60, last: now - 60, pin: nil, contents: [(text, Data("new".utf8))]),
        ])
        let result = model.mergeMaccy(try MaccyStore.read(url))
        XCTAssertEqual(result.added, 2)
        XCTAssertEqual(result.expired, 1)
        XCTAssertEqual(model.library.clips.map(\.text), ["new"])
    }
}
