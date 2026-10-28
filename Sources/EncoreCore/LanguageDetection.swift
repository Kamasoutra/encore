import Foundation

extension CodeLanguage {
    /// A best guess at the language of a copied snippet, to preselect it when filing the snippet. Nil when nothing is distinctive enough.
    public static func detect(_ text: String) -> CodeLanguage? {
        let source = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !source.isEmpty else { return nil }
        // Patterns stay linear, and the sample is short, so a large copy never stalls the panel.
        let sample = String(source.prefix(4_000))
        let firstLine = sample.prefix(while: { $0 != "\n" }).trimmingCharacters(in: .whitespaces)

        if firstLine.hasPrefix("#!") {
            let interpreters: [(String, String)] = [("python", "Python"), ("node", "JavaScript"), ("deno", "TypeScript"), ("ruby", "Ruby"), ("perl", "Perl"), ("php", "PHP"), ("pwsh", "PowerShell"), ("bash", "Bash"), ("zsh", "Bash"), ("sh", "Bash")]
            if let match = interpreters.first(where: { firstLine.contains($0.0) }) { return named(match.1) }
        }
        if sample.hasPrefix("<?php") { return named("PHP") }
        if sample.hasPrefix("<?xml") { return named("XML") }
        if contains(sample, #"^\s*<!doctype html|<html[\s>]"#, caseInsensitive: true) { return named("HTML") }
        if (sample.hasPrefix("{") || sample.hasPrefix("[")), let data = sample.data(using: .utf8), (try? JSONSerialization.jsonObject(with: data)) != nil { return named("JSON") }
        if contains(sample, #"^FROM\s+\S+"#), contains(sample, #"^(RUN|CMD|COPY|ENTRYPOINT|WORKDIR)\s"#) { return named("Dockerfile") }

        let rules: [(String, [String])] = [
            ("Swift", [#"\bimport (SwiftUI|Foundation|UIKit|AppKit)\b"#, #"\bfunc \w+\(.*\)\s*(->|\{|throws|async)"#, #"\bguard let\b|\bif let \w+\s*=?"#, #"@(State|Published|MainActor)\b"#]),
            ("Rust", [#"\bfn \w+\s*(<.*>)?\("#, #"\blet mut\b"#, #"\buse \w+::"#, #"\bimpl\b.*\{"#, #"println!\("#]),
            ("Go", [#"^package \w+"#, #"\bfunc (\(\w+ \*?\w+\) )?\w+\("#, #":= "#, #"\bfmt\.\w+\("#]),
            ("Kotlin", [#"\bfun \w+\("#, #"\bval \w+"#, #"\bdata class\b"#]),
            ("Python", [#"^\s*def \w+\(.*\)\s*(->.*)?:\s*$"#, #"^\s*(from \w[\w.]* )?import \w"#, #"^\s*class \w+(\(.*\))?:\s*$"#, #"\bself\.\w"#, #"\bprint\("#, #"^\s*if __name__ == "#]),
            ("Elixir", [#"\bdefmodule\b"#, #"\|>"#, #"^\s*def(p)? \w+.* do\s*$"#]),
            ("Ruby", [#"^\s*def \w+[^:]*$"#, #"^\s*end\s*$"#, #"\bputs\b"#, #"\battr_(accessor|reader)\b"#, #"\brequire ['\"]"#]),
            ("C#", [#"\busing System\b"#, #"\bnamespace \w+"#, #"\bpublic (static )?(class|void|async)\b"#, #"Console\.WriteLine"#]),
            ("Java", [#"\bpublic (static )?(class|void)\b"#, #"System\.out\.println"#, #"^import java\."#, #"@Override"#]),
            ("C++", [#"#include\s*<\w+>"#, #"\bstd::"#, #"\bcout\s*<<"#, #"\btemplate\s*<"#]),
            ("C", [#"#include\s*[<\"]\w+\.h[>\"]"#, #"\bint main\s*\("#, #"\bprintf\s*\("#, #"\bmalloc\s*\("#]),
            ("PHP", [#"\$\w+\s*="#, #"\bfunction \w+\(.*\$"#, #"\becho\b"#]),
            ("TypeScript", [#"\binterface \w+\s*\{"#, #":\s*(string|number|boolean)\b"#, #"\btype \w+\s*="#, #"\bimport .* from ['\"]"#]),
            ("JavaScript", [#"\b(const|let|var) \w+\s*="#, #"=>"#, #"\bfunction\s*\w*\("#, #"\bconsole\.log\("#, #"\brequire\(['\"]"#, #"\bimport .* from ['\"]"#]),
            ("SQL", [#"\bselect\b[\s\S]{1,400}?\bfrom\b"#, #"\binsert into\b"#, #"\bcreate (table|index|view)\b"#, #"\bupdate \w+ set\b"#, #"\bdelete from\b"#, #"\b(where|join|group by|order by)\b"#]),
            ("Bash", [#"^\s*(sudo|export|echo|cd|ls|grep|curl|brew|git|npm|docker|kubectl) "#, #"\$\{?\w+\}?"#, #"\|\s*\w+"#, #"&&"#, #"^\s*(if|for|while) .*; (then|do)"#]),
            ("PowerShell", [#"\$\w+\s*=\s*Get-"#, #"\b(Get|Set|New|Remove)-\w+"#, #"Write-Host"#]),
            ("CSS", [#"^[.#:\w][^{};\n]*\{\s*$"#, #"^\s*[\w-]+\s*:\s*[^;]+;\s*$"#, #"@media\b"#]),
            ("YAML", [#"^[\w-]+:\s*$"#, #"^[\w-]+:\s+\S"#, #"^\s+- \S"#, #"^---\s*$"#]),
            ("Markdown", [#"^#{1,6} \S"#, #"^```"#, #"^\s*[-*] \[[ x]\] "#, #"\[[^\]]+\]\([^)]+\)"#]),
            ("HCL", [#"^(resource|variable|provider|module|output) \""#]),
            ("Lua", [#"\blocal function\b"#, #"\blocal \w+\s*="#, #"\bend\b"#]),
            ("TOML", [#"^\[[\w.-]+\]\s*$"#, #"^\w+\s*=\s*(\"|\d|true|false|\[)"#]),
        ]
        // Each rule scores by how many of its distinctive patterns appear; the strongest language wins if it shows at least two signs,
        // so a lone "=>" or "$var" does not file plain text as code.
        let scores = rules.map { rule in (rule.0, rule.1.filter { contains(sample, $0, caseInsensitive: rule.0 == "SQL") }.count) }
        // On a tie, the earlier and more specific rule wins.
        guard let top = scores.map(\.1).max(), top >= 2, let best = scores.first(where: { $0.1 == top }) else { return nil }
        return named(best.0)
    }

    private static func contains(_ text: String, _ pattern: String, caseInsensitive: Bool = false) -> Bool {
        var options: NSRegularExpression.Options = [.anchorsMatchLines]
        if caseInsensitive { options.insert(.caseInsensitive) }
        guard let expression = try? NSRegularExpression(pattern: pattern, options: options) else { return false }
        return expression.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }
}
