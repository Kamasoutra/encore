import XCTest
@testable import EncoreCore

final class SearchTests: XCTestCase {
    func testSearchCombinesWordsAppAndTypeAndIgnoresAccents() {
        let clip = Clip(kind: .text, text: "Résumé de réunion", sourceName: "Safari", sourceBundle: "com.apple.Safari")
        XCTAssertTrue(ClipQuery(query: "resume reunion app:safari type:texte").matches(clip))
        XCTAssertFalse(ClipQuery(query: "resume app:xcode").matches(clip))
        XCTAssertFalse(ClipQuery(query: "type:image").matches(clip))
    }

    func testRecognizedImageTextIsSearchable() {
        var clip = Clip(kind: .image, text: "")
        clip.recognizedText = "Facture octobre 2026"
        XCTAssertTrue(ClipQuery(query: "octobre type:image").matches(clip))
    }

    func testDatesUseLocalCalendarAndExclusiveBeforeBound() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
        let date = ISO8601DateFormatter().date(from: "2026-10-24T23:30:00Z")!
        let clip = Clip(kind: .text, text: "", copiedAt: date)
        XCTAssertTrue(ClipQuery(query: "date:today after:2026-10-25 before:2026-10-26").matches(clip, now: date, calendar: calendar))
        XCTAssertFalse(ClipQuery(query: "before:2026-10-25").matches(clip, now: date, calendar: calendar))
        XCTAssertFalse(ClipQuery(query: "after:invalid").matches(clip, now: date, calendar: calendar))
    }

    func testFavoriteCollectionSourceAndTypeFiltersIntersect() {
        let collection = UUID()
        var clip = Clip(kind: .code, text: "let value = 1", sourceName: "Xcode", sourceBundle: "com.apple.dt.Xcode", favorite: true)
        clip.collectionIDs = [collection]
        XCTAssertTrue(ClipQuery(kind: .code, source: "com.apple.dt.Xcode", favorites: true, collectionID: collection).matches(clip))
        XCTAssertFalse(ClipQuery(collectionID: UUID()).matches(clip))
        XCTAssertFalse(ClipQuery(source: "com.apple.Safari").matches(clip))
    }
}
