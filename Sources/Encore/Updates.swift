import AppKit
import Sparkle

/// Sparkle updates from the GitHub release feed; inactive in demo mode, tests and `swift run`, where no feed is bundled.
@MainActor final class Updates: NSObject, ObservableObject, SPUUpdaterDelegate, @preconcurrency SPUStandardUserDriverDelegate {
    static let shared = Updates()
    private var controller: SPUStandardUpdaterController?
    private var idleWait: Timer?

    private override init() {
        super.init()
        let enabled = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") != nil && !CommandLine.arguments.contains("--demo")
        controller = enabled ? SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: self, userDriverDelegate: self) : nil
        // Checking is always on; the setting only chooses whether updates install without asking.
        controller?.updater.automaticallyChecksForUpdates = true
    }

    var available: Bool { controller != nil }
    var automaticallyInstalls: Bool {
        get { controller?.updater.automaticallyDownloadsUpdates ?? false }
        set { controller?.updater.automaticallyDownloadsUpdates = newValue; objectWillChange.send() }
    }
    var lastCheck: Date? { controller?.updater.lastUpdateCheckDate }

    func check() {
        NSApp.activate(ignoringOtherApps: true)
        controller?.checkForUpdates(nil)
    }

    /// encore rarely quits, so an update downloaded in the background would wait for the next quit.
    /// It is installed instead, and encore relaunched, as soon as none of its windows is open.
    func updater(_ updater: SPUUpdater, willInstallUpdateOnQuit item: SUAppcastItem, immediateInstallationBlock immediateInstallHandler: @escaping () -> Void) -> Bool {
        idleWait?.invalidate()
        let install = { [weak self] in
            guard !NSApp.windows.contains(where: { $0.isVisible && $0.canBecomeKey }) else { return }
            self?.idleWait?.invalidate()
            immediateInstallHandler()
        }
        idleWait = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { _ in MainActor.assumeIsolated { install() } }
        install()
        return true
    }

    /// encore has no Dock icon, so an update found by a scheduled check would open its window behind other apps: bring it forward.
    var supportsGentleScheduledUpdateReminders: Bool { true }

    func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState) {
        if handleShowingUpdate && !state.userInitiated { NSApp.activate(ignoringOtherApps: true) }
    }
}
