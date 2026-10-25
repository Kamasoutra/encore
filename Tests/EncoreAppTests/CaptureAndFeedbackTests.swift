import XCTest
import AppKit
import EncoreCore
@testable import Encore

final class CaptureAndFeedbackTests: XCTestCase {
    @MainActor private func withModel(_ action: (AppModel, NSPasteboard, URL) throws -> Void) throws {
        let pb = NSPasteboard(name: .init("Encore-Screenshot-Test-\(UUID())"))
        let model = AppModel(demo: true, pasteboard: pb)
        let root = try XCTUnwrap(model.storage?.root)
        defer { model.storage?.flush(); try? FileManager.default.removeItem(at: root); pb.releaseGlobally() }
        model.library = Library(); model.preferences.recognizeImages = false; model.preferences.retentionDays = 0
        try action(model, pb, root)
    }

    @MainActor func testScreenshotImportPreservesDateAndDoesNotReplaceClipboard() async throws {
        try withModel { model, pb, root in
            pb.clearContents(); pb.setString("Keep my clipboard", forType: .string)
            let count = pb.changeCount
            let png = try XCTUnwrap(try DemoFixtures.create(in: root.appendingPathComponent("Fixture")).first)
            let data = try Data(contentsOf: png)
            let captured = Date().addingTimeInterval(-5)
            model.preferences.importScreenshots = true
            model.preferences.copyScreenshotsToClipboard = false
            ScreenshotImporter(model: model).importImage(data, url: png, capturedAt: captured)
            let clip = try XCTUnwrap(model.library.clips.first)
            XCTAssertEqual(clip.kind, .image); XCTAssertEqual(clip.sourceBundle, "com.apple.screencaptureui")
            XCTAssertEqual(clip.firstCopyDate, captured); XCTAssertEqual(clip.copiedAt, captured)
            XCTAssertEqual(pb.changeCount, count); XCTAssertEqual(pb.string(forType: .string), "Keep my clipboard")
        }
    }

    @MainActor func testScreenshotImportHonorsOptInPauseAndExclusionAndRejectsInvalidData() async throws {
        try withModel { model, _, root in
            let png = try XCTUnwrap(try DemoFixtures.create(in: root.appendingPathComponent("Fixture")).first)
            let data = try Data(contentsOf: png)
            let importer = ScreenshotImporter(model: model)
            importer.importImage(data, url: png, capturedAt: Date())
            XCTAssertTrue(model.library.clips.isEmpty)
            model.preferences.importScreenshots = true; model.preferences.captureEnabled = false
            importer.importImage(data, url: png, capturedAt: Date()); XCTAssertTrue(model.library.clips.isEmpty)
            model.preferences.captureEnabled = true; model.preferences.excludedBundleIDs.append("com.apple.screencaptureui")
            importer.importImage(data, url: png, capturedAt: Date()); XCTAssertTrue(model.library.clips.isEmpty)
            model.preferences.excludedBundleIDs = []
            importer.importImage(Data("not an image".utf8), url: png, capturedAt: Date()); XCTAssertTrue(model.library.clips.isEmpty)
        }
    }

    @MainActor func testReferencedMultiGigabyteFileUsesMetadataWithoutCopyingItsContents() async throws {
        try withModel { model, pb, root in
            let file = root.appendingPathComponent("large-file.bin")
            FileManager.default.createFile(atPath: file.path, contents: nil)
            let handle = try FileHandle(forWritingTo: file)
            try handle.truncate(atOffset: 3_000_000_000); try handle.close()
            let item = NSPasteboardItem(); item.setString(file.absoluteString, forType: .fileURL)
            pb.clearContents(); pb.writeObjects([item])
            let capture = try XCTUnwrap(PasteboardCapture.read(pb, sourceName: "Finder", sourceBundle: "com.apple.finder"))
            XCTAssertEqual(capture.clip.referencedFileBytes, 3_000_000_000)
            XCTAssertLessThan(capture.payload.byteCount, 1000)
            model.accept(capture.clip, payload: capture.payload)
            model.preferences.retentionRules = RetentionRule.examples
            model.prune(now: capture.clip.copiedAt.addingTimeInterval(3600))
            XCTAssertTrue(model.library.clips.isEmpty)
            XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
            XCTAssertEqual(try file.resourceValues(forKeys: [.fileSizeKey]).fileSize, 3_000_000_000)
        }
    }

    @MainActor func testAllBundledSoundVariantsExistWithoutPlayingAudio() async throws {
        for theme in SoundTheme.allCases where theme != .custom {
            for action in [FeedbackSounds.Action.capture, .paste] {
                let url = try XCTUnwrap(FeedbackSounds.bundledURL(action, theme: theme))
                let sound = try XCTUnwrap(NSSound(contentsOf: url, byReference: false))
                XCTAssertGreaterThan(sound.duration, 0.005)
                XCTAssertLessThan(sound.duration, 0.4)
            }
        }
    }

    @MainActor func testMissingFixedDisplayFallsBackToPrimaryAndEmptyInventoryIsSafe() async throws {
        let screens = NSScreen.screens
        guard let first = screens.first else { throw XCTSkip("No display attached to this test runner") }
        let primary = ScreenPlacement.screen(target: "primary", screens: screens, pointer: .zero, current: nil)
        XCTAssertEqual(ScreenPlacement.screen(target: "not-connected", screens: screens, pointer: .zero, current: nil), primary)
        XCTAssertEqual(ScreenPlacement.screen(target: "active", screens: screens, pointer: .zero, current: first), first)
        XCTAssertNil(ScreenPlacement.screen(target: "primary", screens: [], pointer: .zero, current: nil))
        XCTAssertNotNil(ScreenPlacement.identifier(first))
    }
    @MainActor func testRemainingRetentionUsesTheDeadlineAndPinsStayForever() async throws {
        try withModel { model, _, _ in
            let previous = Localization.language
            defer { Localization.language = previous }
            Localization.language = "en"
            let copied = Date()
            var clip = Clip(kind: .file, text: "", copiedAt: copied, referencedFileBytes: 3_000_000_000)
            clip.firstCopiedAt = copied.addingTimeInterval(-86400)
            model.preferences.retentionRules = RetentionRule.examples
            model.displayTime = copied.addingTimeInterval(3590)
            XCTAssertEqual(model.remainingRetention(for: clip), "Expires in under 1 min")
            model.displayTime = copied.addingTimeInterval(3600)
            XCTAssertEqual(model.remainingRetention(for: clip), "Expiring now")
            clip.favorite = true
            XCTAssertEqual(model.remainingRetention(for: clip), "Forever")
        }
    }

}
