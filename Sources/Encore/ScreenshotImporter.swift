import AppKit
import EncoreCore
import ImageIO

@MainActor final class ScreenshotImporter {
    private unowned let model: AppModel
    private var watcher: ScreenCaptureWatcher?
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
        var created: ScreenCaptureWatcher?
        let watcher = ScreenCaptureWatcher(folder: URL(fileURLWithPath: folder)) { [weak self] url in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self, self.watcher != nil, self.watcher === created else { return }
                    self.enqueue(url)
                }
            }
        }
        created = watcher
        self.watcher = watcher
        if !watcher.start() { model.notify(L("Screenshot monitoring is unavailable for this folder.")) }
    }

    func stop() {
        watcher?.stop(); watcher = nil
        generation = UUID(); seen = []
    }

    func enqueue(_ url: URL) {
        guard model.preferences.importScreenshots, model.preferences.captureEnabled, url.isFileURL, seen.insert(url.path).inserted else { return }
        let currentGeneration = generation
        let clipboardRevision = model.clipboard.revision
        reader.async { [weak self] in
            do {
                let values = try url.resourceValues(forKeys: [.fileSizeKey, .creationDateKey, .isRegularFileKey])
                guard values.isRegularFile == true, let size = values.fileSize, size <= PasteboardCapture.maxBytes else { throw PasteboardCapture.CaptureError.tooLarge }
                let data = try Data(contentsOf: url, options: .mappedIfSafe)
                guard data.count <= PasteboardCapture.maxBytes else { throw PasteboardCapture.CaptureError.tooLarge }
                DispatchQueue.main.async {
                    guard let self, self.generation == currentGeneration else { return }
                    self.importImage(data, url: url, capturedAt: values.creationDate ?? Date(), clipboardRevision: clipboardRevision)
                }
            } catch { DispatchQueue.main.async { self?.model.notify(L("Screenshot skipped: \(error.localizedDescription)")) } }
        }
    }

    func importImage(_ data: Data, url: URL, capturedAt: Date, clipboardRevision: Int? = nil) {
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
        let clip = Clip(fingerprint: payload.fingerprint, kind: .image, text: "", title: url.deletingPathExtension().lastPathComponent, sourceName: L("Screenshot"), sourceBundle: "com.apple.screencaptureui", copiedAt: capturedAt, byteCount: payload.byteCount)
        model.accept(clip, payload: payload)
        guard model.preferences.copyScreenshotsToClipboard else { return }
        let expectedRevision = clipboardRevision ?? model.clipboard.revision
        model.clipboard.poll()
        let currentRevision = model.clipboard.revision
        guard currentRevision == expectedRevision || currentRevision == model.clipboard.automaticScreenshotRevision,
              model.clipboard.lastChangeAt <= capturedAt else { return }
        model.clipboard.write(payload, sourceBundle: "com.apple.screencaptureui", screenshotCapturedAt: capturedAt)
    }
}

/// Finds new screenshots by watching their folder and reading the mark macOS writes on each file.
/// Not through Spotlight: when its index stops updating, which macOS does not report, screenshots would silently stop arriving.
final class ScreenCaptureWatcher: @unchecked Sendable {
    private let folder: URL
    private let since: Date
    private let found: @Sendable (URL) -> Void
    private let queue = DispatchQueue(label: "local.kama.Encore.screenshots.watch", qos: .utility)
    private var source: DispatchSourceFileSystemObject?

    init(folder: URL, since: Date = Date(), found: @escaping @Sendable (URL) -> Void) {
        self.folder = folder; self.since = since; self.found = found
    }

    func start() -> Bool {
        let descriptor = open(folder.path, O_EVTONLY)
        guard descriptor >= 0 else { return false }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor, eventMask: .write, queue: queue)
        source.setEventHandler { [weak self] in
            guard let self else { return }
            // The folder changes when the file appears, but not when its mark is written, just after: look again a little later.
            for delay in [0.3, 2, 5] { self.queue.asyncAfter(deadline: .now() + delay) { [weak self] in self?.scan() } }
        }
        source.setCancelHandler { close(descriptor) }
        source.resume()
        self.source = source
        return true
    }

    func stop() { source?.cancel(); source = nil }

    private func scan() {
        let keys: Set<URLResourceKey> = [.creationDateKey]
        let urls = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: Array(keys), options: .skipsHiddenFiles)) ?? []
        let captures = urls.compactMap { url -> (url: URL, date: Date)? in
            guard let date = (try? url.resourceValues(forKeys: keys))?.creationDate, date >= since, Self.isScreenCapture(url) else { return nil }
            return (url, date)
        }
        for capture in captures.sorted(by: { $0.date < $1.date }) { found(capture.url) }
    }

    static func isScreenCapture(_ url: URL) -> Bool {
        let name = "com.apple.metadata:kMDItemIsScreenCapture"
        let size = getxattr(url.path, name, nil, 0, 0, 0)
        guard size > 0 else { return false }
        var data = Data(count: size)
        let read = data.withUnsafeMutableBytes { getxattr(url.path, name, $0.baseAddress, size, 0, 0) }
        guard read == size, let value = try? PropertyListSerialization.propertyList(from: data, format: nil) else { return false }
        return (value as? NSNumber)?.boolValue == true
    }
}
