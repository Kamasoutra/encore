import Foundation
import CoreFoundation

public struct MCPFailure: Error {
    public let code: Int
    public let message: String
    public init(_ message: String, code: Int = -32602) { self.message = message; self.code = code }
}

public enum MCPTools {
    private static let string: [String: Any] = ["type": "string"]
    private static let id: [String: Any] = ["type": "string", "format": "uuid"]
    private static let limit: [String: Any] = ["type": "integer", "minimum": 1, "maximum": 100]
    public static let names = ["search_history", "recent_clips", "get_clip", "list_snippets", "copy_to_clipboard", "add_snippet", "set_favorite"]
    public static var definitions: [[String: Any]] {
        func tool(_ name: String, _ description: String, _ properties: [String: Any], _ required: [String] = []) -> [String: Any] {
            var schema: [String: Any] = ["type": "object", "properties": properties, "required": required, "additionalProperties": false]
            if name == "copy_to_clipboard" { schema["oneOf"] = [["required": ["text"]], ["required": ["id"]]] }
            return ["name": name, "description": description, "inputSchema": schema, "annotations": ["readOnlyHint": ["search_history", "recent_clips", "get_clip", "list_snippets"].contains(name), "destructiveHint": false, "openWorldHint": false]]
        }
        return [
            tool("search_history", "Search clipboard history. Supports app:, type:, tag:, lang:, date:, after: and before: filters.", ["query": string, "limit": limit], ["query"]),
            tool("recent_clips", "List recent copies, newest first, optionally filtered by type.", ["limit": limit, "type": ["type": "string", "enum": ClipKind.allCases.map(\.rawValue)]]),
            tool("get_clip", "Read a copy's full content. Text pages contain at most 100000 characters; use offset for the next page.", ["id": id, "offset": ["type": "integer", "minimum": 0]], ["id"]),
            tool("list_snippets", "List saved snippets and template variables, optionally filtered by tag or language.", ["tag": string, "language": string]),
            tool("copy_to_clipboard", "Put literal text or an existing copy on the clipboard. Does not paste into another app.", ["text": string, "id": id]),
            tool("add_snippet", "Save text as a named snippet with optional language and tags.", ["text": string, "name": string, "language": string, "tags": ["type": "array", "items": string, "maxItems": 12]], ["text", "name"]),
            tool("set_favorite", "Set a copy's favorite state.", ["id": id, "favorite": ["type": "boolean"]], ["id", "favorite"])
        ]
    }

    public static func validate(_ name: String, arguments: [String: Any]) throws {
        guard let definition = definitions.first(where: { $0["name"] as? String == name }), let schema = definition["inputSchema"] as? [String: Any], let properties = schema["properties"] as? [String: [String: Any]] else { throw MCPFailure("Unknown tool", code: -32602) }
        let required = schema["required"] as? [String] ?? []
        guard required.allSatisfy({ arguments[$0] != nil }), arguments.keys.allSatisfy({ properties[$0] != nil }) else { throw MCPFailure("Missing or unknown argument") }
        for (key, value) in arguments {
            let type = properties[key]?["type"] as? String
            switch type {
            case "string":
                guard let text = value as? String, text.utf8.count <= 1_000_000 else { throw MCPFailure("Invalid string argument") }
                if key == "id", UUID(uuidString: text) == nil { throw MCPFailure("Invalid clip id") }
                if ["text", "name"].contains(key), text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { throw MCPFailure("Empty argument") }
                if key == "type", ClipKind(rawValue: text) == nil { throw MCPFailure("Unknown clip type") }
            case "integer":
                guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(), number.doubleValue.isFinite, number.doubleValue.rounded() == number.doubleValue,
                      number.doubleValue >= 0, number.doubleValue <= Double(Int.max / 2) else { throw MCPFailure("Invalid integer argument") }
                if key == "limit", !(1...100).contains(number.intValue) { throw MCPFailure("Limit must be between 1 and 100") }
            case "boolean":
                guard let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() else { throw MCPFailure("Invalid boolean argument") }
            case "array":
                guard let tags = value as? [String], tags.count <= 12, tags.allSatisfy({ $0.utf8.count <= 1000 }) else { throw MCPFailure("Invalid tags") }
            default: throw MCPFailure("Invalid argument")
            }
        }
        if name == "copy_to_clipboard", (arguments["text"] != nil) == (arguments["id"] != nil) { throw MCPFailure("Provide text or id, exclusively") }
    }

    public static func content(_ value: Any) -> [String: Any] {
        let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .fragmentsAllowed])
        return ["content": [["type": "text", "text": data.flatMap { String(data: $0, encoding: .utf8) } ?? "{}"]]]
    }
}

public final class MCPServer {
    public private(set) var client = "Unknown"
    private let version: String
    public init(version: String) { self.version = version }

    public func handle(_ data: Data, call: (String, [String: Any], String) throws -> [String: Any]) -> Data? {
        var request: [String: Any]
        do {
            let object = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
            guard let value = object as? [String: Any] else { return Self.error(id: NSNull(), code: -32600, message: "Invalid request") }
            request = value
        } catch { return Self.error(id: NSNull(), code: -32700, message: "Parse error") }
        let id = request["id"] ?? NSNull()
        guard request["jsonrpc"] as? String == "2.0", let method = request["method"] as? String,
              request["id"] == nil || id is String || (id is NSNumber && CFGetTypeID(id as! NSNumber) != CFBooleanGetTypeID()) else {
            return Self.error(id: NSNull(), code: -32600, message: "Invalid request")
        }
        guard request["id"] != nil else { return nil }
        do {
            if let params = request["params"], !(params is [String: Any]) { throw MCPFailure("Invalid params") }
            let params = request["params"] as? [String: Any] ?? [:]
            let result: [String: Any]
            switch method {
            case "initialize":
                if let info = params["clientInfo"] as? [String: Any], let name = info["name"] as? String { client = String(name.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) }.prefix(100)) }
                result = ["protocolVersion": "2025-06-18", "capabilities": ["tools": [:] as [String: Any]], "serverInfo": ["name": "encore", "version": version]]
            case "ping": result = [:]
            case "tools/list": result = ["tools": MCPTools.definitions]
            case "tools/call":
                guard let name = params["name"] as? String else { throw MCPFailure("Missing tool name") }
                if let arguments = params["arguments"], !(arguments is [String: Any]) { throw MCPFailure("Invalid arguments") }
                let arguments = params["arguments"] as? [String: Any] ?? [:]
                do { result = try call(name, arguments, client) }
                catch let failure as MCPFailure where (-32099 ... -32000).contains(failure.code) {
                    result = ["isError": true, "content": [["type": "text", "text": failure.message]]]
                }
            default: throw MCPFailure("Method not found", code: -32601)
            }
            return try JSONSerialization.data(withJSONObject: ["jsonrpc": "2.0", "id": id, "result": result], options: [.sortedKeys])
        } catch let error as MCPFailure { return Self.error(id: id, code: error.code, message: error.message) }
        catch { return Self.error(id: id, code: -32603, message: "Internal error") }
    }

    public static func error(id: Any = NSNull(), code: Int = -32603, message: String) -> Data {
        (try? JSONSerialization.data(withJSONObject: ["jsonrpc": "2.0", "id": id, "error": ["code": code, "message": message]], options: [.sortedKeys])) ?? Data()
    }
}

public struct MCPLogEntry: Codable, Identifiable {
    public var id = UUID()
    public var date = Date()
    public var client: String
    public var tool: String
    public var summary: String
    public init(client: String, tool: String, summary: String) { self.client = client; self.tool = tool; self.summary = summary }
}
