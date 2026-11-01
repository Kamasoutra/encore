import XCTest
import AppKit
import ImageIO
import EncoreCore
@testable import Encore

final class MCPAppTests: XCTestCase {
    @MainActor private func withModel(_ action: (AppModel, NSPasteboard) throws -> Void) throws {
        let pb = NSPasteboard(name: .init("Encore-MCP-Test-\(UUID())"))
        let model = AppModel(demo: true, pasteboard: pb)
        defer { model.storage?.flush(); if let root = model.storage?.root { try? FileManager.default.removeItem(at: root) }; pb.releaseGlobally() }
        model.library = Library(); model.preferences.retentionDays = 0; model.preferences.soundsEnabled = false
        model.preferences.mcpEnabled = true; model.preferences.recognizeImages = false
        try action(model, pb)
    }
    private func decoded(_ result: [String: Any]) throws -> Any {
        let content = try XCTUnwrap(result["content"] as? [[String: Any]])
        let text = try XCTUnwrap(content.first?["text"] as? String)
        return try JSONSerialization.jsonObject(with: Data(text.utf8))
    }
    @MainActor private func call(_ model: AppModel, _ name: String, _ args: [String: Any] = [:]) throws -> Any { try decoded(model.mcpCall(name, arguments: args, client: "Test client")) }

    @MainActor func testSecretsHiddenWithoutDetectionAndClearOnlyWhenAllowed() async throws {
        try withModel { model, _ in
            XCTAssertFalse(model.preferences.detectSecrets)
            let secret = "sk-" + String(repeating: "a", count: 30)
            model.addText("ordinary text"); model.addText(secret)
            let unmarked = try XCTUnwrap(model.library.clips.first)
            let payload = ClipPayload.text("k9#Lm2!qZxP4")
            var marked = Clip(fingerprint: payload.fingerprint, kind: .text, text: "k9••••••••")
            marked.secret = .password; marked.snippet = true
            model.accept(marked, payload: payload)
            XCTAssertEqual((try call(model, "recent_clips") as? [[String: Any]])?.count, 1)
            XCTAssertEqual((try call(model, "search_history", ["query": "sk-"]) as? [[String: Any]])?.count, 0)
            XCTAssertEqual((try call(model, "list_snippets") as? [[String: Any]])?.count, 0)
            for id in [unmarked.id, marked.id] {
                XCTAssertThrowsError(try call(model, "get_clip", ["id": id.uuidString]))
                XCTAssertThrowsError(try call(model, "copy_to_clipboard", ["id": id.uuidString]))
                XCTAssertThrowsError(try call(model, "set_favorite", ["id": id.uuidString, "favorite": true]))
            }
            model.preferences.mcpAllowSecrets = true
            XCTAssertEqual((try call(model, "recent_clips") as? [[String: Any]])?.count, 3)
            XCTAssertEqual((try call(model, "get_clip", ["id": marked.id.uuidString]) as? [String: Any])?["text"] as? String, "k9#Lm2!qZxP4")
            XCTAssertEqual((try call(model, "get_clip", ["id": unmarked.id.uuidString]) as? [String: Any])?["text"] as? String, secret)
            let log = String(data: try Data(contentsOf: XCTUnwrap(model.mcpLogURL)), encoding: .utf8)!
            XCTAssertFalse(log.contains(secret)); XCTAssertFalse(log.contains("k9#Lm2!qZxP4")); XCTAssertFalse(log.contains(unmarked.id.uuidString))
        }
    }

    @MainActor func testSearchSnippetsFavoritesAndClipboard() async throws {
        try withModel { model, pb in
            let added = try XCTUnwrap(try call(model, "add_snippet", ["text": "Hello {{name}} on {{date}}", "name": "Greeting", "language": "swift", "tags": ["Work"]]) as? [String: Any])
            let id = try XCTUnwrap(added["id"] as? String)
            model.addText("Another copy")
            let matches = try call(model, "search_history", ["query": "app:encore type:text tag:work lang:swift date:today after:2020-01-01 before:2100-01-01"]) as? [[String: Any]]
            XCTAssertEqual(matches?.first?["id"] as? String, id)
            XCTAssertTrue((try call(model, "search_history", ["query": "app:safari"]) as? [[String: Any]])!.isEmpty)
            let snippets = try call(model, "list_snippets", ["tag": "work", "language": "swift"]) as? [[String: Any]]
            XCTAssertEqual(snippets?.first?["variables"] as? [String], ["name", "date"])
            XCTAssertEqual(snippets?.first?["language"] as? String, "Swift")
            _ = try call(model, "set_favorite", ["id": id, "favorite": true]); _ = try call(model, "set_favorite", ["id": id, "favorite": true])
            XCTAssertTrue(model.library.clips.first(where: { $0.id.uuidString == id })!.favorite)
            _ = try call(model, "copy_to_clipboard", ["id": id])
            XCTAssertEqual(pb.string(forType: .string), "Hello {{name}} on {{date}}")
            XCTAssertEqual(model.library.clips.first?.id.uuidString, id)
            _ = try call(model, "copy_to_clipboard", ["text": "Literal copy"])
            XCTAssertEqual(pb.string(forType: .string), "Literal copy")
            XCTAssertEqual(model.library.clips.first?.text, "Literal copy")
            _ = try call(model, "set_favorite", ["id": id, "favorite": false])
            XCTAssertFalse(model.library.clips.first(where: { $0.id.uuidString == id })!.favorite)
        }
    }

    @MainActor func testLongTextImageOCRAndFileMetadata() async throws {
        try withModel { model, _ in
            let long = String(repeating: "é🙂", count: 60000)
            model.addText(long)
            let id = try XCTUnwrap(model.library.clips.first?.id.uuidString)
            let first = try XCTUnwrap(try call(model, "get_clip", ["id": id]) as? [String: Any])
            XCTAssertEqual((first["text"] as? String)?.count, 100000); XCTAssertEqual(first["truncated"] as? Bool, true)
            XCTAssertEqual(first["totalCharacters"] as? Int, 120000)
            let second = try call(model, "get_clip", ["id": id, "offset": 100000]) as? [String: Any]
            XCTAssertEqual((second?["text"] as? String)?.count, 20000); XCTAssertEqual(second?["truncated"] as? Bool, false)
            let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2000, pixelsHigh: 1000, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
            let png = bitmap.representation(using: .png, properties: [:])!
            let payload = ClipPayload(items: [.init(["public.png": png])])
            var image = Clip(fingerprint: payload.fingerprint, kind: .image, text: "")
            image.recognizedText = "Synthetic OCR"
            model.accept(image, payload: payload)
            let result = try model.mcpCall("get_clip", arguments: ["id": image.id.uuidString], client: "Test")
            let content = try XCTUnwrap(result["content"] as? [[String: Any]])
            let data = try XCTUnwrap(Data(base64Encoded: content[1]["data"] as! String))
            let source = CGImageSourceCreateWithData(data as CFData, nil)!
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as! [String: Any]
            XCTAssertEqual(properties[kCGImagePropertyPixelWidth as String] as? Int, 1568)
            XCTAssertEqual((try decoded(result) as? [String: Any])?["text"] as? String, "Synthetic OCR")
            let url = model.storage!.root.appendingPathComponent("sample.pdf")
            try Data("DO NOT RETURN FILE CONTENT".utf8).write(to: url)
            let files = ClipPayload(items: [.init(["public.file-url": Data(url.absoluteString.utf8)])])
            let file = Clip(fingerprint: files.fingerprint, kind: .file, text: "", fileNames: ["sample.pdf"])
            model.accept(file, payload: files)
            let metadata = try call(model, "get_clip", ["id": file.id.uuidString]) as! [String: Any]
            XCTAssertEqual((metadata["files"] as? [[String: Any]])?.first?["path"] as? String, url.path)
            XCTAssertEqual((metadata["files"] as? [[String: Any]])?.first?["size"] as? Int, 26)
            XCTAssertFalse(String(describing: metadata).contains("DO NOT RETURN"))
        }
    }

    @MainActor func testDisabledAndInvalidCallsAreLoggedWithoutArgumentsAndLogIsBounded() async throws {
        try withModel { model, _ in
            model.preferences.mcpEnabled = false
            for name in MCPTools.names { XCTAssertThrowsError(try call(model, name)) }
            XCTAssertEqual(model.mcpLog.count, 7)
            model.preferences.mcpEnabled = true
            XCTAssertThrowsError(try call(model, "recent_clips", ["private content": "secret argument"]))
            for _ in 0..<202 { _ = try call(model, "recent_clips") }
            XCTAssertEqual(model.mcpLog.count, 200)
            model.loadMCPLog(); XCTAssertEqual(model.mcpLog.count, 200)
            let text = try String(contentsOf: model.mcpLogURL!)
            XCTAssertFalse(text.contains("secret argument")); XCTAssertFalse(text.contains("private content"))
            model.clearMCPLog(); model.loadMCPLog(); XCTAssertTrue(model.mcpLog.isEmpty)
        }
    }

    func testMCPPreferencesAreOptInAndPersist() throws {
        var preferences = try JSONDecoder().decode(Preferences.self, from: Data("{}".utf8))
        XCTAssertFalse(preferences.mcpEnabled); XCTAssertFalse(preferences.mcpAllowSecrets)
        preferences.mcpEnabled = true; preferences.mcpAllowSecrets = true
        XCTAssertEqual(try JSONDecoder().decode(Preferences.self, from: JSONEncoder().encode(preferences)), preferences)
    }
}
