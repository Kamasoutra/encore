import XCTest
import AppKit
import EncoreCore
@testable import Encore

final class PeerImportTests: XCTestCase {
    func testSharingIsOffByDefaultAndSurvivesDecoding() throws {
        XCTAssertFalse(Preferences().shareWithPeers)
        XCTAssertFalse(try JSONDecoder().decode(Preferences.self, from: Data("{}".utf8)).shareWithPeers)
        var enabled = Preferences()
        enabled.shareWithPeers = true
        XCTAssertTrue(try JSONDecoder().decode(Preferences.self, from: JSONEncoder().encode(enabled)).shareWithPeers)
    }

    @MainActor func testRemotePayloadBecomesALocalCaptureWithItsFingerprint() throws {
        let payload = ClipPayload.text("https://example.com/remote")
        let clip = try XCTUnwrap(AppModel.clip(for: payload, sourceName: "Safari · depuis MacBook", sourceBundle: "com.apple.Safari"))
        XCTAssertEqual(clip.kind, .link)
        XCTAssertEqual(clip.text, "https://example.com/remote")
        XCTAssertEqual(clip.fingerprint, payload.fingerprint)
        XCTAssertEqual(clip.byteCount, payload.byteCount)
        XCTAssertEqual(clip.sourceName, "Safari · depuis MacBook")
        XCTAssertEqual(clip.sourceBundle, "com.apple.Safari")
    }

    @MainActor func testDemoModelKeepsPeersDisabled() {
        let pasteboard = NSPasteboard(name: .init("Encore-Peer-Test-\(UUID())"))
        defer { pasteboard.releaseGlobally() }
        let model = AppModel(demo: true, pasteboard: pasteboard)
        defer { if let root = model.storage?.root { model.storage?.flush(); try? FileManager.default.removeItem(at: root) } }
        XCTAssertNil(model.peerService)
        XCTAssertTrue(model.peers.isEmpty)
    }
}
