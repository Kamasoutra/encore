import XCTest
import AppKit
import EncoreCore
@testable import Encore

final class ClearedCopyTests: XCTestCase {
    @MainActor private func withModel(_ action: (AppModel, NSPasteboard) throws -> Void) throws {
        let pasteboard = NSPasteboard(name: .init("Encore-Cleared-Test-\(UUID())"))
        let model = AppModel(demo: true, pasteboard: pasteboard)
        defer { model.storage?.flush(); if let root = model.storage?.root { try? FileManager.default.removeItem(at: root) }; pasteboard.releaseGlobally() }
        model.library = Library(); model.preferences.retentionDays = 0
        model.clipboard = ClipboardService(model: model, pasteboard: pasteboard, initialOrigin: .init(bundleID: "org.mozilla.firefox", name: "Firefox"))
        try action(model, pasteboard)
    }

    private func copy(_ text: String, to pasteboard: NSPasteboard) { pasteboard.clearContents(); pasteboard.setString(text, forType: .string) }

    @MainActor func testACopyClearedByItsAppLeavesTheHistory() throws {
        try withModel { model, pb in
            copy("hunter2 is my password", to: pb); model.clipboard.poll()
            XCTAssertEqual(model.library.clips.count, 1)
            pb.clearContents(); model.clipboard.poll()
            XCTAssertTrue(model.library.clips.isEmpty)
            copy("k9#Lm2!qZx", to: pb); model.clipboard.poll()
            copy("\u{0}", to: pb); model.clipboard.poll()
            XCTAssertTrue(model.library.clips.isEmpty, "Some apps clear the clipboard with an invisible character")
        }
    }

    @MainActor func testOnlyTheLastCopyIsForgottenAndProtectedOnesStay() throws {
        try withModel { model, pb in
            copy("First", to: pb); model.clipboard.poll()
            copy("Second", to: pb); model.clipboard.poll()
            pb.clearContents(); model.clipboard.poll()
            XCTAssertEqual(model.library.clips.map(\.text), ["First"])
            copy("Keep me", to: pb); model.clipboard.poll()
            model.library.clips[0].favorite = true
            pb.clearContents(); model.clipboard.poll()
            XCTAssertEqual(Set(model.library.clips.map(\.text)), ["First", "Keep me"])
            model.preferences.forgetClearedCopies = false
            copy("Third", to: pb); model.clipboard.poll()
            pb.clearContents(); model.clipboard.poll()
            XCTAssertTrue(model.library.clips.contains { $0.text == "Third" })
        }
    }

    @MainActor func testDetectedSecretsAreMaskedButPasteTheRealValue() throws {
        try withModel { model, pb in
            copy("ghp_aB3dE5fG7hJ9kL1mN3pQ5rS7tU9vW1xY3zA5", to: pb); model.clipboard.poll()
            XCTAssertNil(model.library.clips.first?.secret, "Detection is off by default")
            model.library = Library()
            model.preferences.detectSecrets = true; model.preferences.secretPreview = 4
            copy("ghp_aB3dE5fG7hJ9kL1mN3pQ5rS7tU9vW1xY3zA5x", to: pb); model.clipboard.poll()
            let clip = try XCTUnwrap(model.library.clips.first)
            XCTAssertEqual(clip.secret, .apiKey)
            XCTAssertEqual(clip.text, "ghp_••••••••")
            let payload = try XCTUnwrap(model.storage?.payload(clip.id))
            XCTAssertEqual(payload.items.first?.representations["public.utf8-plain-text"].flatMap { String(data: $0, encoding: .utf8) }, "ghp_aB3dE5fG7hJ9kL1mN3pQ5rS7tU9vW1xY3zA5x")
            XCTAssertNotNil(model.retentionDecision(for: clip).expiresAt)
        }
    }
}
