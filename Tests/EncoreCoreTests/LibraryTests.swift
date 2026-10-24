import XCTest
@testable import EncoreCore

final class LibraryTests: XCTestCase {
    func testRecopyPreservesFavoriteCollectionsAndRecognizedText() {
        let collection = UUID()
        var first = Clip(fingerprint: "same", kind: .image, text: "", sourceName: "Safari", favorite: true)
        first.collectionIDs = [collection]
        first.recognizedText = "Invoice 123"
        var library = Library()
        library.upsert(first)
        let copy = Clip(fingerprint: "same", kind: .image, text: "", sourceName: "Preview", copiedAt: Date().addingTimeInterval(5))
        XCTAssertEqual(library.upsert(copy), first.id)
        XCTAssertEqual(library.clips.count, 1)
        XCTAssertTrue(library.clips[0].favorite)
        XCTAssertEqual(library.clips[0].collectionIDs, [collection])
        XCTAssertEqual(library.clips[0].recognizedText, "Invoice 123")
        XCTAssertEqual(library.clips[0].sourceName, "Preview")
    }

    func testRetentionAndCountNeverEvictProtectedClips() {
        let now = Date()
        let old = now.addingTimeInterval(-90 * 86_400)
        let favorite = Clip(kind: .text, text: "favorite", copiedAt: old, favorite: true)
        var collection = Clip(kind: .text, text: "collection", copiedAt: old)
        collection.collectionIDs = [UUID()]
        let expired = Clip(kind: .text, text: "expired", copiedAt: old)
        let recent = Clip(kind: .text, text: "recent", copiedAt: now)
        let overflow = Clip(kind: .text, text: "overflow", copiedAt: now)
        var library = Library()
        library.clips = [favorite, recent, collection, overflow, expired]
        XCTAssertEqual(Set(library.prune(days: 30, limit: 1, now: now)), Set([overflow.id, expired.id]))
        XCTAssertEqual(Set(library.clips.map(\.id)), Set([favorite.id, collection.id, recent.id]))
    }

    func testUnlimitedRetentionDoesNotExpireOldClips() {
        var library = Library()
        library.clips = [Clip(kind: .text, text: "old", copiedAt: .distantPast)]
        XCTAssertTrue(library.prune(days: 0, limit: 0).isEmpty)
    }

    func testClassifiesContentWithoutMistakingOTPForColor() {
        XCTAssertEqual(ClipKind.detect(text: "123456"), .text)
        XCTAssertEqual(ClipKind.detect(text: "#FFF"), .color)
        XCTAssertEqual(ClipKind.detect(text: "#A78BFA"), .color)
        XCTAssertEqual(ClipKind.detect(text: "https://example.com/a?q=b"), .link)
        XCTAssertEqual(ClipKind.detect(text: "go to https://example.com"), .text)
        XCTAssertEqual(ClipKind.detect(text: "let answer = 42"), .code)
        XCTAssertEqual(ClipKind.detect(text: "file name", hasImage: true, hasFiles: true), .file)
        XCTAssertEqual(ClipKind.detect(text: "caption", hasImage: true), .image)
    }

    func testPayloadRoundTripPreservesRichFormatsAndMultipleItems() throws {
        let first = PasteItem(["public.utf8-plain-text": Data("Hello".utf8), "public.rtf": Data([0, 1, 255]), "com.vendor.custom": Data([9, 8, 7])])
        let second = PasteItem(["public.file-url": Data("file:///tmp/example.pdf".utf8)])
        let payload = ClipPayload(items: [first, second])
        let decoded = try JSONDecoder().decode(ClipPayload.self, from: JSONEncoder().encode(payload))
        XCTAssertEqual(payload, decoded)
        XCTAssertEqual(payload.fingerprint, decoded.fingerprint)
        XCTAssertEqual(payload.byteCount, decoded.byteCount)
    }

    func testFingerprintIsIndependentOfDictionaryOrderAndSensitiveToItemBoundaries() {
        let a = ClipPayload(items: [.init(["a": Data([1]), "b": Data([2])])])
        let b = ClipPayload(items: [.init(["b": Data([2]), "a": Data([1])])])
        let c = ClipPayload(items: [.init(["a": Data([1])]), .init(["b": Data([2])])])
        XCTAssertEqual(a.fingerprint, b.fingerprint)
        XCTAssertNotEqual(a.fingerprint, c.fingerprint)
        XCTAssertNotEqual(ClipPayload.text("a").fingerprint, ClipPayload.text("b").fingerprint)
    }
}
