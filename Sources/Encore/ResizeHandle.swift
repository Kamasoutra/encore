import EncoreCore
import AppKit
import SwiftUI

struct ResizeHandle: NSViewRepresentable {
    var onFinish: (Double) -> Void
    func makeNSView(context: Context) -> HandleView { HandleView(onFinish: onFinish) }
    func updateNSView(_ view: HandleView, context: Context) { view.onFinish = onFinish }

    final class HandleView: NSView {
        var onFinish: (Double) -> Void
        private var startFrame: NSRect?
        private var startY: CGFloat = 0

        init(onFinish: @escaping (Double) -> Void) {
            self.onFinish = onFinish
            super.init(frame: .zero)
            setAccessibilityElement(true)
            setAccessibilityRole(.splitter)
            setAccessibilityLabel(L("Redimensionner le panneau"))
        }
        required init?(coder: NSCoder) { nil }
        override func resetCursorRects() { addCursorRect(bounds, cursor: .resizeUpDown) }
        override func draw(_ dirtyRect: NSRect) {
            NSColor.secondaryLabelColor.withAlphaComponent(0.45).setFill()
            NSBezierPath(roundedRect: NSRect(x: bounds.midX - 20, y: bounds.midY - 2, width: 40, height: 4), xRadius: 2, yRadius: 2).fill()
        }
        override func mouseDown(with event: NSEvent) {
            startFrame = window?.frame
            startY = NSEvent.mouseLocation.y
        }
        override func mouseDragged(with event: NSEvent) {
            guard let window, let frame = startFrame else { return }
            let maximum = min(760, (window.screen?.visibleFrame.height ?? 800) - 30)
            let height = max(280, min(maximum, frame.height + NSEvent.mouseLocation.y - startY))
            window.setFrame(NSRect(x: frame.minX, y: frame.minY, width: frame.width, height: height), display: false)
        }
        override func mouseUp(with event: NSEvent) {
            guard startFrame != nil, let window else { return }
            mouseDragged(with: event)
            startFrame = nil
            onFinish(window.frame.height)
        }
    }
}
