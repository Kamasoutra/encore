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

    @MainActor func testDraggingFilesCarriesEveryFileAndAMixedSelectionStaysCombined() throws {
        try withModel { model, pb in
            let urls = ["a.png", "b.md"].map { URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent($0) }
            let type = NSPasteboard.PasteboardType.fileURL
            let payload = ClipPayload(items: urls.map { .init([type.rawValue: Data($0.absoluteString.utf8)]) })
            let files = Clip(fingerprint: payload.fingerprint, kind: .file, text: "", sourceName: "Finder", sourceBundle: "com.apple.finder", byteCount: payload.byteCount, fileNames: urls.map(\.lastPathComponent))
            model.accept(files, payload: payload)
            let clip = try XCTUnwrap(model.library.clips.first { $0.kind == .file })

            let items = clipDragItems(model: model, clip: clip)
            XCTAssertEqual(items.compactMap { $0.string(forType: type) }, urls.map(\.absoluteString))
            XCTAssertEqual(items[0].string(forType: .init("local.kama.encore.clip-id")), clip.id.uuidString, "encore's own drop targets read the first item")

            copy("some text", to: pb); model.clipboard.poll()
            let text = try XCTUnwrap(model.library.clips.first { $0.kind == .text })
            model.select(clip.id); model.select(text.id, modifiers: .command)
            let mixed = clipDragItems(model: model, clip: clip)
            XCTAssertEqual(mixed.count, 1)
            XCTAssertTrue(mixed[0].string(forType: .string)?.contains("some text") == true)
        }
    }

    @MainActor func testPastingFilesGivesTheirContentsAndStillTheFiles() throws {
        try withModel { model, pb in
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent("encore-paste-\(UUID())")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: folder) }
            let png = folder.appendingPathComponent("a.png"), md = folder.appendingPathComponent("b.md"), zip = folder.appendingPathComponent("c.zip")
            let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
            let image = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
            try image.write(to: png); try Data("# Titre".utf8).write(to: md); try Data("zip".utf8).write(to: zip)
            @MainActor func paste(_ urls: [URL]) throws {
                let payload = ClipPayload(items: urls.map { .init(["public.file-url": Data($0.absoluteString.utf8), "public.utf8-plain-text": Data($0.lastPathComponent.utf8)]) })
                model.accept(Clip(fingerprint: payload.fingerprint, kind: .file, text: "", sourceName: "Finder", sourceBundle: "com.apple.finder", byteCount: payload.byteCount, fileNames: urls.map(\.lastPathComponent)), payload: payload)
                model.paste([try XCTUnwrap(model.library.clips.first { $0.fingerprint == payload.fingerprint })], copyOnly: true)
                XCTAssertEqual(pb.pasteboardItems?.compactMap { $0.string(forType: .fileURL) }, urls.map(\.absoluteString), "The files stay, for the Finder and attachments")
            }
            try paste([md])
            XCTAssertEqual(pb.string(forType: .string), "# Titre")
            try paste([png])
            XCTAssertEqual(pb.data(forType: .png), image)
            XCTAssertNil(pb.string(forType: .string), "The file's name would compete with the image")
            try paste([png, md])
            XCTAssertEqual(pb.string(forType: .string), "# Titre")
            XCTAssertNotNil(pb.data(forType: .init("com.apple.flat-rtfd")))
            try paste([zip])
            XCTAssertEqual(pb.string(forType: .string), "c.zip", "A file without readable contents pastes as before")
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

    @MainActor func testAPastedSecretIsForgottenThenLeavesTheClipboard() throws {
        let delay = AppModel.pastedSecretClearDelay
        AppModel.pastedSecretClearDelay = 0.2
        defer { AppModel.pastedSecretClearDelay = delay }
        try withModel { model, pb in
            model.preferences.detectSecrets = true
            copy("ghp_aB3dE5fG7hJ9kL1mN3pQ5rS7tU9vW1xY3zA5x", to: pb); model.clipboard.poll()
            copy("an ordinary copy", to: pb); model.clipboard.poll()
            let secret = try XCTUnwrap(model.library.clips.first { $0.secret != nil })
            model.paste([secret], copyOnly: true)
            XCTAssertFalse(model.library.clips.contains { $0.id == secret.id }, "Gone from the history once pasted")
            XCTAssertEqual(pb.string(forType: .string), "ghp_aB3dE5fG7hJ9kL1mN3pQ5rS7tU9vW1xY3zA5x", "Still there to paste by hand")
            RunLoop.main.run(until: Date().addingTimeInterval(0.5))
            XCTAssertNil(pb.string(forType: .string), "Then emptied from the clipboard")
            XCTAssertEqual(model.library.clips.map(\.text), ["an ordinary copy"])
        }
    }

    @MainActor func testSeveralCardsPasteAndDragTheirRealTextInSelectionOrder() throws {
        try withModel { model, pb in
            model.preferences.detectSecrets = true; model.preferences.forgetPastedSecrets = false
            copy("first", to: pb); model.clipboard.poll()
            copy("ghp_aB3dE5fG7hJ9kL1mN3pQ5rS7tU9vW1xY3zA5x", to: pb); model.clipboard.poll()
            copy("third", to: pb); model.clipboard.poll()
            let id = { (start: String) in model.library.clips.first { $0.text.hasPrefix(start) }!.id }
            model.select(id("third")); model.select(id("first"), modifiers: .command); model.select(id("ghp"), modifiers: .command)
            XCTAssertEqual(model.pasteOrder(of: id("third")), 1)
            let expected = "third\nfirst\nghp_aB3dE5fG7hJ9kL1mN3pQ5rS7tU9vW1xY3zA5x"

            let provider = clipItemProvider(model: model, clip: model.library.clips.first { $0.id == id("third") }!)
            let loaded = expectation(description: "dragged text")
            var dragged = ""
            _ = provider.loadDataRepresentation(forTypeIdentifier: "public.utf8-plain-text") { data, _ in
                dragged = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""; loaded.fulfill()
            }
            wait(for: [loaded], timeout: 2)
            XCTAssertEqual(dragged, expected, "The first card carries all of them, one per line, the secret unmasked")

            model.paste(nil, copyOnly: true)
            XCTAssertEqual(pb.string(forType: .string), expected)
        }
    }

    @MainActor func testMergingASelectionMakesOneCopyWithoutSecrets() throws {
        try withModel { model, pb in
            model.preferences.detectSecrets = true
            copy("first", to: pb); model.clipboard.poll()
            copy("ghp_aB3dE5fG7hJ9kL1mN3pQ5rS7tU9vW1xY3zA5x", to: pb); model.clipboard.poll()
            copy("third", to: pb); model.clipboard.poll()
            let id = { (start: String) in model.library.clips.first { $0.text.hasPrefix(start) }!.id }
            model.select(id("third")); model.select(id("ghp"), modifiers: .command); model.select(id("first"), modifiers: .command)
            model.mergeSelection()
            XCTAssertEqual(model.library.clips.first?.text, "third\nfirst", "In selection order, the secret left out")
            XCTAssertEqual(model.library.clips.count, 4, "The originals stay")
        }
    }

    @MainActor func testConfidentialAndExcludedCopiesAreCountedWithoutBeingSaved() throws {
        try withModel { model, pb in
            let before = model.ignoredToday
            pb.clearContents()
            pb.setString("from a password manager", forType: .string)
            pb.setData(Data(), forType: .init("org.nspasteboard.ConcealedType"))
            model.clipboard.poll()
            model.preferences.excludedBundleIDs.append("org.mozilla.firefox")
            copy("from an excluded browser", to: pb); model.clipboard.poll()
            XCTAssertTrue(model.library.clips.isEmpty)
            XCTAssertEqual(model.ignoredToday[.confidential, default: 0], before[.confidential, default: 0] + 1)
            XCTAssertEqual(model.ignoredToday[.excludedApp, default: 0], before[.excludedApp, default: 0] + 1)
        }
    }
}
