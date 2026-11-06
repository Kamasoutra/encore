import AppKit
import QuickLookThumbnailing
import SwiftUI
import EncoreCore
import UniformTypeIdentifiers

@MainActor final class FilePreviews: ObservableObject {
    struct Key: Hashable { let id: UUID; let url: URL }
    @Published private(set) var images: [Key: NSImage] = [:]
    private var dates: [Key: Date] = [:]
    private var requests: [Key: QLThumbnailGenerator.Request] = [:]
    private var tokens: [Key: UUID] = [:]

    func image(_ clip: Clip, url: URL) -> NSImage? { images[Key(id: clip.id, url: url)] }

    func request(_ clip: Clip, url: URL) {
        let key = Key(id: clip.id, url: url)
        guard url.isFileURL, dates[key] != clip.copiedAt else { return }
        if let old = requests.removeValue(forKey: key) { QLThumbnailGenerator.shared.cancel(old) }
        dates[key] = clip.copiedAt
        images.removeValue(forKey: key)
        let request = QLThumbnailGenerator.Request(fileAt: url, size: CGSize(width: 360, height: 360), scale: 2, representationTypes: .thumbnail)
        requests[key] = request
        let token = UUID()
        tokens[key] = token
        QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { [weak self] representation, _ in
            let cg = representation?.cgImage
            DispatchQueue.main.async {
                guard let self, self.tokens[key] == token else { return }
                self.requests.removeValue(forKey: key)
                guard let cg else { return }
                if self.images.count >= 40, let oldest = self.images.keys.first { self.images.removeValue(forKey: oldest); self.dates.removeValue(forKey: oldest) }
                self.images[key] = NSImage(cgImage: cg, size: .zero)
            }
        }
    }

    func remove(_ ids: Set<UUID>) {
        images = images.filter { !ids.contains($0.key.id) }
        dates = dates.filter { !ids.contains($0.key.id) }
        tokens = tokens.filter { !ids.contains($0.key.id) }
        for (key, request) in requests where ids.contains(key.id) {
            requests.removeValue(forKey: key)
            QLThumbnailGenerator.shared.cancel(request)
        }
    }
}

/// One file: its thumbnail, or its icon until there is one.
private struct FileThumbnail: View {
    @ObservedObject var previews: FilePreviews
    let clip: Clip
    let url: URL?
    let fitContent: Bool
    var body: some View {
        ZStack {
            Color(nsColor: .textBackgroundColor).opacity(0.5)
            if let url, let image = previews.image(clip, url: url) {
                if !fitContent {
                    GeometryReader { geometry in Image(nsImage: image).resizable().scaledToFill().frame(width: geometry.size.width, height: geometry.size.height, alignment: .top).clipped() }
                } else { Image(nsImage: image).resizable().scaledToFit().padding(8) }
            }
            else if let url { Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().scaledToFit().frame(maxWidth: 64, maxHeight: 64).padding(6) }
            else { Image(systemName: "doc").font(.system(size: 42)).foregroundStyle(.secondary) }
        }.task(id: clip.copiedAt) { if let url { previews.request(clip, url: url) } }
    }
}

/// Every file of a copy: side by side on a card, and with their names where there is room.
struct FilePreview: View {
    @ObservedObject var previews: FilePreviews
    let clip: Clip
    let urls: [URL]
    var fitContent = false
    var body: some View {
        if urls.count < 2 { FileThumbnail(previews: previews, clip: clip, url: urls.first, fitContent: fitContent) }
        else if fitContent { gallery }
        else { mosaic }
    }

    private func thumbnail(_ index: Int) -> some View {
        FileThumbnail(previews: previews, clip: clip, url: urls[index], fitContent: false)
    }

    private var mosaic: some View {
        VStack(spacing: 2) {
            HStack(spacing: 2) { thumbnail(0); thumbnail(1) }
            if urls.count > 2 {
                HStack(spacing: 2) {
                    thumbnail(2)
                    if urls.count > 3 {
                        thumbnail(3).overlay {
                            if urls.count > 4 {
                                ZStack {
                                    Color.black.opacity(0.55)
                                    Text("+\(Localization.number(urls.count - 3))").font(.system(size: 15, weight: .semibold, design: .rounded)).foregroundStyle(.white)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private var gallery: some View {
        GeometryReader { geometry in
            let columns = min(urls.count, 3)
            let rows = (urls.count + columns - 1) / columns
            let height = rows == 1 ? geometry.size.height - 16 : max(180, (geometry.size.height - 26) / 2)
            ScrollView(rows > 2 ? .vertical : []) {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: columns), spacing: 10) {
                    ForEach(urls.indices, id: \.self) { index in
                        VStack(spacing: 6) {
                            FileThumbnail(previews: previews, clip: clip, url: urls[index], fitContent: true).clipShape(RoundedRectangle(cornerRadius: 8))
                            Text(urls[index].lastPathComponent).font(.system(size: 11, weight: .medium)).lineLimit(1).truncationMode(.middle).help(urls[index].lastPathComponent)
                        }.frame(height: height)
                    }
                }.padding(8)
            }
        }
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
        // No line limit: the frame already clips, and a limit shorter than the view
        // made TextKit loop forever on rich text with tables (HTML emails).
        view.isVerticallyResizable = false
        view.isHorizontallyResizable = false
        view.setAccessibilityElement(false)
        return view
    }
    func updateNSView(_ view: NSTextView, context: Context) {
        guard context.coordinator.text !== text || context.coordinator.scale != scale else { return }
        context.coordinator.text = text; context.coordinator.scale = scale
        view.textStorage?.setAttributedString(Self.styled(text, scale: scale))
    }

    /// Keeps the source layout but bounds font sizes and follows the system appearance.
    static func styled(_ text: NSAttributedString, scale: Double) -> NSAttributedString {
        let copy = NSMutableAttributedString(attributedString: text)
        let range = NSRange(location: 0, length: copy.length)
        text.enumerateAttribute(.font, in: range) { value, span, _ in
            guard let font = value as? NSFont else { return }
            let size = min(36, max(12, font.pointSize)) * scale
            copy.addAttribute(.font, value: NSFontManager.shared.convert(font, toSize: size), range: span)
        }
        copy.addAttribute(.foregroundColor, value: NSColor.labelColor, range: range)
        copy.removeAttribute(.backgroundColor, range: range)
        return copy
    }

    final class PreviewTextView: NSTextView {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}

/// Scrollable, selectable rich text for large previews.
struct ScrollingRichText: NSViewRepresentable {
    let text: NSAttributedString
    var scale: Double = 1
    final class Coordinator { var text: NSAttributedString?; var scale = 0.0 }
    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        scroll.drawsBackground = false
        scroll.autohidesScrollers = true
        let view = scroll.documentView as! NSTextView
        view.isEditable = false
        view.isSelectable = true
        view.drawsBackground = false
        view.textContainerInset = NSSize(width: 14, height: 14)
        view.textContainer?.lineFragmentPadding = 0
        return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard context.coordinator.text !== text || context.coordinator.scale != scale else { return }
        context.coordinator.text = text; context.coordinator.scale = scale
        (scroll.documentView as? NSTextView)?.textStorage?.setAttributedString(RichTextPreview.styled(text, scale: scale))
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
        // Copies encore makes itself (a new text, a merge, a color, an assistant's text) have no source app: they show encore.
        if bundleID.isEmpty || bundleID == Bundle.main.bundleIdentifier {
            value = .init(name: "Encore", icon: NSApp.applicationIconImage)
        } else if let url = installedURL(bundleID) {
            value = .init(name: FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: ""), icon: NSWorkspace.shared.icon(forFile: url.path))
        } else {
            value = .init(name: names[bundleID] ?? bundleID.split(separator: ".").last.map(String.init) ?? L("App"), icon: NSImage(systemSymbolName: "app.dashed", accessibilityDescription: nil)!)
        }
        cache[bundleID] = value
        return value
    }
}
