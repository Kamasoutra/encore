import XCTest
import AppKit
import EncoreCore
@testable import Encore

/// Timings with a large history. Run on demand: `ENCORE_BENCH=10000 swift test --filter ScaleBenchmark`.
final class ScaleBenchmarkTests: XCTestCase {
    private var size: Int { Int(ProcessInfo.processInfo.environment["ENCORE_BENCH"] ?? "") ?? 0 }

    static func history(_ count: Int, now: Date = Date()) -> [Clip] {
        let samples = ["Les bonnes idées reviennent encore.", "https://developer.apple.com/design/human-interface-guidelines", "#A78BFA",
                       "struct GoodIdea {\n    let captured = true\n}", "Bonjour Sam,\n\nMerci pour ton retour !", "jp@example.com"]
        let apps = [("Notes", "com.apple.Notes"), ("Safari", "com.apple.Safari"), ("Figma", "com.figma.Desktop"), ("Xcode", "com.apple.dt.Xcode"), ("Mail", "com.apple.mail")]
        return (0..<count).map { index in
            let text = samples[index % samples.count] + " \(index)"
            let app = apps[index % apps.count]
            var clip = Clip(fingerprint: "bench-\(index)", kind: .detect(text: text), text: text, sourceName: app.0, sourceBundle: app.1,
                            copiedAt: now.addingTimeInterval(-Double(index) * 97), byteCount: text.utf8.count)
            clip.favorite = index % 50 == 0
            if index % 80 == 0 { clip.snippet = true; clip.name = "Snippet \(index)"; clip.tags = ["work"]; clip.language = index % 160 == 0 ? "swift" : nil }
            return clip
        }
    }

    private func time(_ label: String, repeats: Int = 5, _ body: () -> Void) {
        body()
        let start = Date()
        for _ in 0..<repeats { body() }
        let milliseconds = Date().timeIntervalSince(start) / Double(repeats) * 1000
        print(String(format: "BENCH %-44@ %8.2f ms", label as NSString, milliseconds))
    }

    @MainActor func testTimingsWithALargeHistory() throws {
        try XCTSkipIf(size == 0, "Set ENCORE_BENCH to the number of items")
        let pasteboard = NSPasteboard(name: .init("Encore-Bench-\(UUID())"))
        let model = AppModel(demo: true, pasteboard: pasteboard)
        defer { model.storage?.flush(); if let root = model.storage?.root { try? FileManager.default.removeItem(at: root) }; pasteboard.releaseGlobally() }
        model.preferences.historyLimit = 0; model.preferences.retentionDays = 0
        var library = Library(); library.clips = Self.history(size)
        model.library = library
        print("BENCH items: \(model.library.clips.count)")

        time("filtered, recomputed") { model.library.clips[0].lastUsedAt = Date(); _ = model.filtered }
        time("filtered, cached") { _ = model.filtered }
        time("sections (days), recomputed") { model.library.clips[0].lastUsedAt = Date(); _ = model.sections }
        time("search \"design\"") { model.query = "design"; _ = model.filtered; model.query = "" }
        time("search \"app:safari type:link\"") { model.query = "app:safari type:link"; _ = model.filtered; model.query = "" }
        time("type \"design\" letter by letter (6 keys)") { for count in 1...6 { model.query = String("design".prefix(count)); _ = model.filtered }; model.query = "" }
        time("board favorites") { model.board = "favorites"; _ = model.sections; model.board = "history" }
        time("board snippets") { model.board = "snippets"; _ = model.sections; model.board = "history" }
        time("sources (apps filter)") { _ = model.sources }
        time("move right") { model.move(1) }
        time("shift-select 10, ordered") { model.resetSelection(); for _ in 0..<10 { model.move(1, extend: true) }; _ = model.selectedClips }
        time("⌘A then paste order of one card") { model.selection = Set(model.filtered.map(\.id)); _ = model.pasteOrder(of: model.filtered[5].id) }
        time("⌘A then ⌘D (favorite all)", repeats: 2) { model.selection = Set(model.filtered.map(\.id)); model.toggleFavorite() }
        time("prune") { model.prune() }
        time("expires within a minute (per second)") { _ = model.expiresWithinAMinute }
        time("new copy (accept)") { model.addText("Fresh copy \(UUID())") }
        time("encode Library.json", repeats: 3) { _ = try? JSONEncoder().encode(model.library) }
        if let data = try? JSONEncoder().encode(model.library) { print("BENCH Library.json size: \(data.count / 1024) KiB") }
        if let data = try? JSONEncoder().encode(model.library) {
            time("decode Library.json (launch)", repeats: 3) { _ = try? JSONDecoder().decode(Library.self, from: data) }
        }
    }
}
