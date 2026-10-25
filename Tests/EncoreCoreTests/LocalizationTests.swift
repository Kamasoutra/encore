import XCTest
@testable import EncoreCore

final class LocalizationTests: XCTestCase {
    private static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    private var resources: URL { Localization.resources.resourceURL ?? Localization.resources.bundleURL }
    private var bundled: [String] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: resources.path)) ?? []
        return names.filter { $0.hasSuffix(".lproj") }.map { String($0.dropLast(6)) }.sorted()
    }
    private func strings(_ code: String) throws -> [String: String] {
        let url = resources.appendingPathComponent("\(code).lproj/Localizable.strings")
        return try XCTUnwrap(NSDictionary(contentsOf: url) as? [String: String], "\(code): Localizable.strings illisible")
    }
    private func plurals(_ code: String) throws -> [String: [String: Any]] {
        let url = resources.appendingPathComponent("\(code).lproj/Localizable.stringsdict")
        return try XCTUnwrap(NSDictionary(contentsOf: url) as? [String: [String: Any]], "\(code): Localizable.stringsdict illisible")
    }
    private func withLanguage<T>(_ code: String, _ body: () throws -> T) rethrows -> T {
        let previous = Localization.language
        defer { Localization.language = previous }
        Localization.language = code
        return try body()
    }

    func testFrenchAndEnglishTranslateControlsPluralsAndInterpolatedMessages() {
        withLanguage("en") {
            XCTAssertEqual(L("Settings"), "Settings")
            XCTAssertEqual(ClipKind.file.title, "Files")
            XCTAssertEqual(L("Expires in \("2 h")"), "Expires in 2 h")
            XCTAssertEqual(L("100% local"), "100% local")
            XCTAssertEqual([0, 1, 2].map { L("\($0) items") }, ["0 items", "1 item", "2 items"])
            XCTAssertEqual(RetentionUnit.weeks.title(count: 1), "week")
            XCTAssertEqual(RetentionUnit.weeks.title(count: 3), "weeks")
        }
        withLanguage("fr") {
            XCTAssertEqual(L("Settings"), "Réglages")
            XCTAssertEqual(ClipKind.file.title, "Fichiers")
            XCTAssertEqual([0, 1, 2].map { L("\($0) items") }, ["0 élément", "1 élément", "2 éléments"])
            XCTAssertEqual(L("\(1) items deleted · ⌘Z to undo"), "1 élément supprimé · ⌘Z pour annuler")
            XCTAssertEqual(RetentionUnit.months.title(count: 2), "mois")
        }
    }

    func testFormattersFollowTheSelectedLanguage() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        withLanguage("en") {
            XCTAssertEqual(Localization.number(10_000), "10,000")
            XCTAssertTrue(Localization.bytes(1_500_000).hasSuffix("MB"))
            XCTAssertEqual(Localization.relative(now.addingTimeInterval(-300), to: now), "5 min. ago")
            XCTAssertEqual(Localization.relative(now.addingTimeInterval(-10), to: now), "Just now")
            XCTAssertEqual(Localization.date(now, time: false), now.formatted(Date.FormatStyle(date: .numeric, time: .omitted, locale: Locale(identifier: "en"))))
        }
        withLanguage("fr") {
            XCTAssertEqual(Localization.number(10_000), "10\u{202F}000")
            XCTAssertTrue(Localization.bytes(1_500_000).hasSuffix("Mo"))
            XCTAssertEqual(Localization.relative(now.addingTimeInterval(-7200), to: now).replacingOccurrences(of: "\u{A0}", with: " "), "il y a 2 h")
            XCTAssertEqual(Localization.date(now, time: false), now.formatted(Date.FormatStyle(date: .numeric, time: .omitted, locale: Locale(identifier: "fr"))))
        }
        let dates = ["en", "fr"].map { code in withLanguage(code) { Localization.date(now) } }
        XCTAssertNotEqual(dates[0], dates[1])
    }

    func testSupportedLanguagesMatchBundledTablesAndInfoPlist() throws {
        XCTAssertEqual(Set(Localization.supported), Set(bundled))
        XCTAssertEqual(Localization.supported, Localization.catalog.filter(bundled.contains), "ordre du catalogue")
        XCTAssertTrue(Set(bundled).isSubset(of: Localization.catalog), "langue absente du catalogue : \(Set(bundled).subtracting(Localization.catalog))")
        XCTAssertTrue(Localization.supported.contains("en") && Localization.supported.contains("fr"))
        let info = try XCTUnwrap(NSDictionary(contentsOf: Self.root.appendingPathComponent("Resources/Info.plist")))
        XCTAssertEqual(info["CFBundleDevelopmentRegion"] as? String, "en")
        XCTAssertEqual(info["CFBundleLocalizations"] as? [String], Localization.supported)
        Localization.language = "xx"
        XCTAssertEqual(Localization.language, "system")
    }

    func testSystemLanguageResolutionFallsBackToTheClosestTable() {
        let expectations = [("pt-PT", "pt-BR"), ("pt", "pt-BR"), ("zh-HK", "zh-Hant"), ("zh-TW", "zh-Hant"), ("zh-CN", "zh-Hans"), ("nn", "nb"), ("no", "nb"), ("iw", "he"), ("de-CH", "de"), ("fr-CA", "fr"), ("en-GB", "en")]
        for (preference, expected) in expectations {
            let resolved = Localization.resolve([preference])
            XCTAssertTrue(Localization.supported.contains(resolved))
            if Localization.supported.contains(expected) { XCTAssertEqual(resolved, expected, preference) }
        }
        XCTAssertEqual(Localization.resolve(["xx"]), "en")
        XCTAssertEqual(Localization.resolve(["xx", "fr"]), "fr")
    }

    func testLanguageNamesAndReadingDirection() {
        XCTAssertEqual(Localization.nativeName("fr"), "Français")
        XCTAssertEqual(Localization.nativeName("en"), "English")
        XCTAssertEqual(Localization.nativeName("zh-Hant"), "繁體中文")
        withLanguage("fr") {
            XCTAssertEqual(Localization.displayName("de"), "Allemand")
            XCTAssertFalse(Localization.isRightToLeft)
        }
        XCTAssertEqual(Localization.step(rightArrow: true, rightToLeft: false), 1)
        XCTAssertEqual(Localization.step(rightArrow: false, rightToLeft: false), -1)
        XCTAssertEqual(Localization.step(rightArrow: true, rightToLeft: true), -1)
        XCTAssertEqual(Localization.step(rightArrow: false, rightToLeft: true), 1)
        XCTAssertEqual(Locale.Language(identifier: "ar").characterDirection, .rightToLeft)
        XCTAssertEqual(Locale.Language(identifier: "he").characterDirection, .rightToLeft)
    }

    func testEveryLanguageHasTheSourceKeysAndNoEmptyValue() throws {
        let french = try strings("fr"), frenchPlurals = try plurals("fr")
        XCTAssertGreaterThan(french.count + frenchPlurals.count, 300)
        XCTAssertTrue(Set(french.keys).isDisjoint(with: frenchPlurals.keys), "une clé plurielle ne doit pas figurer dans Localizable.strings")
        for code in bundled {
            let table = try strings(code), plural = try plurals(code)
            XCTAssertEqual(Set(table.keys).symmetricDifference(french.keys), [], "\(code): Localizable.strings")
            XCTAssertEqual(Set(plural.keys).symmetricDifference(frenchPlurals.keys), [], "\(code): Localizable.stringsdict")
            for (key, value) in table { XCTAssertFalse(value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, "\(code): valeur vide pour \(key)") }
        }
    }

    func testFormatSpecifiersMatchBetweenKeysAndTranslations() throws {
        for code in bundled {
            for (key, value) in try strings(code) {
                XCTAssertEqual(try Self.arguments(value), try Self.arguments(key), "\(code): \(key) → \(value)")
            }
            for (key, entry) in try plurals(code) {
                let format = try XCTUnwrap(entry["NSStringLocalizedFormatKey"] as? String, "\(code): \(key)")
                var resolved = format
                for match in format.matches(of: #/%(\d+\$)?#@(\w+)@/#) {
                    let variable = try XCTUnwrap(entry[String(match.2)] as? [String: String], "\(code): \(key) variable \(match.2)")
                    let type = try XCTUnwrap(variable["NSStringFormatValueTypeKey"], "\(code): \(key)")
                    resolved = resolved.replacingOccurrences(of: String(match.0), with: "%\(match.1 ?? "")\(type)")
                    for (category, text) in variable where !category.hasPrefix("NSString") {
                        XCTAssertFalse(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, "\(code): \(key) [\(category)] vide")
                        XCTAssertTrue(try Self.arguments(text).allSatisfy { $0 == type }, "\(code): \(key) [\(category)] → \(text)")
                    }
                }
                XCTAssertEqual(try Self.arguments(resolved), try Self.arguments(key), "\(code): \(key) → \(format)")
            }
        }
    }

    func testPluralTablesDeclareEveryCategoryUsedByTheLanguage() throws {
        for code in bundled {
            let required = try Self.categories(code)
            for (key, entry) in try plurals(code) {
                let variables = entry.filter { $0.key != "NSStringLocalizedFormatKey" }
                XCTAssertFalse(variables.isEmpty, "\(code): \(key)")
                for (name, raw) in variables {
                    let variable = try XCTUnwrap(raw as? [String: String], "\(code): \(key).\(name)")
                    XCTAssertEqual(variable["NSStringFormatSpecTypeKey"], "NSStringPluralRuleType", "\(code): \(key).\(name)")
                    XCTAssertEqual(variable["NSStringFormatValueTypeKey"], "lld", "\(code): \(key).\(name)")
                    let present = Set(variable.keys.filter { !$0.hasPrefix("NSString") })
                    XCTAssertTrue(present.isSubset(of: ["zero", "one", "two", "few", "many", "other"]), "\(code): \(key) catégories inconnues \(present)")
                    XCTAssertTrue(required.isSubset(of: present), "\(code): \(key) manque \(required.subtracting(present).sorted())")
                }
            }
        }
    }

    func testEverySourceStringHasATranslationAndEveryKeyIsUsed() throws {
        let sources = Self.root.appendingPathComponent("Sources")
        let files = FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil)?.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" } ?? []
        var used = Set<String>()
        for file in files { used.formUnion(Self.literals(in: try String(contentsOf: file, encoding: .utf8))) }
        let keys = Set(try strings("fr").keys).union(try plurals("fr").keys)
        XCTAssertGreaterThan(used.count, 300)
        XCTAssertEqual(used.subtracting(keys.map(Self.shape)).sorted(), [], "chaînes sans traduction")
        XCTAssertEqual(Set(keys.map(Self.shape)).subtracting(used).sorted(), [], "clés inutilisées")
    }

    func testSearchTypeNamesAcceptEnglishAndTheActiveLanguage() {
        let file = Clip(kind: .file, text: "")
        for code in Localization.supported {
            withLanguage(code) {
                XCTAssertTrue(ClipQuery(query: "type:file").matches(file), code)
                let local = ClipKind.file.title.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Localization.locale).filter { !$0.isWhitespace }
                XCTAssertTrue(ClipQuery(query: "type:\(local)").matches(file), code)
                XCTAssertFalse(ClipQuery(query: "type:text").matches(file), code)
                XCTAssertFalse(ClipQuery(query: "type:\(ClipKind.text.title)").matches(file), code)
            }
        }
    }

    private static let specifier = #/%(?:(\d+)\$)?(@|lld|llu|ld|lu|lf|d|i|u|f|%)/#

    private static func arguments(_ text: String) throws -> [String] {
        var positional: [Int: String] = [:], sequential: [String] = []
        for match in text.matches(of: specifier) where match.2 != "%" {
            if let position = match.1.flatMap({ Int($0) }) { positional[position] = String(match.2) } else { sequential.append(String(match.2)) }
        }
        guard !positional.isEmpty else { return sequential }
        XCTAssertTrue(sequential.isEmpty, "mélange de %@ et %1$@ : \(text)")
        XCTAssertEqual(Set(positional.keys), Set(1...positional.count), "positions incomplètes : \(text)")
        return positional.sorted { $0.key < $1.key }.map(\.value)
    }

    private static func shape(_ key: String) -> String { key.replacing(specifier) { $0.2 == "%" ? "%%" : "%*" } }

    private static func categories(_ code: String) throws -> Set<String> {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("encore-plural-\(UUID().uuidString)/probe.lproj")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory.deletingLastPathComponent()) }
        var variants: [String: String] = ["NSStringFormatSpecTypeKey": "NSStringPluralRuleType", "NSStringFormatValueTypeKey": "lld"]
        for category in ["one", "two", "few", "many", "other"] { variants[category] = category }
        try (["probe": ["NSStringLocalizedFormatKey": "%#@n@", "n": variants]] as NSDictionary).write(to: directory.appendingPathComponent("Localizable.stringsdict"))
        let format = try XCTUnwrap(Bundle(path: directory.path)).localizedString(forKey: "probe", value: nil, table: nil)
        let locale = Locale(identifier: code)
        var found = Set((Array(0...1000) + [1_000_000, 2_000_000, 10_000_000]).map { String(format: format, locale: locale, $0) })
        found.insert("other")
        if code == "ar" { found.insert("zero") }
        return found
    }

    private static func literals(in source: String) -> [String] {
        let characters = Array(source)
        var keys: [String] = [], index = 0
        func literal(_ start: Int) -> (String, Int) {
            var key = "", i = start
            while i < characters.count, characters[i] != "\"" {
                if characters[i] == "\\", i + 1 < characters.count {
                    if characters[i + 1] == "(" {
                        var depth = 1; i += 2
                        while i < characters.count, depth > 0 {
                            if characters[i] == "\"" { i = literal(i + 1).1; continue }
                            if characters[i] == "(" { depth += 1 } else if characters[i] == ")" { depth -= 1 }
                            i += 1
                        }
                        key += "%*"; continue
                    }
                    key += ["n": "\n", "t": "\t", "\"": "\"", "\\": "\\"][characters[i + 1]] ?? String(characters[i + 1]); i += 2; continue
                }
                key.append(characters[i]); i += 1
            }
            return (key, i + 1)
        }
        while index + 2 < characters.count {
            if characters[index] == "L", characters[index + 1] == "(", characters[index + 2] == "\"", index == 0 || !(characters[index - 1].isLetter || characters[index - 1].isNumber || characters[index - 1] == "_") {
                let (key, end) = literal(index + 3); keys.append(key); index = end
            } else { index += 1 }
        }
        return keys
    }
}
