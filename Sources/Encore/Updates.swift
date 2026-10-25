import AppKit
import Sparkle

/// Sparkle updates from the GitHub release feed; inactive in demo mode, tests and `swift run`, where no feed is bundled.
@MainActor final class Updates: ObservableObject {
    static let shared = Updates()
    private let controller: SPUStandardUpdaterController?

    private init() {
        let enabled = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") != nil && !CommandLine.arguments.contains("--demo")
        controller = enabled ? SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil) : nil
    }

    var available: Bool { controller != nil }
    var automaticallyChecks: Bool {
        get { controller?.updater.automaticallyChecksForUpdates ?? false }
        set { controller?.updater.automaticallyChecksForUpdates = newValue; objectWillChange.send() }
    }
    var lastCheck: Date? { controller?.updater.lastUpdateCheckDate }

    func check() {
        NSApp.activate(ignoringOtherApps: true)
        controller?.checkForUpdates(nil)
    }
}
