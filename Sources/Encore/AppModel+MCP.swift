import AppKit
import ImageIO
import EncoreCore

extension AppModel {
    var mcpLogURL: URL? { storage?.root.appendingPathComponent("mcp-log.json") }

    func loadMCPLog() {
        guard let url = mcpLogURL, let data = try? Data(contentsOf: url), let entries = try? JSONDecoder().decode([MCPLogEntry].self, from: data) else { return }
        mcpLog = Array(entries.suffix(200))
    }

    func startMCP() {
        guard mcpListener == nil, storage != nil else { return }
        do {
            mcpListener = try MCPSocket.Listener(path: MCPSocket.path) { [weak self] line, session, reply in
                Task { @MainActor in
                    guard let self else { reply(nil); return }
                    let result = session.handle(line) { name, arguments, client in try self.mcpCall(name, arguments: arguments, client: client) }
                    if !self.preferences.mcpEnabled, let result, let object = try? JSONSerialization.jsonObject(with: result) as? [String: Any], object["result"] != nil {
                        reply(MCPServer.error(id: object["id"] ?? NSNull(), message: L("Enable MCP Server in Settings → MCP.")))
                    } else { reply(result) }
                }
            }
        } catch { fputs("encore MCP: socket unavailable\n", stderr) }
    }

    func clearMCPLog() { mcpLog = []; saveMCPLog() }

    private func saveMCPLog() {
        guard let url = mcpLogURL else { return }
        do {
            let data = try JSONEncoder().encode(mcpLog)
            try data.write(to: url, options: [.atomic])
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        } catch { fputs("encore MCP: could not save access log\n", stderr) }
    }

    private func mcpVisible(_ clip: Clip) -> Bool {
        preferences.mcpAllowSecrets || (clip.secret == nil && SecretKind.detect(plainText(of: clip)) == nil && SecretKind.detect(clip.recognizedText) == nil)
    }

    private func mcpClip(_ arguments: [String: Any]) throws -> Clip {
        guard let value = arguments["id"] as? String, let id = UUID(uuidString: value), let clip = library.clips.first(where: { $0.id == id }), mcpVisible(clip) else { throw MCPFailure("Clip not found", code: -32004) }
        return clip
    }

    private func mcpMetadata(_ clip: Clip) -> [String: Any] {
        ["id": clip.id.uuidString, "type": clip.kind.rawValue, "sourceApp": clip.sourceName, "sourceBundle": clip.sourceBundle,
         "copiedAt": ISO8601DateFormatter().string(from: clip.copiedAt), "firstCopiedAt": ISO8601DateFormatter().string(from: clip.firstCopyDate),
         "favorite": clip.favorite, "name": clip.name, "byteCount": clip.byteCount, "snippet": clip.snippet,
         "preview": String(plainText(of: clip).prefix(200))]
    }

    func mcpCall(_ name: String, arguments: [String: Any], client: String) throws -> [String: Any] {
        var summary = L("Request refused")
        defer {
            mcpLog.append(MCPLogEntry(client: String(client.prefix(100)), tool: MCPTools.names.contains(name) ? name : "unknown", summary: summary))
            mcpLog = Array(mcpLog.suffix(200)); saveMCPLog()
        }
        guard preferences.mcpEnabled else { throw MCPFailure(L("Enable MCP Server in Settings → MCP."), code: -32001) }
        try MCPTools.validate(name, arguments: arguments)
        switch name {
        case "search_history", "recent_clips":
            let query = ClipQuery(query: arguments["query"] as? String ?? "", kind: (arguments["type"] as? String).flatMap(ClipKind.init(rawValue:)))
            let limit = arguments["limit"] as? Int ?? (name == "recent_clips" ? 10 : 20)
            let matches = library.clips.filter { clip in
                guard mcpVisible(clip) else { return false }
                var searchable = clip; searchable.text = plainText(of: clip)
                return query.matches(searchable)
            }.sorted {
                if name == "search_history", query.matchesName($0) != query.matchesName($1) { return query.matchesName($0) }
                return $0.copiedAt > $1.copiedAt
            }
            let result = Array(matches.prefix(limit))
            summary = L("Results: \(Localization.number(result.count))")
            return MCPTools.content(result.map(mcpMetadata))
        case "list_snippets":
            let tag = (arguments["tag"] as? String)?.lowercased()
            let language = (arguments["language"] as? String).map { CodeLanguage.named($0)?.name ?? $0 }
            let matches = Clip.snippetBoardOrder(library.clips.filter { clip in
                clip.snippet && mcpVisible(clip) && (tag == nil || clip.tags.contains(tag!)) && (language == nil || clip.language?.lowercased() == language?.lowercased())
            })
            summary = L("Results: \(Localization.number(matches.count))")
            return MCPTools.content(matches.map { clip -> [String: Any] in
                var value = mcpMetadata(clip)
                value["language"] = clip.language ?? ""; value["tags"] = clip.tags
                let text = plainText(of: clip)
                let regex = try? NSRegularExpression(pattern: #"\{\{([^{}]+)\}\}"#)
                var seen = Set<String>()
                value["variables"] = regex?.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { match -> String? in
                    guard let range = Range(match.range(at: 1), in: text) else { return nil }
                    let field = String(text[range]); return seen.insert(field).inserted ? field : nil
                } ?? []
                return value
            })
        case "get_clip":
            let clip = try mcpClip(arguments)
            var metadata = mcpMetadata(clip)
            let text = (clip.kind == .image || clip.kind == .file) && !clip.recognizedText.isEmpty ? clip.recognizedText : plainText(of: clip)
            let offset = min(arguments["offset"] as? Int ?? 0, text.count)
            let page = String(text.dropFirst(offset).prefix(100_000))
            metadata["text"] = page; metadata["offset"] = offset; metadata["totalCharacters"] = text.count
            metadata["truncated"] = offset + page.count < text.count
            metadata["tags"] = clip.tags; metadata["language"] = clip.language ?? ""
            if clip.kind == .file {
                metadata["files"] = fileURLs(for: clip).map { url -> [String: Any] in
                    let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize
                    return ["path": url.path, "size": size.map { $0 as Any } ?? NSNull()]
                }
                metadata["referencedFileBytes"] = clip.referencedFileBytes.map { $0 as Any } ?? NSNull()
            }
            var result = MCPTools.content(metadata)
            if clip.kind == .image {
                guard let payload = storage?.payload(clip.id), let data = payload.items.lazy.compactMap({ item in
                    ["public.png", "public.tiff", "public.jpeg", "public.heic"].compactMap { item.representations[$0] }.first
                }).first, let source = CGImageSourceCreateWithData(data as CFData, nil),
                      let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: 1568] as CFDictionary),
                      let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else { throw MCPFailure("Image unavailable", code: -32004) }
                var content = result["content"] as? [[String: Any]] ?? []
                content.append(["type": "image", "mimeType": "image/png", "data": png.base64EncodedString()]); result["content"] = content
            }
            summary = L("Copy read")
            return result
        case "copy_to_clipboard":
            let clip: Clip
            if let text = arguments["text"] as? String {
                guard addText(text), let added = library.clips.first(where: { $0.fingerprint == ClipPayload.text(text).fingerprint }) else { throw MCPFailure("Could not save copy", code: -32000) }
                clip = added
            } else { clip = try mcpClip(arguments) }
            guard let payload = storage?.payload(clip.id) else { throw MCPFailure("Content unavailable", code: -32004) }
            clipboard.write(payload, sourceBundle: clip.sourceBundle)
            if let index = library.clips.firstIndex(where: { $0.id == clip.id }) {
                library.clips[index].firstCopiedAt = clip.firstCopyDate
                library.clips[index].copiedAt = Date(); library.clips[index].lastUsedAt = Date()
                library.clips.sort { $0.copiedAt > $1.copiedAt }; save(); reconcileSelection()
            }
            summary = L("Copied to clipboard")
            return MCPTools.content(["id": clip.id.uuidString, "copied": true])
        case "add_snippet":
            let text = arguments["text"] as! String
            guard addText(text), let clip = library.clips.first(where: { $0.fingerprint == ClipPayload.text(text).fingerprint }) else { throw MCPFailure("Could not save snippet", code: -32000) }
            let tags = Clip.tags(from: (arguments["tags"] as? [String] ?? []).joined(separator: ","))
            let language = (arguments["language"] as? String).map { CodeLanguage.named($0)?.name ?? $0 }
            updateSnippet(clip.id, name: arguments["name"] as! String, tags: tags, language: language, snippet: true)
            summary = L("Snippet saved")
            return MCPTools.content(["id": clip.id.uuidString])
        case "set_favorite":
            let clip = try mcpClip(arguments)
            let favorite = arguments["favorite"] as! Bool
            if clip.favorite != favorite { toggleFavorite([clip.id]) }
            summary = L("Favorite updated")
            return MCPTools.content(["id": clip.id.uuidString, "favorite": favorite])
        default: throw MCPFailure("Unknown tool")
        }
    }
}
