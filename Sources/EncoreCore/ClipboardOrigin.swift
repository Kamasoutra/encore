import Foundation

public struct ClipboardOrigin: Equatable, Sendable {
    public var bundleID: String
    public var name: String
    public init(bundleID: String, name: String) { self.bundleID = bundleID; self.name = name }
    public static let unknown = ClipboardOrigin(bundleID: "", name: L("Origine inconnue"))
}
