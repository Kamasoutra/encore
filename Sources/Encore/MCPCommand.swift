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
                if CommandLine.arguments.contains("--demo") { config.arguments = ["--demo"]; config.createsNewApplicationInstance = true }
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

@MainActor enum MCPConfiguration {
    static var executable: String { Bundle.main.executablePath ?? CommandLine.arguments[0] }
    static var claudeCode: String { "claude mcp add encore -- " + "'" + executable.replacingOccurrences(of: "'", with: "'\"'\"'") + "' mcp" }
    static var claudeDesktop: String {
        let value = ["mcpServers": ["encore": ["command": executable, "args": ["mcp"]] as [String: Any]]]
        return (try? JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
    }
}
