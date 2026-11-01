import AppKit
import EncoreCore
import Darwin

@MainActor enum MCPCommand {
    private typealias Connection = (fd: Int32, reader: MCPSocket.Reader)

    /// Relays each request to the running app. When encore quits or restarts, after an update or a reinstall, the next request
    /// reconnects, launching it again if needed, and replays the client's initialize so the access log keeps the client's name.
    static func run() {
        let input = MCPSocket.Reader(STDIN_FILENO)
        var connection: Connection?
        var initialize: Data?
        defer { if let connection { close(connection.fd) } }
        do {
            while let line = try input.line() {
                let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any]
                let isInitialize = object?["method"] as? String == "initialize"
                if isInitialize { initialize = line }
                var response: Data??
                for attempt in 0..<2 where response == nil {
                    if attempt > 0, let stale = connection { close(stale.fd); connection = nil }
                    if connection == nil { connection = connect(replaying: isInitialize ? nil : initialize) }
                    guard let current = connection else { break }
                    // Not try?: it would flatten a failure into the nil of a notification.
                    do { response = .some(try relay(line, over: current)) } catch {}
                }
                switch response {
                case .some(.some(let data)): try MCPSocket.write(data, to: STDOUT_FILENO)
                case .some(.none): continue
                case .none:
                    // A notification needs no answer; a request gets the error a client can show.
                    guard object?["id"] != nil else { continue }
                    try MCPSocket.write(MCPServer.error(id: object?["id"] ?? NSNull(), message: L("encore could not start.")), to: STDOUT_FILENO)
                }
            }
        } catch { fputs("encore MCP: input disconnected or message too large\n", stderr) }
    }

    /// The answer to a request, or nil for a notification, which has none.
    private static func relay(_ line: Data, over connection: Connection) throws -> Data? {
        try MCPSocket.write(line, to: connection.fd)
        let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any]
        if object?["id"] == nil, object?["method"] is String { return nil }
        guard let response = try connection.reader.line() else { throw MCPFailure("encore disconnected") }
        return response
    }

    private static func connect(replaying initialize: Data?) -> Connection? {
        var fd = try? MCPSocket.connect()
        let bundle = Bundle.main.bundleURL
        if fd == nil, bundle.pathExtension == "app" {
            let config = NSWorkspace.OpenConfiguration()
            config.activates = false; config.addsToRecentItems = false
            if CommandLine.arguments.contains("--demo") { config.arguments = ["--demo", "--mcp"]; config.createsNewApplicationInstance = true }
            NSWorkspace.shared.openApplication(at: bundle, configuration: config) { _, _ in }
            let deadline = Date().addingTimeInterval(10)
            repeat {
                RunLoop.current.run(until: Date().addingTimeInterval(0.1))
                fd = try? MCPSocket.connect()
            } while fd == nil && Date() < deadline
        }
        guard let fd else { return nil }
        let connection = (fd: fd, reader: MCPSocket.Reader(fd, limit: 32_000_000))
        if let initialize { _ = try? relay(initialize, over: connection) }
        return connection
    }
}

/// The assistants Settings → MCP shows a configuration for, each written the way its own documentation does.
enum MCPConfiguration: String, CaseIterable, Identifiable {
    case claudeCode, claudeDesktop, codex, cursor, vsCode, other
    var id: String { rawValue }
    static var executable: String { Bundle.main.executablePath ?? CommandLine.arguments[0] }

    var title: String {
        switch self {
        case .claudeCode: "Claude Code"
        case .claudeDesktop: "Claude Desktop"
        case .codex: "Codex"
        case .cursor: "Cursor"
        case .vsCode: "VS Code"
        case .other: L("Other")
        }
    }

    var hint: String {
        switch self {
        case .claudeCode, .codex: L("Run in Terminal.")
        case .claudeDesktop: L("Add to Claude Desktop’s configuration: Settings → Developer → Edit Config.")
        case .cursor: L("Add to ~/.cursor/mcp.json.")
        case .vsCode: L("Add to .vscode/mcp.json in a project, or to your user configuration.")
        case .other: L("The command and its argument, for any other MCP client.")
        }
    }

    var value: String {
        let shell = "'" + Self.executable.replacingOccurrences(of: "'", with: "'\"'\"'") + "'"
        let json = (try? JSONSerialization.data(withJSONObject: Self.executable, options: [.fragmentsAllowed, .withoutEscapingSlashes])).flatMap { String(data: $0, encoding: .utf8) } ?? "\"\""
        switch self {
        case .claudeCode: return "claude mcp add encore -- \(shell) mcp"
        case .codex: return "codex mcp add encore -- \(shell) mcp"
        case .claudeDesktop, .cursor: return "{\n  \"mcpServers\": {\n    \"encore\": {\n      \"command\": \(json),\n      \"args\": [\"mcp\"]\n    }\n  }\n}"
        case .vsCode: return "{\n  \"servers\": {\n    \"encore\": {\n      \"type\": \"stdio\",\n      \"command\": \(json),\n      \"args\": [\"mcp\"]\n    }\n  }\n}"
        case .other: return "command: \(Self.executable)\nargs: mcp"
        }
    }
}
