import EncoreCore
import AppKit

enum SoundTheme: String, Codable, CaseIterable, Identifiable {
    case paper, piano, marimba, glass, drop, bubble, soft, crystal, retro, custom
    static let `default`: SoundTheme = .paper
    var id: String { rawValue }
    var title: String {
        switch self {
        case .paper: L("Papier"); case .piano: L("Piano"); case .marimba: L("Marimba"); case .glass: L("Verre")
        case .drop: L("Goutte"); case .bubble: L("Bulle")
        case .soft: L("Feutré"); case .crystal: L("Net"); case .retro: L("Boisé"); case .custom: L("Personnalisé")
        }
    }
    func name(for action: FeedbackSounds.Action) -> String {
        "\(self == .custom ? SoundTheme.default.rawValue : rawValue)-\(action == .capture ? "capture" : "paste")"
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
    /// Plays a theme without selecting it; `sequence` replays real use: two copies, then a paste.
    static func preview(_ theme: SoundTheme, action: Action? = nil, preferences: Preferences) {
        var preferences = preferences
        preferences.soundTheme = theme
        if let action { play(action, preferences: preferences); return }
        play(.capture, preferences: preferences)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { play(.capture, preferences: preferences) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { play(.paste, preferences: preferences) }
    }
}
