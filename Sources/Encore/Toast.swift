import AppKit
import SwiftUI

/// A short message floating over any app, for what happens once encore's panel is gone: a drop or a paste that left something out.
@MainActor enum Toast {
    private static var panel: NSPanel?
    private static var hide: Task<Void, Never>?

    static func show(_ message: String, near point: NSPoint? = nil, hiddenFromSharing: Bool) {
        let panel = panel ?? make()
        Toast.panel = panel
        panel.sharingType = hiddenFromSharing ? .none : .readOnly
        let host = NSHostingView(rootView: ToastView(message: message))
        panel.contentView = host
        let size = host.fittingSize
        let anchor = point ?? NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(anchor) } ?? NSScreen.main ?? NSScreen.screens[0]
        let bounds = screen.visibleFrame
        // Above the pointer, so the message does not cover what was just dropped.
        let x = min(max(anchor.x - size.width / 2, bounds.minX + 8), bounds.maxX - size.width - 8)
        let y = min(max(anchor.y + 28, bounds.minY + 8), bounds.maxY - size.height - 8)
        panel.setFrame(NSRect(x: x, y: y, width: size.width, height: size.height), display: true)
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { $0.duration = 0.18; panel.animator().alphaValue = 1 }
        hide?.cancel()
        hide = Task {
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            guard !Task.isCancelled else { return }
            NSAnimationContext.runAnimationGroup({ $0.duration = 0.35; panel.animator().alphaValue = 0 }) { panel.orderOut(nil) }
        }
    }

    private static func make() -> NSPanel {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = true
        panel.level = .statusBar; panel.hidesOnDeactivate = false; panel.isReleasedWhenClosed = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        return panel
    }
}

private struct ToastView: View {
    let message: String
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "exclamationmark.circle.fill").foregroundStyle(Palette.accent)
            Text(message).font(.system(size: 12.5, weight: .medium)).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: 360, alignment: .leading)
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Palette.accent.opacity(0.45), lineWidth: 1))
        .padding(1)
    }
}

/// Web pages, in a browser or in an app built on one, take files from a drop and only the first file of a paste.
enum WebTarget {
    @MainActor static func app(at screenPoint: NSPoint) -> NSRunningApplication? {
        guard let primary = NSScreen.screens.first else { return nil }
        // Window bounds count from the top of the main screen, AppKit points from its bottom.
        let point = CGPoint(x: screenPoint.x, y: primary.frame.maxY - screenPoint.y)
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        for window in windows {
            guard (window[kCGWindowLayer as String] as? Int) == 0,
                  let pid = window[kCGWindowOwnerPID as String] as? pid_t, pid != ProcessInfo.processInfo.processIdentifier,
                  let bounds = window[kCGWindowBounds as String] as? [String: CGFloat],
                  CGRect(x: bounds["X"] ?? 0, y: bounds["Y"] ?? 0, width: bounds["Width"] ?? 0, height: bounds["Height"] ?? 0).contains(point) else { continue }
            return NSRunningApplication(processIdentifier: pid)
        }
        return nil
    }

    static func isWeb(_ app: NSRunningApplication?) -> Bool {
        guard let app, let url = app.bundleURL else { return false }
        if let id = app.bundleIdentifier, browsers.contains(id) { return true }
        // Slack, Discord, ChatGPT or Claude: Electron apps show web pages, with their rules.
        return FileManager.default.fileExists(atPath: url.appendingPathComponent("Contents/Frameworks/Electron Framework.framework").path)
    }

    private static let browsers: Set<String> = {
        guard let probe = URL(string: "https://example.com") else { return [] }
        return Set(NSWorkspace.shared.urlsForApplications(toOpen: probe).compactMap { Bundle(url: $0)?.bundleIdentifier })
    }()
}
