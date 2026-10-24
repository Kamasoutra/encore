import Foundation

struct Preferences: Codable, Equatable {
    var retentionDays = 30
    var historyLimit = 2000
    var storageLimitMB = 500
    var captureEnabled = true
    var ignoreSensitive = true
    var recognizeImages = true
    var excludedBundleIDs = ["com.1password.1password", "com.agilebits.onepassword7", "com.bitwarden.desktop", "com.apple.keychainaccess", "org.keepassxc.keepassxc", "com.dashlane.Dashlane"]
    var panelHeight: Double = 380
    var compact = false
    var appearance = "system"
    var shortcut = "commandShiftV"

    static func load(demo: Bool) -> Preferences {
        guard !demo, let data = UserDefaults.standard.data(forKey: "preferences"), let value = try? JSONDecoder().decode(Self.self, from: data) else { return .init() }
        return value
    }
    func save(demo: Bool) {
        guard !demo, let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults.standard.set(data, forKey: "preferences")
    }
}
