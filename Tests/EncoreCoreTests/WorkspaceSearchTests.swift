import XCTest
@testable import EncoreCore

final class WorkspaceSearchTests: XCTestCase {
    func testWeekFilterUsesCalendarBoundariesAndCombinesWithContent() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.firstWeekday = 2
        let now = ISO8601DateFormatter().date(from: "2026-10-25T12:00:00Z")!
        func clip(_ date: String, text: String = "invoice") -> Clip {
            Clip(kind: .text, text: text, copiedAt: ISO8601DateFormatter().date(from: date)!)
        }
        let search = ClipQuery(query: "date:week invoice")
        XCTAssertTrue(search.matches(clip("2026-10-19T00:00:00Z"), now: now, calendar: calendar))
        XCTAssertFalse(search.matches(clip("2026-10-18T23:59:59Z"), now: now, calendar: calendar))
        XCTAssertFalse(search.matches(clip("2026-10-26T00:00:00Z"), now: now, calendar: calendar))
        XCTAssertFalse(search.matches(clip("2026-10-24T00:00:00Z", text: "other"), now: now, calendar: calendar))
    }
}
