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
}
