import XCTest
import AppKit
import EncoreCore
@testable import Encore

final class ScreenshotClipboardTests: XCTestCase {
    @MainActor private func withModel(_ action: (AppModel, NSPasteboard, Data, URL) throws -> Void) throws {
        let pb = NSPasteboard(name: .init("Encore-Screenshot-Copy-\(UUID())"))
        let model = AppModel(demo: true, pasteboard: pb)
        let root = try XCTUnwrap(model.storage?.root)
        defer { model.storage?.flush(); try? FileManager.default.removeItem(at: root); pb.releaseGlobally() }
        model.library = Library()
        model.preferences.recognizeImages = false
        model.preferences.importScreenshots = true
        model.preferences.copyScreenshotsToClipboard = true
        model.preferences.retentionDays = 0
        let png = try XCTUnwrap(try DemoFixtures.create(in: root.appendingPathComponent("Fixture")).first)
        try action(model, pb, Data(contentsOf: png), png)
    }

    @MainActor func testImportedScreenshotBecomesAPasteableImageWithoutRecapturingIt() async throws {
        try withModel { model, pb, data, url in
            model.clipboard.write(.text("Before"))
            let captured = Date()
            ScreenshotImporter(model: model).importImage(data, url: url, capturedAt: captured)
            XCTAssertEqual(pb.data(forType: .png), data)
            XCTAssertNotNil(NSImage(pasteboard: pb))
            XCTAssertEqual(pb.string(forType: .init("org.nspasteboard.source")), "com.apple.screencaptureui")
            XCTAssertEqual(model.library.clips.count, 1)
            model.clipboard.poll()
            XCTAssertEqual(model.library.clips.count, 1)
            XCTAssertEqual(model.library.clips.first?.copiedAt, captured)
        }
    }

    @MainActor func testNewerCopyWinsWhileScreenshotIsBeingRead() async throws {
        try withModel { model, pb, data, url in
            model.clipboard.write(.text("Before"))
            let revision = model.clipboard.revision
            let captured = Date()
            pb.clearContents(); pb.setString("Copied afterwards", forType: .string)
            ScreenshotImporter(model: model).importImage(data, url: url, capturedAt: captured, clipboardRevision: revision)
            XCTAssertEqual(pb.string(forType: .string), "Copied afterwards")
            XCTAssertTrue(model.library.clips.contains { $0.kind == .image })
        }
    }

    @MainActor func testNewestScreenshotWinsAcrossOverlappingImports() async throws {
        try withModel { model, pb, data, url in
            model.clipboard.write(.text("Before"))
            let revision = model.clipboard.revision
            let captured = Date()
            let importer = ScreenshotImporter(model: model)
            let newer = data + Data([0])
            importer.importImage(data, url: url, capturedAt: captured, clipboardRevision: revision)
            importer.importImage(newer, url: url, capturedAt: captured.addingTimeInterval(1), clipboardRevision: revision)
            XCTAssertEqual(pb.data(forType: .png), newer)
            importer.importImage(data, url: url, capturedAt: captured, clipboardRevision: model.clipboard.revision)
            XCTAssertEqual(pb.data(forType: .png), newer)
        }
    }

    @MainActor func testHistoryBudgetDoesNotPreventCopyingAValidScreenshot() async throws {
        try withModel { model, pb, data, url in
            model.preferences.storageLimitMB = 0
            ScreenshotImporter(model: model).importImage(data, url: url, capturedAt: Date())
            XCTAssertTrue(model.library.clips.isEmpty)
            XCTAssertEqual(pb.data(forType: .png), data)
        }
    }

    @MainActor func testPausedExcludedAndInvalidScreenshotsDoNotTouchClipboard() async throws {
        try withModel { model, pb, data, url in
            model.clipboard.write(.text("Keep this"))
            let revision = pb.changeCount
            let importer = ScreenshotImporter(model: model)
            model.preferences.captureEnabled = false
            importer.importImage(data, url: url, capturedAt: Date())
            model.preferences.captureEnabled = true
            model.preferences.excludedBundleIDs.append("com.apple.screencaptureui")
            importer.importImage(data, url: url, capturedAt: Date())
            model.preferences.excludedBundleIDs = []
            importer.importImage(Data("invalid".utf8), url: url, capturedAt: Date())
            XCTAssertEqual(pb.changeCount, revision)
            XCTAssertEqual(pb.string(forType: .string), "Keep this")
        }
    }

    func testPreferenceMigrationPreservesExistingHistoryOnlyMode() throws {
        let old = Data(#"{"importScreenshots":true}"#.utf8)
        XCTAssertFalse(try JSONDecoder().decode(Preferences.self, from: old).copyScreenshotsToClipboard)
        let previouslyDisabled = Data(#"{"importScreenshots":false}"#.utf8)
        XCTAssertTrue(try JSONDecoder().decode(Preferences.self, from: previouslyDisabled).copyScreenshotsToClipboard)
        var preferences = Preferences()
        preferences.copyScreenshotsToClipboard = false
        XCTAssertFalse(try JSONDecoder().decode(Preferences.self, from: JSONEncoder().encode(preferences)).copyScreenshotsToClipboard)
    }
}
