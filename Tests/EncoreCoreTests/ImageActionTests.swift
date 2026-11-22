import XCTest
import ImageIO
import UniformTypeIdentifiers
@testable import EncoreCore

final class ImageActionTests: XCTestCase {
    /// A 400×300 JPEG with a location, as a phone would write it.
    private func photo() throws -> Data {
        let context = try XCTUnwrap(CGContext(data: nil, width: 400, height: 300, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(red: 0.2, green: 0.5, blue: 0.9, alpha: 1); context.fill(CGRect(x: 0, y: 0, width: 400, height: 300))
        let image = try XCTUnwrap(context.makeImage())
        let data = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil))
        let gps: [CFString: Any] = [kCGImagePropertyGPSLatitude: 48.85, kCGImagePropertyGPSLatitudeRef: "N", kCGImagePropertyGPSLongitude: 2.35, kCGImagePropertyGPSLongitudeRef: "E"]
        CGImageDestinationAddImage(destination, image, [kCGImagePropertyGPSDictionary: gps] as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return data as Data
    }

    private func info(_ data: Data) throws -> (width: Int, height: Int, type: String, gps: Bool) {
        let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
        let properties = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        return (properties[kCGImagePropertyPixelWidth] as? Int ?? 0, properties[kCGImagePropertyPixelHeight] as? Int ?? 0,
                CGImageSourceGetType(source) as String? ?? "", properties[kCGImagePropertyGPSDictionary] != nil)
    }

    func testTouchUpsResizeConvertAndDropTheLocation() throws {
        let original = try photo()
        XCTAssertTrue(try info(original).gps, "The test photo carries a location")

        let half = try ImageAction.half.apply(original)
        let halfInfo = try info(half.data)
        XCTAssertEqual([halfInfo.width, halfInfo.height], [200, 150])
        XCTAssertEqual(half.type, UTType.jpeg.identifier, "A JPEG stays a JPEG")
        XCTAssertFalse(halfInfo.gps)

        let png = try ImageAction.png.apply(original)
        XCTAssertEqual(png.type, UTType.png.identifier)
        XCTAssertEqual(try info(png.data).type, UTType.png.identifier)
        XCTAssertEqual(try info(png.data).width, 400)

        let jpeg = try ImageAction.jpeg.apply(png.data)
        XCTAssertEqual(try info(jpeg.data).type, UTType.jpeg.identifier)

        let clean = try ImageAction.stripMetadata.apply(original)
        XCTAssertFalse(try info(clean.data).gps)
        XCTAssertEqual(try info(clean.data).width, 400)

        XCTAssertThrowsError(try ImageAction.fit1920.apply(original), "Already within 1920 pixels")
        XCTAssertThrowsError(try ImageAction.half.apply(Data("not an image".utf8)))
    }

    func testAnImageClaimingTooManyPixelsIsRefusedBeforeDecoding() {
        XCTAssertTrue(ImageAction.decodable(width: 8_000, height: 6_000))
        XCTAssertFalse(ImageAction.decodable(width: 20_000, height: 20_000))
        XCTAssertFalse(ImageAction.decodable(width: Int.max, height: 2), "No overflow")
        XCTAssertFalse(ImageAction.decodable(width: 0, height: 10))
    }
}
