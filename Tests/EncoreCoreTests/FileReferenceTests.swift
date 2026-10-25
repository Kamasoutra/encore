import XCTest
import AppKit
import CoreFoundation
@testable import EncoreCore

final class FileReferenceTests: XCTestCase {
    func testFinderReferenceResolvesToAnExistingFileAndFollowsARename() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Encore-Reference-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("Original.png")
        try Data("fixture".utf8).write(to: file)
        let reference = try referenceString(file)
        XCTAssertTrue(reference.contains("/.file/id="))
        let original = Data(reference.utf8)
        let payload = ClipPayload(items: [.init(["public.file-url": original])])
        let fingerprint = payload.fingerprint
        XCTAssertEqual(payload.fileURLs.first?.resolvingSymlinksInPath(), file.resolvingSymlinksInPath())
        let renamed = root.appendingPathComponent("Renamed.png")
        try FileManager.default.moveItem(at: file, to: renamed)
        XCTAssertEqual(payload.fileURLs.first?.resolvingSymlinksInPath(), renamed.resolvingSymlinksInPath())
        XCTAssertEqual(payload.items.first?.representations["public.file-url"], original)
        XCTAssertEqual(payload.fingerprint, fingerprint)
        XCTAssertEqual(PasteboardCapture.referencedSize(of: payload.fileURLs), 7)
    }

    func testCaptureUsesResolvedFinderFilenameAndSizeWithoutChangingTheReference() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("Encore-Reference-\(UUID()).pdf")
        try Data(repeating: 1, count: 512).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        let reference = try referenceString(file)
        let pb = NSPasteboard(name: .init("Encore-Reference-Test-\(UUID())"))
        defer { pb.releaseGlobally() }
        let item = NSPasteboardItem()
        item.setString(reference, forType: .fileURL)
        pb.clearContents(); pb.writeObjects([item])
        let captured = try XCTUnwrap(PasteboardCapture.read(pb, sourceName: "Finder", sourceBundle: "com.apple.finder"))
        XCTAssertEqual(captured.clip.fileNames, [file.lastPathComponent])
        XCTAssertEqual(captured.clip.referencedFileBytes, 512)
        XCTAssertEqual(captured.payload.fileURLs.first?.resolvingSymlinksInPath(), file.resolvingSymlinksInPath())
        XCTAssertEqual(captured.payload.items.first?.representations["public.file-url"], Data(reference.utf8))
    }
    private func referenceString(_ file: URL) throws -> String {
        let reference = try XCTUnwrap(CFURLCreateFileReferenceURL(nil, file as CFURL, nil)?.takeRetainedValue())
        return CFURLGetString(reference) as String
    }

}
