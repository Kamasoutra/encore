import Foundation

public enum Localization {
    public static let catalog = ["en", "fr", "de", "es", "it", "pt-BR", "nl", "sv", "da", "nb", "fi", "pl", "cs", "sk", "ro", "hu", "el", "ru", "uk", "tr", "ja", "ko", "zh-Hans", "zh-Hant", "ar", "he", "hi", "id", "vi", "th"]
    public static let supported: [String] = catalog.filter { folders[$0.lowercased()] != nil }
    /// Table folders by lowercased code: some SwiftPM versions bundle "zh-Hans.lproj" as "zh-hans.lproj".
    private static let folders: [String: URL] = {
        let root = resources.resourceURL ?? resources.bundleURL
        let names = (try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []
        let tables = names.filter { $0.hasSuffix(".lproj") && FileManager.default.fileExists(atPath: root.appendingPathComponent("\($0)/Localizable.strings").path) }
        return Dictionary(tables.map { (String($0.dropLast(6)).lowercased(), root.appendingPathComponent($0)) }, uniquingKeysWith: { first, _ in first })
    }()
    private static let lock = NSLock()
    private static var selection = "system"
    private static var tables: [String: Bundle] = [:]
    public static var language: String {
        get { lock.lock(); defer { lock.unlock() }; return selection }
        set { lock.lock(); selection = supported.contains(newValue) ? newValue : "system"; lock.unlock() }
    }
    public static var identifier: String {
        let selected = language
        return selected == "system" ? resolve(Locale.preferredLanguages) : selected
    }
    public static func resolve(_ preferences: [String]) -> String {
        Bundle.preferredLocalizations(from: supported, forPreferences: preferences).first.flatMap { supported.contains($0) ? $0 : nil } ?? supported.first ?? "en"
    }
    public static var locale: Locale { Locale(identifier: identifier) }
    public static var isRightToLeft: Bool { Locale.characterDirection(forLanguage: identifier) == .rightToLeft }
    public static func nativeName(_ code: String) -> String { capitalized(Locale(identifier: code).localizedString(forIdentifier: code) ?? code, code) }
    public static func displayName(_ code: String) -> String { capitalized(locale.localizedString(forIdentifier: code) ?? code, identifier) }
    private static func capitalized(_ name: String, _ code: String) -> String { name.prefix(1).uppercased(with: Locale(identifier: code)) + name.dropFirst() }
    public static var resources: Bundle {
        if let url = Bundle.main.url(forResource: "Encore_EncoreCore", withExtension: "bundle"), let bundle = Bundle(url: url) { return bundle }
        return .module
    }
    public static func table(_ code: String) -> Bundle {
        lock.lock(); defer { lock.unlock() }
        if let bundle = tables[code] { return bundle }
        let bundle = folders[code.lowercased()].flatMap(Bundle.init(url:)) ?? resources
        tables[code] = bundle
        return bundle
    }
    public static func text(_ value: String.LocalizationValue) -> String {
        let code = identifier
        return String(localized: value, bundle: table(code), locale: Locale(identifier: code))
    }

    public static func keys(_ glyphs: String) -> String { "\u{2066}\(glyphs)\u{2069}" }
    public static func step(rightArrow: Bool, rightToLeft: Bool = isRightToLeft) -> Int { rightArrow != rightToLeft ? 1 : -1 }
    public static func date(_ date: Date, time: Bool = true) -> String { date.formatted(Date.FormatStyle(date: .numeric, time: time ? .standard : .omitted, locale: locale)) }
    public static func bytes(_ count: Int64) -> String { count.formatted(.byteCount(style: .file).locale(locale)) }
    public static func number(_ value: Int) -> String { value.formatted(.number.locale(locale)) }
    public static func relative(_ date: Date, to now: Date) -> String {
        let age = max(0, now.timeIntervalSince(date))
        if age < 60 { return L("Just now") }
        guard age < 604800 else { return Localization.date(date, time: false) }
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = locale
        formatter.calendar = calendar
        formatter.unitsStyle = .short
        let components = age < 3600 ? DateComponents(minute: -Int(age / 60)) : age < 86400 ? DateComponents(hour: -Int(age / 3600)) : DateComponents(day: -Int(age / 86400))
        return formatter.localizedString(from: components)
    }
    public static func duration(_ seconds: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.calendar = calendar
        formatter.allowedUnits = [.day, .hour, .minute]
        formatter.maximumUnitCount = 1
        formatter.unitsStyle = .abbreviated
        return formatter.string(from: seconds) ?? ""
    }
    /// "42 s", in the selected language: the last minute before something expires.
    public static func seconds(_ seconds: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.calendar = calendar
        formatter.allowedUnits = [.second]
        formatter.unitsStyle = .short
        return formatter.string(from: max(1, seconds.rounded(.up))) ?? ""
    }
    private static var calendar: Calendar { var calendar = Calendar.current; calendar.locale = locale; return calendar }
}

public func L(_ value: String.LocalizationValue) -> String { Localization.text(value) }
