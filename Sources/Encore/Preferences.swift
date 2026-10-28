import Foundation
import EncoreCore

struct Preferences: Codable, Equatable {
    var retentionDays = 30
    var historyLimit = 2000
    var storageLimitMB = 500
    var captureEnabled = true
    var ignoreSensitive = true
    var recognizeImages = true
    private static let legacyDefaultExcludedBundleIDs = ["com.1password.1password", "com.agilebits.onepassword7", "com.bitwarden.desktop", "com.apple.keychainaccess", "org.keepassxc.keepassxc", "com.dashlane.Dashlane"]
    static let defaultExcludedBundleIDs = legacyDefaultExcludedBundleIDs + ["com.apple.Passwords"]
    var excludedBundleIDs: [String] = []
    var disabledDefaultExclusions: [String] = []
    var panelHeight: Double = 380
    var compact = false
    var appearance = "system"
    var shortcut = "commandShiftV"
    var stackShortcutEnabled = false
    var retentionRules: [RetentionRule] = []
    var cardScale: Double = 1
    var importScreenshots = false
    var copyScreenshotsToClipboard = true
    var screenshotFolder: String?
    var soundsEnabled = true
    var soundTheme: SoundTheme = .default
    var soundVolume = 0.2
    var captureSoundPath: String?
    var pasteSoundPath: String?
    var displayTarget = "active"
    var language = "system"
    var shareWithPeers = false
    /// Return and double-click paste into the front app; off, they only make the item the current clipboard.
    var pasteDirectly = true
    /// Merge favorites, and snippets, with paired Macs that sync them too, and keep them in step while connected.
    var syncFavorites = false
    var syncSnippets = false

    var retentionPolicy: RetentionPolicy {
        RetentionPolicy(rules: retentionRules, fallback: retentionDays > 0 ? .init(retentionDays, .days) : .forever)
    }

    init() {}

    private enum CodingKeys: String, CodingKey {
        case retentionDays, historyLimit, storageLimitMB, captureEnabled, ignoreSensitive, recognizeImages
        case excludedBundleIDs, panelHeight, compact, appearance, shortcut, retentionRules, cardScale, importScreenshots, copyScreenshotsToClipboard, screenshotFolder
        case soundsEnabled, soundTheme, soundVolume, captureSoundPath, pasteSoundPath, displayTarget, stackShortcutEnabled, disabledDefaultExclusions, language, shareWithPeers, pasteDirectly, syncFavorites, syncSnippets
    }

    init(from decoder: Decoder) throws {
        self.init()
        let values = try decoder.container(keyedBy: CodingKeys.self)
        retentionDays = try values.decodeIfPresent(Int.self, forKey: .retentionDays) ?? retentionDays
        historyLimit = try values.decodeIfPresent(Int.self, forKey: .historyLimit) ?? historyLimit
        storageLimitMB = try values.decodeIfPresent(Int.self, forKey: .storageLimitMB) ?? storageLimitMB
        captureEnabled = try values.decodeIfPresent(Bool.self, forKey: .captureEnabled) ?? captureEnabled
        ignoreSensitive = try values.decodeIfPresent(Bool.self, forKey: .ignoreSensitive) ?? ignoreSensitive
        recognizeImages = try values.decodeIfPresent(Bool.self, forKey: .recognizeImages) ?? recognizeImages
        excludedBundleIDs = try values.decodeIfPresent([String].self, forKey: .excludedBundleIDs) ?? excludedBundleIDs
        disabledDefaultExclusions = try values.decodeIfPresent([String].self, forKey: .disabledDefaultExclusions)
            ?? (values.contains(.excludedBundleIDs) ? Self.legacyDefaultExcludedBundleIDs.filter { !excludedBundleIDs.contains($0) } : [])
        panelHeight = try values.decodeIfPresent(Double.self, forKey: .panelHeight) ?? panelHeight
        compact = try values.decodeIfPresent(Bool.self, forKey: .compact) ?? compact
        appearance = try values.decodeIfPresent(String.self, forKey: .appearance) ?? appearance
        shortcut = try values.decodeIfPresent(String.self, forKey: .shortcut) ?? shortcut
        stackShortcutEnabled = try values.decodeIfPresent(Bool.self, forKey: .stackShortcutEnabled) ?? false
        retentionRules = try values.decodeIfPresent([RetentionRule].self, forKey: .retentionRules) ?? []
        cardScale = min(1.5, max(0.75, try values.decodeIfPresent(Double.self, forKey: .cardScale) ?? 1))
        importScreenshots = try values.decodeIfPresent(Bool.self, forKey: .importScreenshots) ?? false
        copyScreenshotsToClipboard = try values.decodeIfPresent(Bool.self, forKey: .copyScreenshotsToClipboard) ?? !importScreenshots
        screenshotFolder = try values.decodeIfPresent(String.self, forKey: .screenshotFolder)
        soundsEnabled = try values.decodeIfPresent(Bool.self, forKey: .soundsEnabled) ?? true
        soundTheme = try values.decodeIfPresent(SoundTheme.self, forKey: .soundTheme) ?? .default
        soundVolume = min(1, max(0, try values.decodeIfPresent(Double.self, forKey: .soundVolume) ?? 0.2))
        captureSoundPath = try values.decodeIfPresent(String.self, forKey: .captureSoundPath)
        pasteSoundPath = try values.decodeIfPresent(String.self, forKey: .pasteSoundPath)
        displayTarget = try values.decodeIfPresent(String.self, forKey: .displayTarget) ?? "active"
        language = try values.decodeIfPresent(String.self, forKey: .language) ?? "fr"
        shareWithPeers = try values.decodeIfPresent(Bool.self, forKey: .shareWithPeers) ?? false
        pasteDirectly = try values.decodeIfPresent(Bool.self, forKey: .pasteDirectly) ?? true
        syncFavorites = try values.decodeIfPresent(Bool.self, forKey: .syncFavorites) ?? false
        syncSnippets = try values.decodeIfPresent(Bool.self, forKey: .syncSnippets) ?? false
    }

    static func load(demo: Bool) -> Preferences {
        guard !demo, let data = UserDefaults.standard.data(forKey: "preferences"), let value = try? JSONDecoder().decode(Self.self, from: data) else { return .init() }
        return value
    }

    mutating func reconcileDefaultExclusions(installed: Set<String>) {
        let defaults = Set(Self.defaultExcludedBundleIDs)
        excludedBundleIDs.removeAll { defaults.contains($0) && !installed.contains($0) }
        for id in Self.defaultExcludedBundleIDs where installed.contains(id) && !disabledDefaultExclusions.contains(id) && !excludedBundleIDs.contains(id) {
            excludedBundleIDs.append(id)
        }
    }

    mutating func removeExcludedApp(_ id: String) {
        excludedBundleIDs.removeAll { $0 == id }
        if Self.defaultExcludedBundleIDs.contains(id) && !disabledDefaultExclusions.contains(id) { disabledDefaultExclusions.append(id) }
    }
    func save(demo: Bool) {
        guard !demo, let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults.standard.set(data, forKey: "preferences")
    }
}
