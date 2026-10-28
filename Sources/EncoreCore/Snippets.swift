import Foundation

extension Clip {
    /// Keeps the name, tags and language of an incoming copy of the same content where this item has none.
    public mutating func adoptSnippetDetails(of other: Clip) {
        if name.isEmpty { name = String(other.name.prefix(100)) }
        tags = Array((tags + other.tags.filter { !tags.contains($0) }).prefix(12))
        if language == nil { language = other.language }
        snippet = snippet || other.snippet
    }

    /// Snippets are grouped by language for code, then by their first tag.
    public var snippetGroup: String {
        if let language, !language.isEmpty { return language }
        return tags.sorted().first.map { "#\($0)" } ?? ""
    }
}

/// A language a snippet can be filed under. Icons and colors come from the Seti icon theme (MIT), the default file icons of VS Code.
public struct CodeLanguage: Hashable, Identifiable {
    public let name: String
    /// Name of the icon in the app's Languages resources.
    public let icon: String
    /// sRGB color, 0xRRGGBB.
    public let color: UInt32
    public let aliases: [String]
    public var id: String { name }

    init(_ name: String, icon: String, color: UInt32, aliases: [String]) {
        self.name = name; self.icon = icon; self.color = color; self.aliases = aliases
    }

    /// The language stored under this name or one of its aliases, ignoring case.
    public static func named(_ value: String?) -> CodeLanguage? {
        guard let value = value?.lowercased(), !value.isEmpty else { return nil }
        return all.first { $0.name.lowercased() == value } ?? all.first { $0.aliases.contains(value) }
    }

    /// Languages for a filter typed by the user: exact name or alias first, then prefixes, then other matches.
    public static func search(_ query: String) -> [CodeLanguage] {
        let query = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty else { return all }
        func rank(_ language: CodeLanguage) -> Int? {
            let names = [language.name.lowercased()] + language.aliases
            if names.contains(query) { return 0 }
            if names.contains(where: { $0.hasPrefix(query) }) { return 1 }
            if language.name.lowercased().contains(query) { return 2 }
            return nil
        }
        return all.compactMap { language in rank(language).map { ($0, language) } }.sorted { $0.0 < $1.0 }.map(\.1)
    }

    public static let all: [CodeLanguage] = [
        .init("Assembly", icon: "asm", color: 0xCC3E44, aliases: ["asm", "s", "nasm"]),
        .init("Bash", icon: "shell", color: 0x8DC149, aliases: ["sh", "shell", "zsh"]),
        .init("Batch", icon: "windows", color: 0x519ABA, aliases: ["cmd", "bat"]),
        .init("Bicep", icon: "bicep", color: 0x519ABA, aliases: []),
        .init("C", icon: "c", color: 0x519ABA, aliases: ["h"]),
        .init("C#", icon: "c-sharp", color: 0x519ABA, aliases: ["csharp", "cs"]),
        .init("C++", icon: "cpp", color: 0x519ABA, aliases: ["cpp", "cxx", "hpp", "cc"]),
        .init("Clojure", icon: "clojure", color: 0x8DC149, aliases: ["clj", "cljs"]),
        .init("CoffeeScript", icon: "coffee", color: 0xCBCB41, aliases: ["coffee"]),
        .init("Crystal", icon: "crystal", color: 0xD4D7D6, aliases: ["cr"]),
        .init("CSS", icon: "css", color: 0x519ABA, aliases: []),
        .init("CSV", icon: "csv", color: 0x8DC149, aliases: []),
        .init("CUDA", icon: "cu", color: 0x8DC149, aliases: ["cu"]),
        .init("D", icon: "d", color: 0xCC3E44, aliases: ["dlang"]),
        .init("Dart", icon: "dart", color: 0x519ABA, aliases: []),
        .init("Dockerfile", icon: "docker", color: 0x519ABA, aliases: ["docker"]),
        .init("EJS", icon: "ejs", color: 0xCBCB41, aliases: []),
        .init("Elixir", icon: "elixir", color: 0xA074C4, aliases: ["ex", "exs"]),
        .init("Elm", icon: "elm", color: 0x519ABA, aliases: []),
        .init("Erlang", icon: "default", color: 0x6D8086, aliases: ["erl"]),
        .init("F#", icon: "f-sharp", color: 0x519ABA, aliases: ["fsharp", "fs"]),
        .init("Fortran", icon: "default", color: 0x6D8086, aliases: ["f90"]),
        .init("GDScript", icon: "godot", color: 0x519ABA, aliases: ["godot", "gd"]),
        .init("Go", icon: "go2", color: 0x519ABA, aliases: ["golang"]),
        .init("GraphQL", icon: "graphql", color: 0xF55385, aliases: ["gql"]),
        .init("Groovy", icon: "grails", color: 0x8DC149, aliases: ["gradle"]),
        .init("Haml", icon: "haml", color: 0xCC3E44, aliases: []),
        .init("Handlebars", icon: "mustache", color: 0xE37933, aliases: ["hbs", "mustache"]),
        .init("Haskell", icon: "haskell", color: 0xA074C4, aliases: ["hs"]),
        .init("Haxe", icon: "haxe", color: 0xE37933, aliases: ["hx"]),
        .init("HCL", icon: "terraform", color: 0xA074C4, aliases: ["terraform", "tf"]),
        .init("HTML", icon: "html", color: 0xE37933, aliases: ["htm", "xhtml"]),
        .init("INI", icon: "config", color: 0x6D8086, aliases: ["cfg", "conf", "properties"]),
        .init("Java", icon: "java", color: 0xCC3E44, aliases: []),
        .init("JavaScript", icon: "javascript", color: 0xCBCB41, aliases: ["js", "node", "mjs", "cjs"]),
        .init("Jinja", icon: "jinja", color: 0xCC3E44, aliases: ["jinja2", "j2"]),
        .init("JSON", icon: "json", color: 0xCBCB41, aliases: ["jsonc", "json5"]),
        .init("JSX", icon: "react", color: 0x519ABA, aliases: ["react"]),
        .init("Julia", icon: "julia", color: 0xA074C4, aliases: ["jl"]),
        .init("Kotlin", icon: "kotlin", color: 0xE37933, aliases: ["kt", "kts"]),
        .init("LaTeX", icon: "tex", color: 0x519ABA, aliases: ["tex"]),
        .init("Less", icon: "less", color: 0x519ABA, aliases: []),
        .init("Liquid", icon: "liquid", color: 0x8DC149, aliases: []),
        .init("Lisp", icon: "default", color: 0x6D8086, aliases: ["scheme", "racket"]),
        .init("Lua", icon: "lua", color: 0x519ABA, aliases: []),
        .init("Makefile", icon: "makefile", color: 0xE37933, aliases: ["make", "mk"]),
        .init("Markdown", icon: "markdown", color: 0x519ABA, aliases: ["md", "mdx"]),
        .init("Nim", icon: "nim", color: 0xCBCB41, aliases: []),
        .init("Nix", icon: "default", color: 0x6D8086, aliases: []),
        .init("Objective-C", icon: "c", color: 0xCBCB41, aliases: ["objc", "objectivec"]),
        .init("OCaml", icon: "ocaml", color: 0xE37933, aliases: ["ml"]),
        .init("Perl", icon: "perl", color: 0x519ABA, aliases: ["pl"]),
        .init("PHP", icon: "php", color: 0xA074C4, aliases: []),
        .init("PowerShell", icon: "powershell", color: 0x519ABA, aliases: ["ps1", "pwsh"]),
        .init("Prisma", icon: "prisma", color: 0x519ABA, aliases: []),
        .init("Prolog", icon: "prolog", color: 0xE37933, aliases: ["pro"]),
        .init("Protobuf", icon: "default", color: 0x6D8086, aliases: ["proto"]),
        .init("Pug", icon: "pug", color: 0xCC3E44, aliases: ["jade"]),
        .init("PureScript", icon: "purescript", color: 0xD4D7D6, aliases: ["purs"]),
        .init("Python", icon: "python", color: 0x519ABA, aliases: ["py", "python3"]),
        .init("R", icon: "R", color: 0x519ABA, aliases: ["rlang"]),
        .init("Razor", icon: "html", color: 0x519ABA, aliases: ["cshtml"]),
        .init("ReasonML", icon: "reasonml", color: 0xCC3E44, aliases: ["reason", "re"]),
        .init("ReScript", icon: "rescript", color: 0xCC3E44, aliases: ["res"]),
        .init("Ruby", icon: "ruby", color: 0xCC3E44, aliases: ["rb"]),
        .init("Rust", icon: "rust", color: 0x6D8086, aliases: ["rs"]),
        .init("Sass", icon: "sass", color: 0xF55385, aliases: ["scss"]),
        .init("Scala", icon: "scala", color: 0xCC3E44, aliases: ["sc"]),
        .init("Slim", icon: "slim", color: 0xE37933, aliases: []),
        .init("Solidity", icon: "ethereum", color: 0x519ABA, aliases: ["sol"]),
        .init("SQL", icon: "db", color: 0xF55385, aliases: ["mysql", "postgres", "postgresql", "sqlite", "plsql"]),
        .init("Stylus", icon: "stylus", color: 0x8DC149, aliases: ["styl"]),
        .init("Svelte", icon: "svelte", color: 0xCC3E44, aliases: []),
        .init("Swift", icon: "swift", color: 0xE37933, aliases: []),
        .init("TOML", icon: "config", color: 0x6D8086, aliases: []),
        .init("TSX", icon: "react", color: 0x519ABA, aliases: []),
        .init("Twig", icon: "twig", color: 0x8DC149, aliases: []),
        .init("TypeScript", icon: "typescript", color: 0x519ABA, aliases: ["ts"]),
        .init("Vala", icon: "vala", color: 0x6D8086, aliases: []),
        .init("Visual Basic", icon: "default", color: 0x6D8086, aliases: ["vb", "vba", "vbnet"]),
        .init("Vue", icon: "vue", color: 0x8DC149, aliases: []),
        .init("WebAssembly", icon: "wat", color: 0xA074C4, aliases: ["wasm", "wat"]),
        .init("XML", icon: "xml", color: 0xE37933, aliases: ["xsd", "xsl", "plist", "svg"]),
        .init("YAML", icon: "yml", color: 0xA074C4, aliases: ["yml"]),
        .init("Zig", icon: "zig", color: 0xE37933, aliases: []),
    ]
}

/// Placeholders in a snippet: {{name}} asks for a value before pasting, {{date}}, {{time}} and {{clipboard}} fill themselves,
/// {{cursor}} marks where the insertion point goes after pasting.
public struct SnippetTemplate: Equatable, Sendable {
    public static let builtIns: Set<String> = ["date", "time", "clipboard", "cursor"]
    // NSRegularExpression rather than Swift regex literals, which need macOS 13.
    private static let pattern = try! NSRegularExpression(pattern: #"\{\{\s*([\p{L}\p{N}_][\p{L}\p{N}_\- ]{0,39}?)\s*\}\}"#)

    public let text: String
    /// Each placeholder with the range it covers and the field name inside.
    private let matches: [(range: Range<String.Index>, field: String)]

    public init?(_ text: String) {
        let found = Self.pattern.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { match -> (Range<String.Index>, String)? in
            guard let range = Range(match.range, in: text), let field = Range(match.range(at: 1), in: text) else { return nil }
            return (range, String(text[field]))
        }
        guard !found.isEmpty else { return nil }
        self.text = text
        matches = found
    }

    public static func == (lhs: Self, rhs: Self) -> Bool { lhs.text == rhs.text }

    /// Names the user must fill in, in order of first appearance.
    public var fields: [String] {
        var seen = Set<String>()
        return matches.map(\.field).filter { !Self.builtIns.contains($0.lowercased()) && seen.insert($0).inserted }
    }

    /// The text to paste, and how many characters follow the cursor mark, if there is one.
    public func render(values: [String: String], clipboard: String, now: Date = Date(), locale: Locale = Localization.locale) -> (text: String, charactersAfterCursor: Int?) {
        var result = ""
        var cursor: Int?
        var position = text.startIndex
        for match in matches {
            result += text[position..<match.range.lowerBound]
            switch match.field.lowercased() {
            case "date": result += now.formatted(Date.FormatStyle(date: .numeric, time: .omitted, locale: locale))
            case "time": result += now.formatted(Date.FormatStyle(date: .omitted, time: .shortened, locale: locale))
            case "clipboard": result += clipboard
            case "cursor": if cursor == nil { cursor = result.count }
            default: result += values[match.field] ?? ""
            }
            position = match.range.upperBound
        }
        result += text[position...]
        return (result, cursor.map { result.count - $0 })
    }
}

/// Snippets as readable JSON, to keep or share without the rest of the history.
public struct SnippetFile: Codable, Equatable, Sendable {
    public struct Entry: Codable, Equatable, Sendable {
        public var name: String
        public var text: String
        public var tags: [String]
        public var language: String?
        public init(name: String, text: String, tags: [String] = [], language: String? = nil) {
            self.name = name; self.text = text; self.tags = tags; self.language = language
        }
    }
    public var version = 1
    public var snippets: [Entry]

    public init(snippets: [Entry]) { self.snippets = snippets }

    /// Snippets with text; images and files stay in the full backup.
    public init(library: Library) {
        snippets = library.clips.filter { $0.snippet && [.text, .code, .link, .color].contains($0.kind) && !$0.text.isEmpty }
            .map { Entry(name: $0.name, text: $0.text, tags: $0.tags, language: $0.language) }
    }

    /// Adds the snippets. Content already in the library becomes a snippet and keeps its own details first.
    public func merged(into original: Library, now: Date = Date()) throws -> (library: Library, payloads: [(UUID, ClipPayload)]) {
        guard version == 1 else { throw CocoaError(.coderReadCorrupt) }
        var library = original
        var payloads: [(UUID, ClipPayload)] = []
        var indices = Dictionary(library.clips.enumerated().map { ($0.element.fingerprint, $0.offset) }, uniquingKeysWith: { first, _ in first })
        for entry in snippets where !entry.text.isEmpty {
            let payload = ClipPayload.text(entry.text)
            guard payload.byteCount <= PasteboardCapture.maxBytes else { throw CocoaError(.coderReadCorrupt) }
            var clip = Clip(fingerprint: payload.fingerprint, kind: .detect(text: entry.text), text: entry.text, copiedAt: now, byteCount: payload.byteCount)
            clip.snippet = true
            clip.name = String(entry.name.prefix(100))
            clip.tags = Clip.tags(from: entry.tags.joined(separator: ","))
            clip.language = entry.language.map { String($0.prefix(40)) }
            if let index = indices[payload.fingerprint] {
                library.clips[index].adoptSnippetDetails(of: clip)
                continue
            }
            indices[payload.fingerprint] = library.clips.count
            library.clips.append(clip)
            payloads.append((clip.id, payload))
        }
        library.clips.sort { $0.copiedAt > $1.copiedAt }
        return (library, payloads)
    }
}
