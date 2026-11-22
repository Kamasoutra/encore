import EncoreCore
import AppKit

enum SoundTheme: String, Codable, CaseIterable, Identifiable {
    case paper, piano, marimba, glass, drop, bubble, soft, crystal, retro, custom
    static let `default`: SoundTheme = .paper
    var id: String { rawValue }
    var title: String {
        switch self {
        case .paper: L("Paper"); case .piano: L("Piano"); case .marimba: L("Marimba"); case .glass: L("Glass")
        case .drop: L("Drop"); case .bubble: L("Bubble")
        case .soft: L("Soft"); case .crystal: L("Crisp"); case .retro: L("Wood"); case .custom: L("Custom")
        }
    }
    func name(for action: FeedbackSounds.Action) -> String {
        "\(self == .custom ? SoundTheme.default.rawValue : rawValue)-\(action == .capture ? "capture" : "paste")"
    }
}

@MainActor enum FeedbackSounds {
    enum Action { case capture, paste }
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
        guard !candidates.isEmpty else { return false }
        SoundPlayer.shared.play(candidates, volume: Float(min(1, max(0, preferences.soundVolume))))
        return true
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

/// Starting a sleeping output device (an HDMI screen, Bluetooth headphones) blocks `NSSound.play` for a second or more, so sounds play on their own queue and never hold up a paste.
private final class SoundPlayer: @unchecked Sendable {
    static let shared = SoundPlayer()
    private let queue = DispatchQueue(label: "local.kama.Encore.sounds", qos: .userInitiated)
    private var cache: [String: NSSound] = [:] // only touched on `queue`

    func play(_ candidates: [URL], volume: Float) {
        let asked = DispatchTime.now()
        queue.async { [self] in
            // Behind a device that took seconds to start, a late sound would only confuse: it is dropped.
            guard DispatchTime.now().uptimeNanoseconds - asked.uptimeNanoseconds < 500_000_000 else { return }
            guard let sound = candidates.lazy.compactMap({ url -> NSSound? in
                if let sound = self.cache[url.path] { return sound }
                guard let sound = NSSound(contentsOf: url, byReference: false) else { return nil }
                self.cache[url.path] = sound
                return sound
            }).first else { return }
            sound.volume = volume
            if sound.isPlaying { sound.stop() }
            sound.play()
        }
    }
}
