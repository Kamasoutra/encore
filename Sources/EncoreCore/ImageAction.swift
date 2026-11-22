import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Touch-ups that make a new copy of an image, ready to paste: smaller, in another format, or without its metadata.
/// Every result is encoded afresh from the pixels, so none of them keeps the original's metadata, location included.
public enum ImageAction: String, CaseIterable, Identifiable, Sendable {
    case half, fit1920, jpeg, png, stripMetadata

    public var id: String { rawValue }
    public static let maxPixels = 100_000_000

    /// Whether an image of that size can be decoded: the size is read from its header, before any pixel.
    public static func decodable(width: Int, height: Int) -> Bool {
        width > 0 && height > 0 && width.multipliedReportingOverflow(by: height).partialValue <= maxPixels && width <= maxPixels && height <= maxPixels
    }

    public var title: String {
        switch self {
        case .half: L("Reduce by half")
        case .fit1920: L("Fit within 1920 pixels")
        case .jpeg: L("Convert to JPEG")
        case .png: L("Convert to PNG")
        case .stripMetadata: L("Remove metadata and location")
        }
    }

    public enum Failure: LocalizedError {
        case unreadable, alreadySmall, tooLarge
        public var errorDescription: String? {
            switch self {
            case .unreadable: L("This image could not be read.")
            case .alreadySmall: L("This image is already within that size.")
            case .tooLarge: L("This image is too large to touch up.")
            }
        }
    }

    /// The new image and its type, `public.png` or `public.jpeg`.
    public func apply(_ data: Data) throws -> (data: Data, type: String) {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int, let height = properties[kCGImagePropertyPixelHeight] as? Int else { throw Failure.unreadable }
        // A small file can claim billions of pixels: decoding it would take gigabytes. 100 megapixels is above any camera's photo.
        guard Self.decodable(width: width, height: height) else { throw Failure.tooLarge }
        let longest = max(width, height)
        let target: Int = switch self {
        case .half: max(1, longest / 2)
        case .fit1920: min(longest, 1920)
        default: longest
        }
        if self == .fit1920 && longest <= 1920 { throw Failure.alreadySmall }
        // A thumbnail at full size is the simplest way to get the pixels upright, the orientation applied, and nothing else.
        let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true,
                                        kCGImageSourceThumbnailMaxPixelSize: target, kCGImageSourceShouldCacheImmediately: true]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { throw Failure.unreadable }
        let original = (CGImageSourceGetType(source) as String?) ?? UTType.png.identifier
        let type: UTType = switch self {
        case .jpeg: .jpeg
        case .png: .png
        default: original == UTType.jpeg.identifier ? .jpeg : .png
        }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, type.identifier as CFString, 1, nil) else { throw Failure.unreadable }
        var encoding: [CFString: Any] = [:]
        if type == .jpeg { encoding[kCGImageDestinationLossyCompressionQuality] = 0.85 }
        CGImageDestinationAddImage(destination, type == .jpeg ? Self.opaque(image) ?? image : image, encoding as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw Failure.unreadable }
        return (output as Data, type.identifier)
    }

    /// JPEG has no transparency: transparent areas become white rather than black.
    private static func opaque(_ image: CGImage) -> CGImage? {
        guard image.alphaInfo != .none, image.alphaInfo != .noneSkipLast, image.alphaInfo != .noneSkipFirst,
              let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        let rect = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        context.setFillColor(red: 1, green: 1, blue: 1, alpha: 1)
        context.fill(rect)
        context.draw(image, in: rect)
        return context.makeImage()
    }
}
