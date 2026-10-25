import XCTest
import AppKit
import EncoreCore
@testable import Encore

final class SourceAndPreferencesTests: XCTestCase {
    @MainActor private func withModel(_ action: (AppModel, NSPasteboard) throws -> Void) throws {
        let pasteboard = NSPasteboard(name: .init("Encore-Origin-Test-\(UUID())"))
        let model = AppModel(demo: true, pasteboard: pasteboard)
        defer { model.storage?.flush(); if let root = model.storage?.root { try? FileManager.default.removeItem(at: root) }; pasteboard.releaseGlobally() }
        model.library = Library(); model.preferences.retentionDays = 0
        model.clipboard = ClipboardService(model: model, pasteboard: pasteboard, initialOrigin: .init(bundleID: "org.mozilla.firefox", name: "Firefox"))
        try action(model, pasteboard)
    }

    @MainActor func testPendingFirefoxCopyIsDrainedBeforeSwitchingToTerminal() async throws {
        try withModel { model, pb in
            pb.clearContents()
            pb.setString("Copied before switching", forType: .string)
            model.clipboard.noteActivation(.init(bundleID: "com.cmuxterm.app", name: "cmux"))
            XCTAssertEqual(model.library.clips.first?.sourceBundle, "org.mozilla.firefox")
            pb.clearContents(); pb.setString("Copied in terminal", forType: .string)
            model.clipboard.poll()
            XCTAssertEqual(model.library.clips.first?.sourceBundle, "com.cmuxterm.app")
        }
    }

    @MainActor func testDeclaredSourceWinsOverTheTrackedAppAndHonorsExclusions() async throws {
        try withModel { model, pb in
            model.clipboard.noteActivation(.init(bundleID: "com.cmuxterm.app", name: "cmux"))
            pb.clearContents()
            pb.setString("Original content", forType: .string)
            pb.setString("org.mozilla.firefox", forType: .init("org.nspasteboard.source"))
            model.clipboard.poll()
            XCTAssertEqual(model.library.clips.first?.sourceBundle, "org.mozilla.firefox")
            model.preferences.excludedBundleIDs.append("org.mozilla.firefox")
            pb.clearContents(); pb.setString("Excluded content", forType: .string)
            pb.setString("org.mozilla.firefox", forType: .init("org.nspasteboard.source"))
            model.clipboard.poll()
            XCTAssertEqual(model.library.clips.count, 1)
        }
    }

    @MainActor func testExplicitUnknownSourceDoesNotInventAnAppAndCopyRestoresOrigin() async throws {
        try withModel { model, pb in
            pb.clearContents()
            pb.setString("Unknown content", forType: .string)
            pb.setString("", forType: .init("org.nspasteboard.source"))
            model.clipboard.poll()
            XCTAssertEqual(model.library.clips.first?.sourceBundle, "")
            model.clipboard.write(.text("Restored"), sourceBundle: "org.mozilla.firefox")
            XCTAssertEqual(pb.string(forType: .init("org.nspasteboard.source")), "org.mozilla.firefox")
            XCTAssertEqual(ClipPayload.text("Restored").fingerprint, ClipPayload(items: [.init(["public.utf8-plain-text": Data("Restored".utf8), "org.nspasteboard.source": Data("org.mozilla.firefox".utf8)])]).fingerprint)
        }
    }

    func testPreferencesMigrateWithoutLosingOldUserSettings() throws {
        let old = Data(#"{"retentionDays":90,"compact":true,"appearance":"dark","excludedBundleIDs":["test.private"]}"#.utf8)
        let preferences = try JSONDecoder().decode(Preferences.self, from: old)
        XCTAssertEqual(preferences.retentionDays, 90); XCTAssertTrue(preferences.compact)
        XCTAssertEqual(preferences.appearance, "dark"); XCTAssertEqual(preferences.excludedBundleIDs, ["test.private"])
        XCTAssertTrue(preferences.retentionRules.isEmpty); XCTAssertFalse(preferences.importScreenshots)
        XCTAssertEqual(preferences.cardScale, 1)
    }

    func testRulesAndScreenshotPreferencesSurviveRoundTrip() throws {
        var original = Preferences(); original.retentionRules = RetentionRule.examples
        original.importScreenshots = true; original.screenshotFolder = "/tmp/Screenshots"; original.cardScale = 1.25
        XCTAssertEqual(try JSONDecoder().decode(Preferences.self, from: JSONEncoder().encode(original)), original)
    }

    @MainActor func testRetentionPreviewDoesNotDeleteAndApplyRemovesExpiredItems() async throws {
        try withModel { model, _ in
            let payload = ClipPayload.text("Old")
            let clip = Clip(fingerprint: payload.fingerprint, kind: .text, text: "Old", copiedAt: Date().addingTimeInterval(-7200), byteCount: payload.byteCount)
            model.accept(clip, payload: payload)
            let rules = [RetentionRule(duration: .init(1, .hours))]
            XCTAssertEqual(model.retentionRemovalCount(rules: rules, fallbackDays: 0), 1)
            XCTAssertEqual(model.library.clips.count, 1)
            model.applyRetention(rules: rules, fallbackDays: 0)
            XCTAssertTrue(model.library.clips.isEmpty)
            XCTAssertNil(model.storage?.payload(clip.id))
        }
    }
}
