import XCTest
@testable import Encore

final class InstalledExclusionsTests: XCTestCase {
    func testOnlyInstalledDefaultsAreEnabledAndLaterInstallationsAreDetected() {
        let first = Preferences.defaultExcludedBundleIDs[0]
        let second = Preferences.defaultExcludedBundleIDs[1]
        var preferences = Preferences()
        preferences.reconcileDefaultExclusions(installed: [first])
        XCTAssertEqual(preferences.excludedBundleIDs, [first])
        preferences.reconcileDefaultExclusions(installed: [first, second])
        XCTAssertEqual(preferences.excludedBundleIDs, [first, second])
        preferences.reconcileDefaultExclusions(installed: [second])
        XCTAssertEqual(preferences.excludedBundleIDs, [second])
    }

    func testManualOptOutSurvivesRefreshAndPreferenceRoundTrip() throws {
        let id = Preferences.defaultExcludedBundleIDs[0]
        var preferences = Preferences()
        preferences.reconcileDefaultExclusions(installed: [id])
        preferences.removeExcludedApp(id)
        preferences = try JSONDecoder().decode(Preferences.self, from: JSONEncoder().encode(preferences))
        preferences.reconcileDefaultExclusions(installed: [id])
        XCTAssertTrue(preferences.excludedBundleIDs.isEmpty)
    }

    func testLegacyOptOutIsPreservedWithoutDeletingCustomRules() throws {
        var preferences = try JSONDecoder().decode(Preferences.self, from: Data(#"{"excludedBundleIDs":["custom.app"]}"#.utf8))
        preferences.reconcileDefaultExclusions(installed: Set(Preferences.defaultExcludedBundleIDs.filter { $0 != "com.apple.Passwords" }))
        XCTAssertEqual(preferences.excludedBundleIDs, ["custom.app"])
    }
}
