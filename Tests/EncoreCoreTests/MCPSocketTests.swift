import XCTest
import Darwin
@testable import EncoreCore

final class MCPSocketTests: XCTestCase {
    func testSocketPermissionsSameUserPersistentSessionAndShutdown() throws {
        let root = URL(fileURLWithPath: "/tmp").appendingPathComponent("Encore-Socket-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: root) }
        let path = root.appendingPathComponent("mcp.sock").path
        let listener = try MCPSocket.Listener(path: path) { data, session, reply in
            reply(session.handle(data) { name, args, client in
                try MCPTools.validate(name, arguments: args)
                return MCPTools.content(["client": client])
            })
        }
        defer { listener.stop() }
        let attrs = try FileManager.default.attributesOfItem(atPath: path)
        XCTAssertEqual((attrs[.posixPermissions] as? NSNumber)?.intValue, 0o600)
        let fd = try MCPSocket.connect(path)
        defer { close(fd) }
        XCTAssertTrue(MCPSocket.sameUser(fd))
        XCTAssertThrowsError(try MCPSocket.Listener(path: path) { _, _, reply in reply(nil) })
        let reader = MCPSocket.Reader(fd)
        try MCPSocket.write(Data(#"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"clientInfo":{"name":"Socket Test"}}}"#.utf8), to: fd)
        XCTAssertNotNil(try reader.line())
        try MCPSocket.write(Data(#"{"jsonrpc":"2.0","method":"notifications/initialized"}"#.utf8), to: fd)
        try MCPSocket.write(Data(#"{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"recent_clips"}}"#.utf8), to: fd)
        let response = try XCTUnwrap(reader.line())
        XCTAssertTrue(String(decoding: response, as: UTF8.self).contains("Socket Test"))
        listener.stop()
        XCTAssertNil(try reader.line())
    }

    func testReaderKeepsCoalescedFramesAndRejectsOversizedInput() throws {
        var fds: [Int32] = [0, 0]
        XCTAssertEqual(pipe(&fds), 0)
        defer { close(fds[0]); close(fds[1]) }
        try MCPSocket.write(Data("first\nsecond".utf8), to: fds[1])
        let reader = MCPSocket.Reader(fds[0], limit: 6)
        XCTAssertEqual(try reader.line(), Data("first".utf8))
        XCTAssertEqual(try reader.line(), Data("second".utf8))
        try MCPSocket.write(Data("too long".utf8), to: fds[1])
        XCTAssertThrowsError(try reader.line())
    }
}
