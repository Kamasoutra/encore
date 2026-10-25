import EncoreCore
import AppKit

enum SoundTheme: String, Codable, CaseIterable, Identifiable {
    case soft, crystal, retro, custom
    var id: String { rawValue }
    var title: String {
        switch self { case .soft: L("Feutré"); case .crystal: L("Net"); case .retro: L("Boisé"); case .custom: L("Personnalisé") }
    }
    func name(for action: FeedbackSounds.Action) -> String {
        "\(self == .custom ? "soft" : rawValue)-\(action == .capture ? "capture" : "paste")"
    }
}

@MainActor enum FeedbackSounds {
    enum Action { case capture, paste }
    private static var cache: [String: NSSound] = [:]
    static var resources: Bundle {
        if let url = Bundle.main.url(forResource: "Encore_Encore", withExtension: "bundle"), let bundle = Bundle(url: url) { return bundle }
        return .module
    }
    static func bundledURL(_ action: Action, theme: SoundTheme) -> URL? {
        resources.url(forResource: theme.name(for: action), withExtension: "wav", subdirectory: "Sounds")
    }
    @discardableResult static func play(_ action: Action, preferences: Preferences) -> Bool {
        let path = action == .capture ? preferences.captureSoundPath : preferences.pasteSoundPath
        let custom = preferences.soundTheme == .custom ? path.map { URL(fileURLWithPath: $0) } : nil
        let candidates = [custom, bundledURL(action, theme: preferences.soundTheme)].compactMap { $0 }
        guard let sound = candidates.lazy.compactMap({ url -> NSSound? in
            if let sound = cache[url.path] { return sound }
            guard let sound = NSSound(contentsOf: url, byReference: false) else { return nil }
            cache[url.path] = sound
            return sound
        }).first else { return false }
        sound.volume = Float(min(1, max(0, preferences.soundVolume)))
        if sound.isPlaying { sound.stop() }
        return sound.play()
    }
}
