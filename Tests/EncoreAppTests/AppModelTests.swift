import XCTest
import AppKit
import EncoreCore
@testable import Encore

final class AppModelTests: XCTestCase {
    @MainActor private func withModel(_ body: (AppModel) throws -> Void) throws {
        let pasteboard = NSPasteboard(name: .init("Encore-Model-Test-\(UUID())"))
        defer { pasteboard.releaseGlobally() }
        let model = AppModel(demo: true, pasteboard: pasteboard)
        let root = try XCTUnwrap(model.storage?.root)
        defer { model.storage?.flush(); try? FileManager.default.removeItem(at: root) }
        model.library = Library()
        model.preferences.retentionDays = 0
        try body(model)
    }

    @MainActor func testCollectionMembershipIsMultipleAndRemovingCollectionKeepsContent() async throws {
        try withModel { model in
            model.addText("Keep me")
            let id = try XCTUnwrap(model.library.clips.first?.id)
            let a = ClipCollection(name: "A")
            let b = ClipCollection(name: "B")
            model.library.collections = [a, b]
            model.assignCollection(a.id, ids: [id])
            model.assignCollection(b.id, ids: [id])
            model.assignCollection(b.id, ids: [id], toggle: false)
            XCTAssertEqual(model.library.clips[0].collectionIDs, [a.id, b.id])
            model.deleteCollection(a)
            XCTAssertEqual(model.library.clips.count, 1)
            XCTAssertEqual(model.library.clips[0].collectionIDs, [b.id])
        }
    }

    @MainActor func testDeletionCleansQueueAndUndoRestoresPayloadAndFavorite() async throws {
        try withModel { model in
            model.addText("Retain rich data")
            let clip = try XCTUnwrap(model.library.clips.first)
            model.toggleFavorite([clip.id])
            model.enqueue([clip.id])
            model.remove([clip.id])
            XCTAssertTrue(model.queue.isEmpty)
            XCTAssertTrue(model.library.clips.isEmpty)
            model.undoDelete()
            XCTAssertEqual(model.library.clips.count, 1)
            XCTAssertTrue(model.library.clips[0].favorite)
            XCTAssertEqual(model.storage?.payload(clip.id), .text("Retain rich data"))
        }
    }

    @MainActor func testRemovingFavoriteWhileViewingFavoritesSelectsRemainingItem() async throws {
        try withModel { model in
            model.addText("first")
            model.addText("second")
            for clip in model.library.clips { model.toggleFavorite([clip.id]) }
            model.board = "favorites"
            let id = try XCTUnwrap(model.cursor)
            model.toggleFavorite([id])
            XCTAssertEqual(model.filtered.count, 1)
            XCTAssertEqual(model.cursor, model.filtered[0].id)
            XCTAssertEqual(model.selectedClips.count, 1)
        }
    }

    @MainActor func testTransformCreatesACopyAndLeavesTheOriginalUntouched() async throws {
        try withModel { model in
            model.addText("Hello world")
            let original = try XCTUnwrap(model.library.clips.first)
            model.transform(.uppercase, clip: original)
            XCTAssertEqual(Set(model.library.clips.map(\.text)), ["Hello world", "HELLO WORLD"])
            XCTAssertEqual(model.storage?.payload(original.id), .text("Hello world"))
        }
    }

    @MainActor func testQueueCollectionPreservesCopyOrderAndDeduplicates() async throws {
        try withModel { model in
            model.collecting = true
            model.addText("one")
            model.addText("two")
            model.addText("one")
            XCTAssertEqual(model.queue.compactMap { id in model.library.clips.first { $0.id == id }?.text }, ["one", "two"])
            XCTAssertEqual(model.library.clips.count, 2)
        }
    }

    @MainActor func testBudgetRefusesNewDataWithoutEvictingExistingData() async throws {
        try withModel { model in
            model.addText("existing")
            model.preferences.storageLimitMB = 0
            model.addText("rejected")
            XCTAssertEqual(model.library.clips.map(\.text), ["existing"])
            XCTAssertEqual(model.status, L("Storage full: increase the limit or delete some items."))
        }
    }

    @MainActor func testShiftSelectionIncludesTheRangeAndNavigationDoesNotWrap() async throws {
        try withModel { model in
            for value in ["1", "2", "3"] { model.addText(value) }
            let ids = model.filtered.map(\.id)
            model.select(ids[0])
            model.select(ids[2], modifiers: .shift)
            XCTAssertEqual(model.selection, Set(ids))
            model.move(1)
            XCTAssertEqual(model.cursor, ids[2])
            model.move(-99)
            XCTAssertEqual(model.cursor, ids[0])
        }
    }

    @MainActor func testExpiringSelectedMiddleItemKeepsSelectionBesideTheGap() async throws {
        try withModel { model in
            let now = Date()
            model.preferences.detectSecrets = true
            model.preferences.secretLifetime = 30
            model.library.clips = (0..<12).map { Clip(kind: .text, text: "Item \($0)", copiedAt: now) }
            model.library.clips[2].secret = .password
            model.library.clips[7].secret = .password
            model.library.clips[2].copiedAt = now.addingTimeInterval(-31)
            model.library.clips[7].copiedAt = now.addingTimeInterval(-31)
            let next = model.library.clips[8].id
            model.select(model.library.clips[7].id)
            model.prune(now: now)
            XCTAssertEqual(model.cursor, next)
            XCTAssertEqual(model.selection, [next])
            let following = model.library.clips[7].id
            model.select(following, modifiers: .shift)
            XCTAssertEqual(model.selection, [next, following])
        }
    }

    @MainActor func testClearingSelectedLastItemSelectsItsPreviousNeighbor() async throws {
        try withModel { model in
            model.library.clips = (0..<12).map { Clip(kind: .text, text: "Item \($0)") }
            let previous = model.library.clips[10].id
            let last = model.library.clips[11].id
            model.select(last)
            model.forgetCleared(last)
            XCTAssertEqual(model.cursor, previous)
            XCTAssertEqual(model.selection, [previous])
        }
    }

    @MainActor func testQueueDeliveryUpdatesThePasteboardInFIFOOrderThenDisarms() async throws {
        try withModel { model in
            let pasteboard = NSPasteboard(name: .init("Encore-Queue-Test-\(UUID())"))
            defer { pasteboard.releaseGlobally() }
            model.clipboard = ClipboardService(model: model, pasteboard: pasteboard)
            model.collecting = true
            model.addText("one")
            model.addText("two")
            XCTAssertTrue(model.advanceQueue())
            XCTAssertEqual(pasteboard.string(forType: .string), "one")
            XCTAssertTrue(model.collecting)
            XCTAssertTrue(model.advanceQueue())
            XCTAssertEqual(pasteboard.string(forType: .string), "two")
            XCTAssertFalse(model.collecting)
            XCTAssertFalse(model.advanceQueue())
        }
    }

    @MainActor func testPlainPasteRemovesRichFormattingButOriginalPayloadIsPreserved() async throws {
        try withModel { model in
            let pasteboard = NSPasteboard(name: .init("Encore-Plain-Test-\(UUID())"))
            defer { pasteboard.releaseGlobally() }
            model.clipboard = ClipboardService(model: model, pasteboard: pasteboard)
            let payload = ClipPayload(items: [.init([NSPasteboard.PasteboardType.string.rawValue: Data("hello".utf8), NSPasteboard.PasteboardType.rtf.rawValue: Data([1, 2, 3])])])
            let clip = Clip(fingerprint: payload.fingerprint, kind: .text, text: "hello")
            model.accept(clip, payload: payload)
            model.paste([clip], plain: true, copyOnly: true)
            XCTAssertEqual(pasteboard.string(forType: .string), "hello")
            XCTAssertNil(pasteboard.data(forType: .rtf))
            XCTAssertEqual(model.storage?.payload(clip.id), payload)
            model.paste([clip], copyOnly: true)
            XCTAssertEqual(pasteboard.data(forType: .rtf), Data([1, 2, 3]))
        }
    }

    @MainActor func testShiftNavigationShrinksSelectionWhenReversingDirection() async throws {
        try withModel { model in
            for value in ["one", "two", "three"] { model.addText(value) }
            let ids = model.filtered.map(\.id)
            model.select(ids[0])
            model.move(1, extend: true)
            model.move(1, extend: true)
            XCTAssertEqual(model.selection.count, 3)
            model.move(-1, extend: true)
            XCTAssertEqual(model.selection, Set(ids[0...1]))
        }
    }

    @MainActor func testEditingToExistingContentMergesPinsWithoutDuplicateCards() async throws {
        try withModel { model in
            model.addText("first")
            let first = try XCTUnwrap(model.library.clips.first)
            model.toggleFavorite([first.id])
            model.addText("second")
            let second = try XCTUnwrap(model.library.clips.first)
            model.enqueue([first.id, second.id])
            XCTAssertTrue(model.updateText(second.id, text: "first", title: "Merged"))
            XCTAssertEqual(model.library.clips.count, 1)
            XCTAssertTrue(model.library.clips[0].favorite)
            XCTAssertEqual(model.queue, [second.id])
            XCTAssertEqual(model.storage?.payload(second.id), .text("first"))
            XCTAssertNil(model.storage?.payload(first.id))
        }
    }

    @MainActor func testMissingQueuePayloadStopsInsteadOfReusingStaleClipboard() async throws {
        try withModel { model in
            model.addText("missing")
            let id = try XCTUnwrap(model.library.clips.first?.id)
            model.enqueue([id])
            model.collecting = true
            model.storage?.save(model.library, deleting: [id])
            model.storage?.flush()
            XCTAssertFalse(model.advanceQueue())
            XCTAssertFalse(model.collecting)
            XCTAssertEqual(model.status, L("Queue stopped: this item's content is unavailable."))
        }
    }

    @MainActor func testVisionRecognizesAnActualImageAndMakesItSearchable() async throws {
        let pasteboard = NSPasteboard(name: .init("Encore-OCR-Test-\(UUID())"))
        let model = AppModel(demo: true, pasteboard: pasteboard)
        let root = try XCTUnwrap(model.storage?.root)
        defer { model.storage?.flush(); try? FileManager.default.removeItem(at: root); pasteboard.releaseGlobally() }
        model.library = Library()
        let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 700, pixelsHigh: 160, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        NSColor.white.setFill()
        NSRect(x: 0, y: 0, width: 700, height: 160).fill()
        ("ENCORE 2026" as NSString).draw(at: NSPoint(x: 30, y: 50), withAttributes: [.font: NSFont.systemFont(ofSize: 60, weight: .bold), .foregroundColor: NSColor.black])
        NSGraphicsContext.restoreGraphicsState()
        let data = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        let payload = ClipPayload(items: [.init([NSPasteboard.PasteboardType.png.rawValue: data])])
        let clip = Clip(fingerprint: payload.fingerprint, kind: .image, text: "", byteCount: data.count)
        model.accept(clip, payload: payload)
        let preview = try XCTUnwrap(model.image(for: clip)?.cgImage(forProposedRect: nil, context: nil, hints: nil))
        XCTAssertLessThanOrEqual(preview.width, 640)
        for _ in 0..<100 {
            if model.library.clips.first?.recognizedText.contains("2026") == true { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        XCTAssertTrue(model.library.clips.first?.recognizedText.contains("ENCORE") == true)
        model.query = "2026 type:image"
        XCTAssertEqual(model.filtered.map(\.id), [clip.id])
    }
}
