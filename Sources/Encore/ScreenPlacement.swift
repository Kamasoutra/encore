import AppKit
import CoreGraphics

enum ScreenPlacement {
    static func displayID(_ screen: NSScreen) -> CGDirectDisplayID? {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }
    static func identifier(_ screen: NSScreen) -> String? {
        guard let id = displayID(screen), let uuid = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue() else { return nil }
        return CFUUIDCreateString(nil, uuid) as String
    }
    static func screen(target: String, screens: [NSScreen], pointer: NSPoint, current: NSScreen?) -> NSScreen? {
        let primary = screens.first { displayID($0) == CGMainDisplayID() } ?? screens.first
        if target == "active" { return current ?? screens.first { $0.frame.contains(pointer) } ?? primary }
        if target == "primary" { return primary }
        return screens.first { identifier($0) == target } ?? primary
    }
}
