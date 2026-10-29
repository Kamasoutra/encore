import XCTest
import AppKit
import Carbon
import EncoreCore
@testable import Encore

final class CompactWindowTests: XCTestCase {
    private let laptop = NSRect(x: 0, y: 0, width: 1512, height: 944)
    /// A second display to the left of the main one, with negative coordinates.
    private let side = NSRect(x: -2560, y: 120, width: 2560, height: 1415)

    func testHeightFitsTheChosenRowsAndNeverExceedsTheScreen() {
        for rows in 3...10 {
            let size = CompactPlacement.size(rows: rows, in: laptop)
            XCTAssertEqual(size.width, 360)
            XCTAssertEqual(size.height, CGFloat(rows) * 62 + CGFloat(rows - 1) * 6 + 160)
        }
        XCTAssertEqual(CompactPlacement.size(rows: 10, in: NSRect(x: 0, y: 0, width: 800, height: 500)).height, 480)
    }

    func testPositionsMapToCornersCenterAndEdgesWithTheMargin() {
        let size = CompactPlacement.size(rows: 6, in: laptop)
        let bottomLeft = CompactPlacement.frame(position: [0, 0], rows: 6, in: laptop)
        XCTAssertEqual(bottomLeft.origin, NSPoint(x: 10, y: 10))
        let topRight = CompactPlacement.frame(position: [1, 1], rows: 6, in: laptop)
        XCTAssertEqual(topRight.maxX, laptop.maxX - 10)
        XCTAssertEqual(topRight.maxY, laptop.maxY - 10)
        let center = CompactPlacement.frame(position: [0.5, 0.5], rows: 6, in: laptop)
        XCTAssertEqual(center.midX, laptop.midX, accuracy: 0.001)
        XCTAssertEqual(center.midY, laptop.midY, accuracy: 0.001)
        XCTAssertEqual(center.size, size)
    }

    func testMissingOrOutOfRangePositionsFallBackInsideTheScreen() {
        XCTAssertEqual(CompactPlacement.frame(position: [], rows: 6, in: laptop), CompactPlacement.frame(position: [1, 0.5], rows: 6, in: laptop))
        XCTAssertEqual(CompactPlacement.frame(position: [0], rows: 6, in: laptop), CompactPlacement.frame(position: [0, 0.5], rows: 6, in: laptop))
        let wild = CompactPlacement.frame(position: [-3, 7], rows: 6, in: laptop)
        XCTAssertTrue(laptop.insetBy(dx: 9.9, dy: 9.9).contains(wild))
    }

    func testSavedPositionRoundTripsAndKeepsItsRelativePlaceOnAnotherScreen() {
        for position in [[0.0, 0.0], [1, 1], [0.5, 0.5], [0.25, 0.8], [1, 0.5]] {
            let frame = CompactPlacement.frame(position: position, rows: 6, in: laptop)
            let saved = CompactPlacement.position(of: frame, in: laptop)
            XCTAssertEqual(saved[0], position[0], accuracy: 0.0001)
            XCTAssertEqual(saved[1], position[1], accuracy: 0.0001)
        }
        let topLeft = CompactPlacement.frame(position: [0, 1], rows: 6, in: laptop)
        let moved = CompactPlacement.frame(position: CompactPlacement.position(of: topLeft, in: laptop), rows: 6, in: side)
        XCTAssertEqual(moved.minX, side.minX + 10)
        XCTAssertEqual(moved.maxY, side.maxY - 10)
    }

    func testAWindowDraggedOffScreenSavesAPositionInsideIt() {
        let saved = CompactPlacement.position(of: NSRect(x: -400, y: 5000, width: 360, height: 568), in: laptop)
        XCTAssertEqual(saved, [0, 1])
    }

    func testSnappingPointsDrawTheWindowInWithoutJumping() {
        let size = CompactPlacement.size(rows: 6, in: laptop)
        let right = laptop.maxX - 10 - size.width, middle = (laptop.minY + 10 + laptop.maxY - 10 - size.height) / 2
        // Held still close to a point.
        XCTAssertEqual(CompactPlacement.attract(NSPoint(x: right - 4, y: middle + 3), size: size, in: laptop), NSPoint(x: right, y: middle))
        // Far from every point: untouched.
        let free = NSPoint(x: 400, y: 270)
        XCTAssertEqual(CompactPlacement.attract(free, size: size, in: laptop), free)
        // Drawn in: closer to the point than the pointer, but not on it, and further from it as the pointer moves away.
        var last: CGFloat = 0
        for distance in stride(from: CGFloat(8), to: 48, by: 4) {
            let x = CompactPlacement.attract(NSPoint(x: right - distance, y: 500), size: size, in: laptop).x
            let offset = right - x
            XCTAssertGreaterThan(offset, last)
            XCTAssertLessThan(offset, distance)
            last = offset
        }
        // No jump where the pull starts.
        XCTAssertEqual(CompactPlacement.attract(NSPoint(x: right - 47.99, y: 500), size: size, in: laptop).x, right - 47.99, accuracy: 0.05)
    }

    func testEachAxisSnapsOnItsOwnSoTheWindowSlidesAlongAnEdge() {
        let size = CompactPlacement.size(rows: 6, in: laptop)
        let left = laptop.minX + 10
        let snapped = CompactPlacement.attract(NSPoint(x: left + 2, y: 300), size: size, in: laptop)
        XCTAssertEqual(snapped.x, left)
        XCTAssertEqual(snapped.y, 300)
        let onSide = CompactPlacement.attract(NSPoint(x: side.minX + 12, y: side.maxY - 10 - size.height - 1), size: size, in: side)
        XCTAssertEqual(onSide, NSPoint(x: side.minX + 10, y: side.maxY - 10 - size.height))
    }

    func testCompactPreferencesMigrateFromTheSideColumnsAndStayInRange() throws {
        func decode(_ json: String) throws -> Preferences { try JSONDecoder().decode(Preferences.self, from: Data(json.utf8)) }
        let fresh = try decode("{}")
        XCTAssertEqual(fresh.placement, "bottom")
        XCTAssertEqual(fresh.compactPosition, [1, 0.5])
        XCTAssertEqual(fresh.compactCount, 6)
        let left = try decode(#"{"placement":"left"}"#)
        XCTAssertEqual(left.placement, "compact")
        XCTAssertEqual(left.compactPosition, [0, 0.5])
        XCTAssertEqual(try decode(#"{"placement":"right","compactPosition":[0.2,0.2]}"#).compactPosition, [1, 0.5])
        XCTAssertEqual(try decode(#"{"compactCount":1}"#).compactCount, 3)
        XCTAssertEqual(try decode(#"{"compactCount":42}"#).compactCount, 10)
        var custom = Preferences()
        custom.placement = "compact"; custom.compactPosition = [0.3, 0.9]; custom.compactCount = 8
        XCTAssertEqual(try JSONDecoder().decode(Preferences.self, from: JSONEncoder().encode(custom)), custom)
    }

    @MainActor func testClearingKeepsProtectedItemsUnlessEverythingGoes() {
        let model = AppModel(demo: true, pasteboard: NSPasteboard(name: .init("Encore-Clear-Test-\(UUID())")))
        defer { if let root = model.storage?.root { try? FileManager.default.removeItem(at: root) } }
        func fill() {
            var favorite = Clip(kind: .text, text: "Kept as a favorite"); favorite.favorite = true
            var snippet = Clip(kind: .code, text: "let kept = true"); snippet.snippet = true
            var filed = Clip(kind: .text, text: "Kept in a collection"); filed.collectionIDs = [UUID()]
            model.library.clips = [Clip(kind: .text, text: "Gone"), favorite, snippet, filed, Clip(kind: .link, text: "https://example.com")]
        }
        fill()
        model.clear(everything: false)
        XCTAssertEqual(Set(model.library.clips.map(\.text)), ["Kept as a favorite", "let kept = true", "Kept in a collection"])
        fill()
        model.clear(everything: true)
        XCTAssertTrue(model.library.clips.isEmpty)
    }

    @MainActor func testTheColumnGivesWayToTheLibraryOpenedFromIt() {
        let model = AppModel(demo: true, pasteboard: NSPasteboard(name: .init("Encore-Compact-Test-\(UUID())")))
        defer { if let root = model.storage?.root { try? FileManager.default.removeItem(at: root) } }
        XCTAssertFalse(model.sideColumn)
        XCTAssertFalse(model.columnShown)
        model.preferences.placement = "compact"
        XCTAssertTrue(model.sideColumn)
        XCTAssertTrue(model.columnShown)
        model.expanded = true
        XCTAssertTrue(model.sideColumn)
        XCTAssertFalse(model.columnShown)
    }
}

final class GlobalShortcutTests: XCTestCase {
    private func key(_ code: Int, _ characters: String, _ flags: NSEvent.ModifierFlags) throws -> NSEvent {
        try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: 0, context: nil,
                                       characters: characters, charactersIgnoringModifiers: characters, isARepeat: false, keyCode: UInt16(code)))
    }

    func testLabelsFollowTheMacOrderOfModifiers() throws {
        let all = try XCTUnwrap(GlobalShortcut(event: try key(kVK_ANSI_K, "k", [.command, .shift, .option, .control])))
        XCTAssertEqual(all.label, "⌃⌥⇧⌘K")
        XCTAssertEqual(all.modifiers, UInt32(cmdKey | shiftKey | optionKey | controlKey))
        XCTAssertEqual(GlobalShortcut(event: try key(kVK_ANSI_V, "v", .control))?.label, "⌃V")
    }

    func testNamedKeysAreSpelledOut() throws {
        XCTAssertEqual(GlobalShortcut(event: try key(kVK_Space, " ", .option))?.label, "⌥Space")
        XCTAssertEqual(GlobalShortcut(event: try key(kVK_F5, "\u{F708}", .control))?.label, "⌃F5")
        XCTAssertEqual(GlobalShortcut(event: try key(kVK_Return, "\r", [.command, .shift]))?.label, "⇧⌘↩")
    }

    func testCombinationsThatWouldStealKeysOrAppShortcutsAreRefused() throws {
        XCTAssertNil(GlobalShortcut(event: try key(kVK_ANSI_V, "v", .command)))
        XCTAssertNil(GlobalShortcut(event: try key(kVK_ANSI_C, "c", .command)))
        XCTAssertNil(GlobalShortcut(event: try key(kVK_ANSI_V, "v", .shift)))
        XCTAssertNil(GlobalShortcut(event: try key(kVK_F5, "\u{F708}", [])))
        XCTAssertNil(GlobalShortcut(event: try key(kVK_Escape, "\u{1B}", [.control, .option])))
    }

    func testPreferencesKeepLabelsThatContainTheSeparator() throws {
        let colon = try XCTUnwrap(GlobalShortcut(event: try key(kVK_ANSI_Period, ":", .option)))
        let restored = GlobalShortcut(preference: colon.preference)
        XCTAssertEqual(restored.label, colon.label)
        XCTAssertEqual(restored, colon)
    }

    func testTheSameKeysAreTheSameShortcutWhateverTheLabel() {
        XCTAssertEqual(GlobalShortcut(code: 9, modifiers: 768, label: "⇧⌘V"), .standard)
        XCTAssertNotEqual(GlobalShortcut(code: 9, modifiers: 2048, label: "⌘⇧V"), .standard)
        XCTAssertEqual(GlobalShortcut(preference: "9:768:anything").preference, "commandShiftV")
        XCTAssertEqual(GlobalShortcut(preference: "x:y:z"), .standard)
    }
}
