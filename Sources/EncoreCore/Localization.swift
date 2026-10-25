import Foundation

public enum Localization {
    private static let lock = NSLock()
    private static var selection = "system"
    public static var language: String {
        get { lock.lock(); defer { lock.unlock() }; return selection }
        set { lock.lock(); selection = ["fr", "en"].contains(newValue) ? newValue : "system"; lock.unlock() }
    }
    public static var identifier: String {
        let selected = language
        return selected == "system" ? (Bundle.preferredLocalizations(from: ["fr", "en"]).first ?? "en") : selected
    }
    public static var locale: Locale { Locale(identifier: identifier) }
    public static var resources: Bundle {
        if let url = Bundle.main.url(forResource: "Encore_EncoreCore", withExtension: "bundle"), let bundle = Bundle(url: url) { return bundle }
        return .module
    }
    public static func text(_ value: String.LocalizationValue) -> String {
        let bundle = resources.path(forResource: identifier, ofType: "lproj").flatMap(Bundle.init(path:)) ?? resources
        return String(localized: value, bundle: bundle, locale: locale)
    }
}

public func L(_ value: String.LocalizationValue) -> String { Localization.text(value) }
