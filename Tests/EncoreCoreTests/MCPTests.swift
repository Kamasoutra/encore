import XCTest
@testable import EncoreCore

final class MCPTests: XCTestCase {
    private func request(_ text: String, call: (String, [String: Any], String) throws -> [String: Any] = { name, args, _ in try MCPTools.validate(name, arguments: args); return MCPTools.content(["ok": true]) }) throws -> [String: Any]? {
        try MCPServer(version: "test").handle(Data(text.utf8), call: call).map { try XCTUnwrap(JSONSerialization.jsonObject(with: $0) as? [String: Any]) }
    }

    func testInitializeToolsAndPing() throws {
        let initialized = try request(#"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"clientInfo":{"name":"Test"}}}"#)
        let result = try XCTUnwrap(initialized?["result"] as? [String: Any])
        XCTAssertEqual(result["protocolVersion"] as? String, "2025-06-18")
        XCTAssertEqual((result["serverInfo"] as? [String: String])?["version"], "test")
        let list = try request(#"{"jsonrpc":"2.0","id":"tools","method":"tools/list"}"#)
        XCTAssertEqual(((list?["result"] as? [String: Any])?["tools"] as? [[String: Any]])?.count, 7)
        XCTAssertNotNil(try request(#"{"jsonrpc":"2.0","id":2,"method":"ping"}"#)?["result"])
    }

    func testInvalidJSONUnknownMethodsAndNotifications() throws {
        XCTAssertEqual((try request("{")?["error"] as? [String: Any])?["code"] as? Int, -32700)
        XCTAssertEqual((try request("[]")?["error"] as? [String: Any])?["code"] as? Int, -32600)
        XCTAssertEqual((try request(#"{"jsonrpc":"2.0","id":1,"method":"missing"}"#)?["error"] as? [String: Any])?["code"] as? Int, -32601)
        XCTAssertEqual((try request(#"{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"missing"}}"#)?["error"] as? [String: Any])?["code"] as? Int, -32602)
        XCTAssertNil(try request(#"{"jsonrpc":"2.0","method":"notifications/initialized"}"#))
        XCTAssertNil(try request(#"{"jsonrpc":"2.0","method":"tools/call","params":{"name":"set_favorite"}}"#) { _, _, _ in XCTFail("Notifications cannot invoke tools"); return [:] })
        XCTAssertEqual((try request(#"{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"recent_clips","arguments":[]}}"#)?["error"] as? [String: Any])?["code"] as? Int, -32602)
    }

    func testEveryToolValidatesItsInputs() throws {
        let id = UUID().uuidString
        let valid: [(String, [String: Any])] = [("search_history", ["query": "app:safari", "limit": 100]), ("recent_clips", ["type": "image"]), ("get_clip", ["id": id, "offset": 100000]), ("list_snippets", ["tag": "work", "language": "Swift"]), ("copy_to_clipboard", ["text": "hello"]), ("copy_to_clipboard", ["id": id]), ("add_snippet", ["text": "hello", "name": "Greeting", "tags": ["work"]]), ("set_favorite", ["id": id, "favorite": true])]
        for (name, arguments) in valid { XCTAssertNoThrow(try MCPTools.validate(name, arguments: arguments), name) }
        let invalid: [(String, [String: Any])] = [("search_history", [:]), ("search_history", ["query": 2]), ("recent_clips", ["limit": true]), ("recent_clips", ["limit": 0]), ("recent_clips", ["limit": 101]), ("recent_clips", ["limit": 1.5]), ("recent_clips", ["type": "pdf"]), ("get_clip", ["id": "oops"]), ("get_clip", ["id": id, "offset": -1]), ("list_snippets", ["tag": []]), ("copy_to_clipboard", [:]), ("copy_to_clipboard", ["text": "x", "id": id]), ("copy_to_clipboard", ["text": ""]), ("add_snippet", ["text": "x"]), ("add_snippet", ["text": "x", "name": "n", "tags": [1]]), ("set_favorite", ["id": id, "favorite": 1]), ("recent_clips", ["unknown": "x"])]
        for (name, arguments) in invalid { XCTAssertThrowsError(try MCPTools.validate(name, arguments: arguments), "\(name): \(arguments)") }
    }

    func testToolExecutionFailureIsAnMCPErrorResult() throws {
        let response = try request(#"{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"get_clip"}}"#) { _, _, _ in
            throw MCPFailure("Clip not found", code: -32004)
        }
        XCTAssertNil(response?["error"])
        XCTAssertEqual((response?["result"] as? [String: Any])?["isError"] as? Bool, true)
    }

    func testClientIdentityStaysInItsSession() throws {
        let server = MCPServer(version: "test")
        _ = server.handle(Data(#"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"clientInfo":{"name":"Inspector"}}}"#.utf8)) { _, _, _ in [:] }
        _ = server.handle(Data(#"{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"recent_clips"}}"#.utf8)) { _, _, client in
            XCTAssertEqual(client, "Inspector"); return [:]
        }
        XCTAssertEqual(MCPServer(version: "test").client, "Unknown")
    }
}
