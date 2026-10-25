import XCTest
@testable import EncoreCore

final class RetentionTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private var utc: Calendar { var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!; return calendar }
    private func clip(_ bytes: Int, kind: ClipKind = .image) -> Clip { .init(kind: kind, text: "", copiedAt: now, byteCount: bytes) }

    func testExamplesResolveOverlapsAndExactSizeBoundaries() {
        let policy = RetentionPolicy(rules: RetentionRule.examples)
        for (bytes, seconds) in [(3_000_000_000, 3600.0), (500_000_000, 172800.0), (999_999_999, 172800.0), (1_000_000_000, 604800.0), (300_000_000, 604800.0), (299_999_999, 2592000.0)] {
            XCTAssertEqual(policy.decision(for: clip(bytes), calendar: utc).expiresAt, now.addingTimeInterval(seconds), "\(bytes)")
        }
        XCTAssertNil(policy.decision(for: clip(999_999, kind: .text), calendar: utc).expiresAt)
        XCTAssertNotNil(policy.decision(for: clip(1_000_000, kind: .text), calendar: utc).expiresAt)
        XCTAssertNotNil(policy.decision(for: clip(100, kind: .image), calendar: utc).expiresAt)
    }

    func testReorderingChangesTheWinningRuleAndDisabledRulesDoNotMatch() {
        let short = RetentionRule(minimumBytes: 100, duration: .init(1, .hours))
        var long = RetentionRule(minimumBytes: 100, duration: .init(7, .days))
        XCTAssertEqual(RetentionPolicy(rules: [short, long]).decision(for: clip(200)).ruleID, short.id)
        XCTAssertEqual(RetentionPolicy(rules: [long, short]).decision(for: clip(200)).ruleID, long.id)
        long.enabled = false
        XCTAssertEqual(RetentionPolicy(rules: [long, short]).decision(for: clip(200)).ruleID, short.id)
    }

    func testInvalidRulesAreSkippedInsteadOfDeletingContent() {
        let rules = [RetentionRule(minimumBytes: -1), RetentionRule(minimumBytes: 500, maximumBytes: 400), RetentionRule(duration: .init(0, .hours))]
        XCTAssertTrue(rules.allSatisfy { !$0.isValid })
        let decision = RetentionPolicy(rules: rules, fallback: .forever).decision(for: clip(1000))
        XCTAssertNil(decision.ruleID)
        XCTAssertNil(decision.expiresAt)
    }

    func testFilesUseReferencedSizeWhileStorageKeepsOnlyTheReference() {
        let file = Clip(kind: .file, text: "", copiedAt: now, byteCount: 120, referencedFileBytes: 3_000_000_000)
        let policy = RetentionPolicy(rules: RetentionRule.examples)
        XCTAssertEqual(file.byteCount, 120)
        XCTAssertEqual(file.retentionByteCount, 3_000_000_000)
        XCTAssertEqual(policy.decision(for: file, calendar: utc).expiresAt, now.addingTimeInterval(3600))
        let unknown = Clip(kind: .file, text: "", copiedAt: now, byteCount: 120)
        XCTAssertNil(unknown.retentionByteCount)
        XCTAssertNil(policy.decision(for: unknown).ruleID)
    }

    func testRuleManagedContentBypassesCountButExpiresAtTheDeadline() {
        var library = Library()
        let a = clip(100, kind: .text)
        let b = clip(200, kind: .text)
        library.clips = [a, b, clip(300), clip(400)]
        let policy = RetentionPolicy(rules: [.init(kind: .text, duration: .init(1, .hours))], fallback: .forever)
        XCTAssertEqual(library.prune(policy: policy, limit: 1, now: now).count, 1)
        XCTAssertEqual(library.clips.count, 3)
        XCTAssertTrue(library.prune(policy: policy, limit: 1, now: now.addingTimeInterval(3599)).isEmpty)
        XCTAssertEqual(Set(library.prune(policy: policy, limit: 1, now: now.addingTimeInterval(3600))), Set([a.id, b.id]))
    }

    func testTinyTextForeverSurvivesAgeAndCountButPinsOverrideEveryRule() {
        var tiny = clip(50, kind: .text)
        tiny.copiedAt = .distantPast
        var pinned = clip(5_000_000_000)
        pinned.copiedAt = .distantPast; pinned.favorite = true
        var library = Library(); library.clips = [tiny, pinned]
        XCTAssertTrue(library.prune(policy: .init(rules: RetentionRule.examples), limit: 1, now: now).isEmpty)
    }

    func testRecopyPreservesFirstTimestampRefreshesFileSizeAndRenewsDeadline() {
        let first = Clip(fingerprint: "same", kind: .file, text: "", copiedAt: now, referencedFileBytes: 3_000_000_000)
        var library = Library(); library.upsert(first)
        let nextDate = now.addingTimeInterval(1200)
        library.upsert(Clip(fingerprint: "same", kind: .file, text: "", copiedAt: nextDate, referencedFileBytes: 600_000_000))
        let updated = library.clips[0]
        XCTAssertEqual(updated.firstCopyDate, now)
        XCTAssertEqual(updated.copiedAt, nextDate)
        XCTAssertEqual(updated.referencedFileBytes, 600_000_000)
        XCTAssertEqual(RetentionPolicy(rules: RetentionRule.examples).decision(for: updated, calendar: utc).expiresAt, nextDate.addingTimeInterval(172800))
    }

    func testCalendarMonthsAndDaylightSavingTime() {
        let january = ISO8601DateFormatter().date(from: "2026-01-31T12:00:00Z")!
        let february = ISO8601DateFormatter().date(from: "2026-02-28T12:00:00Z")!
        XCTAssertEqual(RetentionDuration(1, .months).expiration(from: january, calendar: utc), february)
        var paris = utc; paris.timeZone = TimeZone(identifier: "Europe/Paris")!
        let beforeChange = ISO8601DateFormatter().date(from: "2026-10-24T10:00:00Z")!
        XCTAssertEqual(RetentionDuration(1, .days).expiration(from: beforeChange, calendar: paris)?.timeIntervalSince(beforeChange), 25 * 3600)
    }

    func testLegacyLibraryWithoutNewFieldsStillDecodes() throws {
        let original = clip(100)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as? [String: Any])
        object.removeValue(forKey: "firstCopiedAt"); object.removeValue(forKey: "referencedFileBytes")
        let decoded = try JSONDecoder().decode(Clip.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertEqual(decoded.firstCopyDate, original.copiedAt)
        XCTAssertNil(decoded.referencedFileBytes)
    }
}
