import AppKit
import EncoreCore
import ImageIO

@MainActor final class ScreenshotImporter {
    private unowned let model: AppModel
    private var query: NSMetadataQuery?
    private var observers: [NSObjectProtocol] = []
    private var configuration = ""
    private var seen = Set<String>()
    private var generation = UUID()
    private let reader = DispatchQueue(label: "local.kama.Encore.screenshots", qos: .utility)

    init(model: AppModel) { self.model = model }

    static var defaultFolder: URL {
        let location = UserDefaults(suiteName: "com.apple.screencapture")?.string(forKey: "location")
        return location.map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) } ?? FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask)[0]
    }

    func configure() {
        let enabled = model.preferences.importScreenshots && model.preferences.captureEnabled && !model.demo
        let folder = model.preferences.screenshotFolder ?? Self.defaultFolder.path
        let signature = "\(enabled)|\(folder)"
        guard signature != configuration else { return }
        stop(); configuration = signature
        guard enabled else { return }
        let query = NSMetadataQuery()
        query.searchScopes = [folder]
        query.predicate = NSPredicate(format: "kMDItemIsScreenCapture == 1 AND kMDItemFSCreationDate >= %@", Date() as NSDate)
        query.sortDescriptors = [NSSortDescriptor(key: NSMetadataItemFSCreationDateKey, ascending: true)]
        for name in [Notification.Name.NSMetadataQueryDidFinishGathering, .NSMetadataQueryDidUpdate] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: query, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.consume() }
            })
        }
        self.query = query
        if !query.start() { model.notify(L("La surveillance des captures est indisponible pour ce dossier.")) }
    }

    func stop() {
        query?.stop(); query = nil
        observers.forEach { NotificationCenter.default.removeObserver($0) }; observers = []
        generation = UUID(); seen = []
    }

    private func consume() {
        guard let query else { return }
        query.disableUpdates()
        defer { query.enableUpdates() }
        for index in 0..<query.resultCount {
            guard let item = query.result(at: index) as? NSMetadataItem, let path = item.value(forAttribute: NSMetadataItemPathKey) as? String else { continue }
            enqueue(URL(fileURLWithPath: path))
        }
    }

    func enqueue(_ url: URL) {
        guard model.preferences.importScreenshots, model.preferences.captureEnabled, url.isFileURL, seen.insert(url.path).inserted else { return }
        let currentGeneration = generation
        reader.async { [weak self] in
            do {
                let values = try url.resourceValues(forKeys: [.fileSizeKey, .creationDateKey, .isRegularFileKey])
                guard values.isRegularFile == true, let size = values.fileSize, size <= PasteboardCapture.maxBytes else { throw PasteboardCapture.CaptureError.tooLarge }
                let data = try Data(contentsOf: url, options: .mappedIfSafe)
                guard data.count <= PasteboardCapture.maxBytes else { throw PasteboardCapture.CaptureError.tooLarge }
                DispatchQueue.main.async {
                    guard let self, self.generation == currentGeneration else { return }
                    self.importImage(data, url: url, capturedAt: values.creationDate ?? Date())
                }
            } catch { DispatchQueue.main.async { self?.model.notify(L("Capture ignorée : \(error.localizedDescription)")) } }
        }
    }

    func importImage(_ data: Data, url: URL, capturedAt: Date) {
        guard model.preferences.importScreenshots, model.preferences.captureEnabled,
              url.isFileURL, !model.preferences.excludedBundleIDs.contains("com.apple.screencaptureui"), data.count <= PasteboardCapture.maxBytes,
              let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              CGImageSourceGetType(source) != nil, CGImageSourceGetCount(source) > 0 else { return }
        let type: String
        switch url.pathExtension.lowercased() {
        case "png": type = "public.png"
        case "jpg", "jpeg": type = "public.jpeg"
        case "heic", "heif": type = "public.heic"
        case "tif", "tiff": type = "public.tiff"
        default: return
        }
        let payload = ClipPayload(items: [.init([type: data])])
        let clip = Clip(fingerprint: payload.fingerprint, kind: .image, text: "", title: url.deletingPathExtension().lastPathComponent, sourceName: L("Capture d’écran"), sourceBundle: "com.apple.screencaptureui", copiedAt: capturedAt, byteCount: payload.byteCount)
        model.accept(clip, payload: payload)
    }
}
