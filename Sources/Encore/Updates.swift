import AppKit
import Sparkle

/// Sparkle updates from the GitHub release feed; inactive in tests and `swift run`, where no feed is bundled.
/// The demo shows them as on and up to date without running Sparkle: it shares the app and its settings with the real instance, and must never install anything.
@MainActor final class Updates: NSObject, ObservableObject, SPUUpdaterDelegate, @preconcurrency SPUStandardUserDriverDelegate {
    static let shared = Updates()
    private var controller: SPUStandardUpdaterController?
    private var idleWait: Timer?
    private let demo = CommandLine.arguments.contains("--demo")
    private var demoInstalls = true

    private override init() {
        super.init()
        let enabled = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") != nil && !demo
        controller = enabled ? SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: self, userDriverDelegate: self) : nil
        // Checking is always on; the setting only chooses whether updates install without asking.
        controller?.updater.automaticallyChecksForUpdates = true
    }

    var available: Bool { controller != nil || demo }
    var automaticallyInstalls: Bool {
        get { controller?.updater.automaticallyDownloadsUpdates ?? demoInstalls }
        set { if let controller { controller.updater.automaticallyDownloadsUpdates = newValue } else { demoInstalls = newValue }; objectWillChange.send() }
    }
    var lastCheck: Date? { demo ? Date() : controller?.updater.lastUpdateCheckDate }
    static let current = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    /// The newest version the feed offers, once a check has run; the current one when encore is up to date.
    @Published private(set) var latest: String?
    @Published private(set) var probing = false
    var updateFound: Bool { latest.map { $0 != Self.current } ?? false }

    /// Reads the feed without showing anything, to tell whether a newer version exists.
    func probe() {
        if demo { latest = Self.current; return }
        guard let controller, !probing, controller.updater.canCheckForUpdates else { return }
        probing = true
        controller.updater.checkForUpdateInformation()
    }

    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) { latest = item.displayVersionString; probing = false }
    func updaterDidNotFindUpdate(_ updater: SPUUpdater) { latest = Self.current; probing = false }
    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: Error?) { probing = false }

    func check() {
        guard let controller else { probe(); return }
        NSApp.activate(ignoringOtherApps: true)
        controller.checkForUpdates(nil)
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
