import XCTest
import AppKit
import SwiftUI
@testable import Encore

final class PresentationTests: XCTestCase {
    func testGlobalQueueShortcutIsOptInAndItsPreferencePersists() throws {
        XCTAssertFalse(Preferences().stackShortcutEnabled)
        XCTAssertFalse(try JSONDecoder().decode(Preferences.self, from: Data("{}".utf8)).stackShortcutEnabled)
        var preferences = Preferences()
        preferences.stackShortcutEnabled = true
        XCTAssertTrue(try JSONDecoder().decode(Preferences.self, from: JSONEncoder().encode(preferences)).stackShortcutEnabled)
    }

    @MainActor func testQuickPasteUsesPhysicalNumberKeysOnAZERTYAndQWERTY() async throws {
        for (index, keyCode) in [UInt16(18), 19, 20, 21, 23, 22, 26, 28, 25].enumerated() {
            for character in ["&", String(index + 1)] {
                let event = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [.command], timestamp: 0, windowNumber: 0, context: nil, characters: character, charactersIgnoringModifiers: character, isARepeat: false, keyCode: keyCode))
                XCTAssertEqual(AppDelegate.quickPasteIndex(event), index)
            }
        }
        let alternate = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [.command, .option], timestamp: 0, windowNumber: 0, context: nil, characters: "1", charactersIgnoringModifiers: "1", isARepeat: false, keyCode: 18))
        XCTAssertNil(AppDelegate.quickPasteIndex(alternate))
    }

    @MainActor func testWhiteAndBlackSwatchesHaveContrastingLabels() async {
        XCTAssertEqual(Palette.swatchText("#FFFFFF", dark: true), Color.black)
        XCTAssertEqual(Palette.swatchText("#fff", dark: false), Color.black)
        XCTAssertEqual(Palette.swatchText("#000000", dark: false), Color.white)
        XCTAssertEqual(Palette.swatchText("#00000000", dark: false), Color.black)
        XCTAssertEqual(Palette.swatchText("#FFFFFF00", dark: true), Color.white)
    }
}
