import AppKit
import XCTest
@testable import EncoreCore

final class PasteboardTests: XCTestCase {
    private var pasteboard: NSPasteboard!
    override func setUp() { pasteboard = NSPasteboard(name: .init("Encore-Test-\(UUID())")) }
    override func tearDown() { pasteboard.releaseGlobally() }

    private func read(ignoreSensitive: Bool = true) throws -> (clip: Clip, payload: ClipPayload)? {
        try PasteboardCapture.read(pasteboard, sourceName: "Test", sourceBundle: "test.source", ignoreSensitive: ignoreSensitive)
    }

    func testSensitiveAndTransientItemsAreNotRecordedIncludingLaterItems() throws {
        for marker in PasteboardCapture.ignoredTypes {
            let ordinary = NSPasteboardItem()
            ordinary.setString("Ordinary text", forType: .string)
            let sensitive = NSPasteboardItem()
            sensitive.setString("SECRET DO NOT CAPTURE", forType: .string)
            sensitive.setData(Data(), forType: .init(marker))
            pasteboard.clearContents()
            pasteboard.writeObjects([ordinary, sensitive])
            XCTAssertNil(try read(), marker)
        }
    }

    func testRichTextAndCustomTypesSurviveCaptureWithoutTruncation() throws {
        let text = String(repeating: "é", count: 110_000)
        let item = NSPasteboardItem()
        item.setString(text, forType: .string)
        item.setData(Data([0, 1, 255]), forType: .rtf)
        item.setData(Data([5, 9]), forType: .init("com.example.custom"))
        pasteboard.writeObjects([item])
        let capture = try XCTUnwrap(read())
        XCTAssertEqual(capture.clip.text, text)
        XCTAssertEqual(capture.payload.items[0].representations[NSPasteboard.PasteboardType.rtf.rawValue], Data([0, 1, 255]))
        XCTAssertEqual(capture.payload.items[0].representations["com.example.custom"], Data([5, 9]))
        XCTAssertEqual(capture.clip.fingerprint, capture.payload.fingerprint)
    }

    func testMultipleFilesKeepDistinctItemsAndNames() throws {
        let urls = [URL(fileURLWithPath: "/tmp/first.pdf"), URL(fileURLWithPath: "/tmp/second.png")]
        let items = urls.map { url in let item = NSPasteboardItem(); item.setString(url.absoluteString, forType: .fileURL); return item }
        pasteboard.writeObjects(items)
        let capture = try XCTUnwrap(read())
        XCTAssertEqual(capture.clip.kind, .file)
        XCTAssertEqual(capture.clip.fileNames, ["first.pdf", "second.png"])
        XCTAssertEqual(capture.payload.items.count, 2)
    }

    func testOversizeContentIsRefused() throws {
        let item = NSPasteboardItem()
        item.setString("caption", forType: .string)
        item.setData(Data(repeating: 1, count: PasteboardCapture.maxBytes + 1), forType: .png)
        pasteboard.writeObjects([item])
        XCTAssertThrowsError(try read())
    }

    func testImageWithCaptionIsStillAnImage() throws {
        let item = NSPasteboardItem()
        item.setString("caption", forType: .string)
        item.setData(Data([1, 2, 3]), forType: .png)
        pasteboard.writeObjects([item])
        XCTAssertEqual(try read()?.clip.kind, .image)
    }
}
