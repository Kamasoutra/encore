import AppKit

enum SoundTheme: String, Codable, CaseIterable, Identifiable {
    case soft, crystal, retro, custom
    var id: String { rawValue }
    var title: String {
        switch self { case .soft: "Doux"; case .crystal: "Cristal"; case .retro: "Rétro"; case .custom: "Personnalisé" }
    }
    func name(for action: FeedbackSounds.Action) -> String {
        switch (self, action) {
        case (.crystal, .capture): "Glass"
        case (.crystal, .paste): "Ping"
        case (.retro, .capture): "Funk"
        case (.retro, .paste): "Morse"
        case (_, .capture): "Pop"
        case (_, .paste): "Tink"
        }
    }
}

@MainActor enum FeedbackSounds {
    enum Action { case capture, paste }
    @discardableResult static func play(_ action: Action, preferences: Preferences) -> Bool {
        let path = action == .capture ? preferences.captureSoundPath : preferences.pasteSoundPath
        let custom = preferences.soundTheme == .custom ? path.flatMap { NSSound(contentsOfFile: $0, byReference: true) } : nil
        let sound = custom ?? NSSound(named: NSSound.Name(preferences.soundTheme.name(for: action)))
        guard let sound else { return false }
        sound.volume = Float(min(1, max(0, preferences.soundVolume)))
        if sound.isPlaying { sound.stop() }
        return sound.play()
    }
}
