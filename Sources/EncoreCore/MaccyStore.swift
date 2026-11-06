import Foundation
import SQLite3

/// Reads Maccy's history: a SwiftData store whose tables are ZHISTORYITEM (one per copy) and ZHISTORYITEMCONTENT
/// (one per clipboard type of a copy), checked against Maccy 2.8. Only ever reads a copy of the files, never Maccy's own.
public enum MaccyStore {
    public struct Item: Equatable {
        public var items: [PasteItem]
        public var application: String?
        public var firstCopiedAt: Date
        public var lastCopiedAt: Date
        public var pinned: Bool
    }

    public enum Failure: Error, Equatable { case unreadable, notMaccy }

    /// Where the Mac App Store and the direct download of Maccy both keep it: Maccy is sandboxed.
    public static var defaultURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Containers/org.p0deje.Maccy/Data/Library/Application Support/Maccy/Storage.sqlite")
    }

    /// Types Maccy keeps for itself or that only make sense at copy time, as in its HistoryItem.transientTypes.
    static let transientTypes: Set<String> = [
        "org.p0deje.Maccy.modified", "org.p0deje.Maccy.fromMaccy", "com.apple.linkpresentation.metadata",
        "com.apple.WebKit.custom-pasteboard-data", "org.nspasteboard.source", "org.chromium.web-custom-data",
        "org.chromium.source-url", "org.chromium.internal.source-rfh-token", "com.apple.notes.richtext",
    ]

    /// Every copy, oldest first. The store is copied with its write-ahead log first, so that the latest copies are in it
    /// and Maccy, even running, is left alone.
    public static func read(_ url: URL) throws -> [Item] {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("encore-maccy-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let copy = folder.appendingPathComponent("Storage.sqlite")
        do { try FileManager.default.copyItem(at: url, to: copy) } catch { throw Failure.unreadable }
        for suffix in ["-wal", "-shm"] {
            let side = URL(fileURLWithPath: url.path + suffix)
            if FileManager.default.fileExists(atPath: side.path) { try? FileManager.default.copyItem(at: side, to: URL(fileURLWithPath: copy.path + suffix)) }
        }
        var db: OpaquePointer?
        guard sqlite3_open_v2(copy.path, &db, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK, let db else { sqlite3_close(db); throw Failure.unreadable }
        defer { sqlite3_close(db) }

        var items: [Int64: Item] = [:]
        try query(db, "SELECT Z_PK, ZAPPLICATION, ZFIRSTCOPIEDAT, ZLASTCOPIEDAT, ZPIN FROM ZHISTORYITEM") { row in
            let first = Date(timeIntervalSinceReferenceDate: sqlite3_column_double(row, 2))
            let last = sqlite3_column_type(row, 3) == SQLITE_NULL ? first : Date(timeIntervalSinceReferenceDate: sqlite3_column_double(row, 3))
            items[sqlite3_column_int64(row, 0)] = Item(items: [], application: text(row, 1), firstCopiedAt: first, lastCopiedAt: last, pinned: text(row, 4) != nil)
        }
        // A copy of several files holds the same type once per file: each repeat starts a new clipboard item.
        try query(db, "SELECT ZITEM, ZTYPE, ZVALUE FROM ZHISTORYITEMCONTENT ORDER BY ZITEM, Z_PK") { row in
            let id = sqlite3_column_int64(row, 0)
            guard items[id] != nil, let type = text(row, 1), !transientTypes.contains(type), let bytes = sqlite3_column_blob(row, 2) else { return }
            let data = Data(bytes: bytes, count: Int(sqlite3_column_bytes(row, 2)))
            if let last = items[id]!.items.last, last.representations[type] == nil {
                items[id]!.items[items[id]!.items.count - 1].representations[type] = data
            } else {
                items[id]!.items.append(PasteItem([type: data]))
            }
        }
        return items.values.filter { !$0.items.isEmpty }.sorted { $0.lastCopiedAt < $1.lastCopiedAt }
    }

    private static func text(_ row: OpaquePointer, _ column: Int32) -> String? {
        sqlite3_column_text(row, column).map { String(cString: $0) }
    }

    private static func query(_ db: OpaquePointer, _ sql: String, _ each: (OpaquePointer) -> Void) throws {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else { sqlite3_finalize(statement); throw Failure.notMaccy }
        defer { sqlite3_finalize(statement) }
        while sqlite3_step(statement) == SQLITE_ROW { each(statement) }
    }
}
