import AppKit
import EncoreCore
import Darwin

@MainActor enum MCPCommand {
    static func run() {
        let input = MCPSocket.Reader(STDIN_FILENO)
        var fd: Int32?
        var failure: String?
        do { fd = try MCPSocket.connect() }
        catch {
            let bundle = Bundle.main.bundleURL
            if bundle.pathExtension == "app" {
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
            if fd == nil { failure = L("encore could not start.") }
        }
        defer { if let fd { close(fd) } }
        let reader = fd.map { MCPSocket.Reader($0, limit: 32_000_000) }
        do {
            while let line = try input.line() {
                if let fd, let reader, failure == nil {
                    do {
                        try MCPSocket.write(line, to: fd)
                        let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any]
                        if object?["id"] == nil, object?["method"] is String { continue }
                        guard let response = try reader.line() else { throw MCPFailure("encore disconnected") }
                        try MCPSocket.write(response, to: STDOUT_FILENO)
                        continue
                    } catch { failure = L("encore could not start.") }
                }
                let response = MCPServer(version: "0").handle(line) { _, _, _ in [:] }
                if let response, let object = try? JSONSerialization.jsonObject(with: response) as? [String: Any] {
                    try MCPSocket.write(MCPServer.error(id: object["id"] ?? NSNull(), message: failure ?? L("encore could not start.")), to: STDOUT_FILENO)
                }
            }
        } catch { fputs("encore MCP: input disconnected or message too large\n", stderr) }
    }
}

/// The assistants Settings → MCP shows a configuration for, each written the way its own documentation does.
@MainActor enum MCPConfiguration: String, CaseIterable, Identifiable {
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
