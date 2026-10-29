import AppKit

/// Where the compact window sits: its size for a number of rows, its place on a screen,
/// and the pull of the snapping points while it is dragged.
enum CompactPlacement {
    static let width: CGFloat = 360
    static let rowHeight: CGFloat = 62
    static let rowSpacing: CGFloat = 6
    /// The header, search field, library bar, footer and padding around the rows.
    static let chrome: CGFloat = 160
    /// Distance kept from the edges of the screen.
    static let margin: CGFloat = 10

    static func size(rows: Int, in frame: NSRect) -> NSSize {
        let rows = CGFloat(rows)
        return NSSize(width: width, height: min(frame.height - 2 * margin, rows * rowHeight + (rows - 1) * rowSpacing + chrome))
    }

    /// The window at a saved position: from 0 to 1 across the room the screen leaves it, so it lands at the same spot on any screen.
    static func frame(position: [Double], rows: Int, in frame: NSRect) -> NSRect {
        let size = size(rows: rows, in: frame)
        let position = position + [1, 0.5].dropFirst(position.count)
        let roomX = frame.width - 2 * margin - size.width, roomY = frame.height - 2 * margin - size.height
        return NSRect(x: frame.minX + margin + roomX * min(1, max(0, position[0])), y: frame.minY + margin + roomY * min(1, max(0, position[1])),
                      width: size.width, height: size.height)
    }

    /// The saved position of a window frame on a screen.
    static func position(of window: NSRect, in frame: NSRect) -> [Double] {
        let roomX = max(1, frame.width - 2 * margin - window.width), roomY = max(1, frame.height - 2 * margin - window.height)
        return [min(1, max(0, (window.minX - frame.minX - margin) / roomX)), min(1, max(0, (window.minY - frame.minY - margin) / roomY))]
    }

    static let reach: CGFloat = 48
    static let hold: CGFloat = 6

    /// The center, the corners and the middle of each edge draw the window in rather than make it jump:
    /// within `reach` it lags towards the point, more as it gets closer, and holds still within `hold`.
    static func attract(_ origin: NSPoint, size: NSSize, in frame: NSRect) -> NSPoint {
        func axis(_ value: CGFloat, _ low: CGFloat, _ high: CGFloat) -> CGFloat {
            guard let anchor = [low, (low + high) / 2, high].min(by: { abs($0 - value) < abs($1 - value) }), abs(value - anchor) < reach else { return value }
            let pull = max(0, abs(value - anchor) - hold) / (reach - hold)
            return anchor + (value < anchor ? -1 : 1) * reach * pull * pull
        }
        return NSPoint(x: axis(origin.x, frame.minX + margin, frame.maxX - margin - size.width), y: axis(origin.y, frame.minY + margin, frame.maxY - margin - size.height))
    }
}
