import XCTest
import CryptoKit
@testable import Encore

final class HistoryKeyTests: XCTestCase {
    private var realService = ""

    override func setUp() {
        realService = HistoryKey.service
        HistoryKey.service = "local.kama.Encore.history.test-\(UUID().uuidString)"
    }

    override func tearDown() {
        HistoryKey.delete()
        HistoryKey.service = realService
    }

    func testTheKeyIsKeptInTheKeychainUntilItIsDeleted() throws {
        XCTAssertNil(try HistoryKey.read(), "No key means no encryption")
        let created = try HistoryKey.create()
        let read = try XCTUnwrap(try HistoryKey.read())
        XCTAssertEqual(read.withUnsafeBytes { Data($0) }, created.withUnsafeBytes { Data($0) })
        HistoryKey.delete()
        XCTAssertNil(try HistoryKey.read())
    }

    func testAKeyIsNeverReplacedSinceFilesSealedWithItWouldBeLost() throws {
        let first = try HistoryKey.create()
        XCTAssertThrowsError(try HistoryKey.create())
        let kept = try XCTUnwrap(try HistoryKey.read())
        XCTAssertEqual(kept.withUnsafeBytes { Data($0) }, first.withUnsafeBytes { Data($0) })
    }
}
