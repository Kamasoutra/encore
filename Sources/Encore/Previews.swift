import AppKit
import QuickLookThumbnailing
import SwiftUI
import EncoreCore
import UniformTypeIdentifiers

@MainActor final class FilePreviews: ObservableObject {
    @Published private(set) var images: [UUID: NSImage] = [:]
    private var dates: [UUID: Date] = [:]
    private var requests: [UUID: QLThumbnailGenerator.Request] = [:]
    private var tokens: [UUID: UUID] = [:]

    func request(_ clip: Clip, urls: [URL]) {
        guard let url = urls.first, url.isFileURL, dates[clip.id] != clip.copiedAt else { return }
        if let old = requests.removeValue(forKey: clip.id) { QLThumbnailGenerator.shared.cancel(old) }
        dates[clip.id] = clip.copiedAt
        images.removeValue(forKey: clip.id)
        let request = QLThumbnailGenerator.Request(fileAt: url, size: CGSize(width: 360, height: 360), scale: 2, representationTypes: .thumbnail)
        requests[clip.id] = request
        let token = UUID()
        tokens[clip.id] = token
        QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { [weak self] representation, _ in
            let cg = representation?.cgImage
            DispatchQueue.main.async {
                guard let self, self.tokens[clip.id] == token else { return }
                self.requests.removeValue(forKey: clip.id)
                guard let cg else { return }
                if self.images.count >= 40, let id = self.images.keys.first { self.images.removeValue(forKey: id); self.dates.removeValue(forKey: id) }
                self.images[clip.id] = NSImage(cgImage: cg, size: .zero)
            }
        }
    }

    func remove(_ ids: Set<UUID>) {
        for id in ids {
            images.removeValue(forKey: id)
            dates.removeValue(forKey: id)
            tokens.removeValue(forKey: id)
            if let request = requests.removeValue(forKey: id) { QLThumbnailGenerator.shared.cancel(request) }
        }
    }
}

struct FilePreview: View {
    @ObservedObject var previews: FilePreviews
    let clip: Clip
    let urls: [URL]
    var fitContent = false
    private var isImage: Bool { urls.first.flatMap { UTType(filenameExtension: $0.pathExtension) }?.conforms(to: .image) == true }
    var body: some View {
        ZStack {
            Color(nsColor: .textBackgroundColor).opacity(0.5)
            if let image = previews.images[clip.id] {
                if !fitContent {
                    GeometryReader { geometry in Image(nsImage: image).resizable().scaledToFill().frame(width: geometry.size.width, height: geometry.size.height, alignment: .top).clipped() }
                } else { Image(nsImage: image).resizable().scaledToFit().padding(8) }
            }
            else if let url = urls.first { Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().scaledToFit().frame(width: 64, height: 64) }
            else { Image(systemName: "doc").font(.system(size: 42)).foregroundStyle(.secondary) }
        }.task(id: clip.copiedAt) { previews.request(clip, urls: urls) }
    }
}

struct RichTextPreview: NSViewRepresentable {
    let text: NSAttributedString
    var scale: Double = 1
    final class Coordinator { var text: NSAttributedString?; var scale = 0.0 }
    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSTextView {
        let view = PreviewTextView()
        view.isEditable = false
        view.isSelectable = false
        view.drawsBackground = false
        view.textContainerInset = NSSize(width: 14, height: 14)
        view.textContainer?.lineFragmentPadding = 0
        view.textContainer?.widthTracksTextView = true
        view.textContainer?.maximumNumberOfLines = 30
        view.textContainer?.lineBreakMode = .byTruncatingTail
        view.isVerticallyResizable = false
        view.isHorizontallyResizable = false
        view.setAccessibilityElement(false)
        return view
    }
    func updateNSView(_ view: NSTextView, context: Context) {
        guard context.coordinator.text !== text || context.coordinator.scale != scale else { return }
        context.coordinator.text = text; context.coordinator.scale = scale
        let copy = NSMutableAttributedString(attributedString: text)
        let range = NSRange(location: 0, length: copy.length)
        text.enumerateAttribute(.font, in: range) { value, span, _ in
            guard let font = value as? NSFont else { return }
            let size = min(36, max(12, font.pointSize)) * scale
            copy.addAttribute(.font, value: NSFontManager.shared.convert(font, toSize: size), range: span)
        }
        copy.addAttribute(.foregroundColor, value: NSColor.labelColor, range: range)
        copy.removeAttribute(.backgroundColor, range: range)
        view.textStorage?.setAttributedString(copy)
    }

    final class PreviewTextView: NSTextView {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}

struct AppPresentation {
    var name: String
    var icon: NSImage
}

@MainActor enum ApplicationCatalog {
    private static var cache: [String: AppPresentation] = [:]
    static func installedURL(_ bundleID: String) -> URL? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID), FileManager.default.fileExists(atPath: url.path) else { return nil }
        return url
    }
    static func invalidate() { cache.removeAll() }
    static func app(_ bundleID: String) -> AppPresentation {
        if let existing = cache[bundleID] { return existing }
        let names = ["com.1password.1password": "1Password", "com.agilebits.onepassword7": "1Password 7", "com.bitwarden.desktop": "Bitwarden", "com.apple.keychainaccess": L("Keychain Access"), "org.keepassxc.keepassxc": "KeePassXC", "com.dashlane.Dashlane": "Dashlane"]
        let value: AppPresentation
        if let url = installedURL(bundleID) {
            value = .init(name: FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: ""), icon: NSWorkspace.shared.icon(forFile: url.path))
        } else {
            value = .init(name: names[bundleID] ?? bundleID.split(separator: ".").last.map(String.init) ?? L("App"), icon: NSImage(systemSymbolName: "app.dashed", accessibilityDescription: nil)!)
        }
        cache[bundleID] = value
        return value
    }
}
