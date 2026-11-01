import XCTest
@testable import EncoreCore

final class TransformTests: XCTestCase {
    func testCleanURLRemovesTrackingButPreservesFunctionalParametersAndFragment() throws {
        XCTAssertEqual(try TextAction.cleanURL.apply("https://example.com/path?utm_source=news&q=swift&fbclid=123#read"), "https://example.com/path?q=swift#read")
        XCTAssertEqual(try TextAction.cleanURL.apply("https://example.com/?utm_campaign=hello"), "https://example.com/")
        XCTAssertThrowsError(try TextAction.cleanURL.apply("hello world"))
    }

    func testJSONTransformsPreserveValues() throws {
        let original = "{\"b\":[1,true,null],\"a\":\"été\"}"
        let pretty = try TextAction.prettyJSON.apply(original)
        XCTAssertTrue(pretty.contains("\n"))
        let compact = try TextAction.compactJSON.apply(pretty)
        XCTAssertEqual(try JSONSerialization.jsonObject(with: Data(original.utf8)) as? NSDictionary, try JSONSerialization.jsonObject(with: Data(compact.utf8)) as? NSDictionary)
        XCTAssertThrowsError(try TextAction.prettyJSON.apply("not JSON"))
    }

    func testBase64UnicodeRoundTripAndInvalidData() throws {
        let text = "Bonjour 👋 à bientôt"
        XCTAssertEqual(try TextAction.base64Decode.apply(TextAction.base64Encode.apply(text)), text)
        XCTAssertThrowsError(try TextAction.base64Decode.apply("%%%"))
        XCTAssertThrowsError(try TextAction.base64Decode.apply("/w=="))
    }

    func testColorsConvertBetweenFormats() {
        XCTAssertEqual(ColorFormat.rgb.format("#A78BFA"), "rgb(167, 139, 250)")
        XCTAssertEqual(ColorFormat.hsl.format("#A78BFA"), "hsl(255, 92%, 76%)")
        XCTAssertEqual(ColorFormat.swiftUI.format("#A78BFA"), "Color(red: 0.655, green: 0.545, blue: 0.980)")
        XCTAssertEqual(ColorFormat.hex.format("#fff"), "#FFFFFF")
        XCTAssertEqual(ColorFormat.rgb.format("#FF000080"), "rgba(255, 0, 0, 0.5)")
        XCTAssertEqual(ColorFormat.hex.format("#FF000080"), "#FF000080")
        XCTAssertNil(ColorFormat.rgb.format("not a color"))
    }

    func testColorsCopiedInAnyFormatAreColors() {
        for (text, format) in [("#A78BFA", ColorFormat.hex), ("rgb(167, 139, 250)", .rgb), ("rgba(167 139 250 / 50%)", .rgb), ("hsl(255, 92%, 76%)", .hsl),
                               ("HSLA(255deg 92% 76% / 0.5)", .hsl), ("Color(red: 0.655, green: 0.545, blue: 0.980)", .swiftUI), ("Color(.sRGB, red: 1, green: 0, blue: 0, opacity: 0.5)", .swiftUI)] {
            XCTAssertEqual(ColorFormat.of(text), format, text)
            XCTAssertEqual(ClipKind.detect(text: text), .color, text)
        }
        XCTAssertEqual(ColorFormat.hex.format("rgb(167, 139, 250)"), "#A78BFA")
        XCTAssertEqual(ColorFormat.hex.format("hsl(255, 92%, 76%)"), "#A689FA")  // HSL in whole numbers rounds a little
        XCTAssertEqual(ColorFormat.hex.format("Color(red: 0.655, green: 0.545, blue: 0.980)"), "#A78BFA")
        XCTAssertEqual(ColorFormat.rgb.format("rgba(255, 0, 0, 50%)"), "rgba(255, 0, 0, 0.5)")
        for text in ["rgb(300, 0, 0)", "rgb(1, 2)", "hsl(10, 200%, 50%)", "Color(red: 2, green: 0, blue: 0)", "#GGHHII", "rgb(1, 2, 3) and more", "call rgb(1,2,3)"] {
            XCTAssertNil(ColorFormat.of(text), text)
        }
    }
}
