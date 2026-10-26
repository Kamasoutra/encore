import AppKit
import EncoreCore

@MainActor enum DemoFixtures {
    /// Demo content follows the launch language, so French campaign captures are French throughout.
    static let french = Locale.preferredLanguages.first?.hasPrefix("fr") == true
    static func text(_ english: String, _ french: String) -> String { Self.french ? french : english }

    static func create(in directory: URL) throws -> [URL] {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let png = directory.appendingPathComponent(text("A good idea.png", "Une bonne idée.png"))
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 900, pixelsHigh: 1100, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        NSGradient(starting: NSColor(red: 0.21, green: 0.12, blue: 0.51, alpha: 1), ending: NSColor(red: 0.93, green: 0.45, blue: 0.32, alpha: 1))!.draw(in: NSRect(x: 0, y: 0, width: 900, height: 1100), angle: 55)
        NSColor.white.withAlphaComponent(0.12).setFill()
        NSBezierPath(ovalIn: NSRect(x: 230, y: 410, width: 900, height: 900)).fill()
        NSColor.white.withAlphaComponent(0.1).setFill()
        NSBezierPath(ovalIn: NSRect(x: -330, y: -220, width: 750, height: 750)).fill()
        (text("GOOD\nIDEAS\nCOME\nBACK.", "LES\nBONNES\nIDÉES\nREVIENNENT.") as NSString).draw(in: NSRect(x: 80, y: 190, width: 740, height: 710), withAttributes: [.font: NSFont.systemFont(ofSize: french ? 96 : 116, weight: .bold), .foregroundColor: NSColor.white])
        (text("ENCORE  /  KEEP WHAT MATTERS", "ENCORE  /  GARDEZ L’ESSENTIEL") as NSString).draw(at: NSPoint(x: 83, y: 90), withAttributes: [.font: NSFont.systemFont(ofSize: 23, weight: .medium), .foregroundColor: NSColor.white.withAlphaComponent(0.8)])
        NSGraphicsContext.restoreGraphicsState()
        try bitmap.representation(using: .png, properties: [:])!.write(to: png)

        let pdf = directory.appendingPathComponent(text("Project notes.pdf", "Notes de projet.pdf"))
        var page = CGRect(x: 0, y: 0, width: 600, height: 800)
        guard let context = CGContext(pdf as CFURL, mediaBox: &page, nil) else { throw CocoaError(.fileWriteUnknown) }
        context.beginPDFPage(nil)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        NSColor.white.setFill(); NSRect(x: 0, y: 0, width: 600, height: 800).fill()
        NSColor(red: 0.55, green: 0.36, blue: 0.93, alpha: 1).setFill(); NSRect(x: 42, y: 698, width: 44, height: 5).fill()
        (text("Project notes", "Notes de projet") as NSString).draw(at: NSPoint(x: 42, y: 638), withAttributes: [.font: NSFont.systemFont(ofSize: 34, weight: .bold), .foregroundColor: NSColor.black])
        (text("GOOD IDEAS DESERVE TO STAY.", "LES BONNES IDÉES MÉRITENT DE RESTER.") as NSString).draw(at: NSPoint(x: 43, y: 607), withAttributes: [.font: NSFont.systemFont(ofSize: 11, weight: .medium), .foregroundColor: NSColor.gray])
        let titles: [String] = french ? ["01  Capturer sans interruption", "02  Retrouver en un instant", "03  Garder l’essentiel", "04  Reprendre le fil"] : ["01  Capture without interruption", "02  Find it in an instant", "03  Keep what matters", "04  Pick up the thread"]
        for (index, title) in titles.enumerated() {
            let y = CGFloat(505 - index * 110)
            (title as NSString).draw(at: NSPoint(x: 43, y: y), withAttributes: [.font: NSFont.systemFont(ofSize: 18, weight: .semibold), .foregroundColor: NSColor.darkGray])
            for line in 0..<3 {
                NSColor(white: 0.91, alpha: 1).setFill()
                NSRect(x: 43, y: y - 18 - CGFloat(line * 11), width: CGFloat(line == 2 ? 320 : 490), height: 4).fill()
            }
        }
        NSGraphicsContext.restoreGraphicsState()
        context.endPDFPage(); context.closePDF()
        return [png, pdf]
    }

    static func richText() throws -> (String, ClipPayload) {
        let title = text("Good ideas\ndeserve an encore.", "Les bonnes idées\nreviennent encore.")
        let body = title + text("\n\nA thought at the right time.\nA quote worth keeping.\nThe detail that changes everything.", "\n\nUne pensée au bon moment.\nUne citation à garder.\nLe détail qui change tout.")
        let value = NSMutableAttributedString(string: body, attributes: [.font: NSFont.systemFont(ofSize: 15), .foregroundColor: NSColor.labelColor])
        value.addAttributes([.font: NSFont(name: "Georgia-Bold", size: 23) ?? NSFont.systemFont(ofSize: 23, weight: .bold)], range: (body as NSString).range(of: title))
        let rtf = try value.data(from: NSRange(location: 0, length: value.length), documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])
        return (body, ClipPayload(items: [.init([NSPasteboard.PasteboardType.string.rawValue: Data(body.utf8), NSPasteboard.PasteboardType.rtf.rawValue: rtf])]))
    }
}
