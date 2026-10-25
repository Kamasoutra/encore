import XCTest
@testable import EncoreCore

final class LocalizationTests: XCTestCase {
    func testFrenchAndEnglishTranslateControlsAndInterpolatedMessages() {
        let previous = Localization.language
        defer { Localization.language = previous }
        Localization.language = "en"
        XCTAssertEqual(L("Réglages"), "Settings")
        XCTAssertEqual(ClipKind.file.title, "Files")
        XCTAssertEqual(L("il y a \(5) min"), "5 min ago")
        XCTAssertEqual(L("Expire dans \("2 h")"), "Expires in 2 h")
        Localization.language = "fr"
        XCTAssertEqual(L("Réglages"), "Réglages")
        XCTAssertEqual(ClipKind.file.title, "Fichiers")
        XCTAssertEqual(L("il y a \(5) min"), "il y a 5 min")
    }

    func testBundledLanguagesHaveMatchingKeys() throws {
        let fr = try XCTUnwrap(Localization.resources.url(forResource: "Localizable", withExtension: "strings", subdirectory: "fr.lproj"))
        let en = try XCTUnwrap(Localization.resources.url(forResource: "Localizable", withExtension: "strings", subdirectory: "en.lproj"))
        let french = try XCTUnwrap(NSDictionary(contentsOf: fr) as? [String: String])
        let english = try XCTUnwrap(NSDictionary(contentsOf: en) as? [String: String])
        XCTAssertEqual(Set(french.keys), Set(english.keys))
        XCTAssertGreaterThan(french.count, 300)
    }

    func testSearchTypeNamesRemainValidWhenTheInterfaceLanguageChanges() {
        let previous = Localization.language
        defer { Localization.language = previous }
        let file = Clip(kind: .file, text: "")
        for language in ["en", "fr"] {
            Localization.language = language
            XCTAssertTrue(ClipQuery(query: "type:file").matches(file))
            XCTAssertTrue(ClipQuery(query: "type:fichiers").matches(file))
            XCTAssertFalse(ClipQuery(query: "type:texte").matches(file))
        }
    }
}
