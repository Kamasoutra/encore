import XCTest
@testable import EncoreCore

final class SnippetTests: XCTestCase {
    func testLibrariesWithoutSnippetDetailsStillLoadAndNewDetailsRoundTrip() throws {
        // A clip as written by 0.4: no name, tags or language keys.
        var legacy = try JSONSerialization.jsonObject(with: JSONEncoder().encode(Clip(kind: .text, text: "hello"))) as! [String: Any]
        for key in ["name", "tags", "language"] { legacy.removeValue(forKey: key) }
        let old = try JSONDecoder().decode(Clip.self, from: JSONSerialization.data(withJSONObject: legacy))
        XCTAssertEqual(old.name, "")
        XCTAssertEqual(old.tags, [])
        XCTAssertNil(old.language)

        var clip = Clip(kind: .code, text: "git status")
        clip.name = "Status"; clip.tags = ["git"]; clip.language = "Bash"
        XCTAssertEqual(try JSONDecoder().decode(Clip.self, from: JSONEncoder().encode(clip)), clip)
        XCTAssertEqual(clip.displayTitle, "Status")
    }

    func testTagsAreSplitLowercasedAndDeduplicated() {
        XCTAssertEqual(Clip.tags(from: "#Work, mail  work,#perso"), ["work", "mail", "perso"])
        XCTAssertEqual(Clip.tags(from: "  "), [])
    }

    func testSearchFindsNamesAndTagsAndListsNameMatchesFirst() {
        var named = Clip(kind: .text, text: "Kind regards")
        named.name = "Signature"; named.tags = ["mail"]; named.language = "Markdown"
        let other = Clip(kind: .text, text: "my signature is below")
        XCTAssertTrue(ClipQuery(query: "signature").matches(named))
        XCTAssertTrue(ClipQuery(query: "tag:mail").matches(named))
        XCTAssertFalse(ClipQuery(query: "tag:mai").matches(named))
        XCTAssertTrue(ClipQuery(query: "lang:markdown").matches(named))
        XCTAssertTrue(ClipQuery(query: "signature").matchesName(named))
        XCTAssertFalse(ClipQuery(query: "signature").matchesName(other))
        XCTAssertFalse(ClipQuery(query: "tag:mail").matchesName(named))
    }

    func testTemplateFieldsAndRendering() throws {
        let template = try XCTUnwrap(SnippetTemplate("Hi {{ name }}, see {{clipboard}} on {{date}}.{{cursor}} Bye {{name}} {{Team}}"))
        XCTAssertEqual(template.fields, ["name", "Team"])
        let now = Date(timeIntervalSince1970: 0)
        let locale = Locale(identifier: "en_US_POSIX")
        let rendered = template.render(values: ["name": "Ana", "Team": "Ops"], clipboard: "the PR", now: now, locale: locale)
        let date = now.formatted(Date.FormatStyle(date: .numeric, time: .omitted, locale: locale))
        XCTAssertEqual(rendered.text, "Hi Ana, see the PR on \(date). Bye Ana Ops")
        XCTAssertEqual(rendered.charactersAfterCursor, " Bye Ana Ops".count)
        XCTAssertNil(SnippetTemplate("No placeholder, {single} or {{ }}"))
        XCTAssertNil(SnippetTemplate("plain").map(\.text))
    }

    func testSnippetFileExportsTextSnippetsAndMergesWithoutDuplicates() throws {
        var library = Library()
        var snippet = Clip(fingerprint: ClipPayload.text("git status").fingerprint, kind: .code, text: "git status")
        snippet.name = "Status"
        snippet.snippet = true
        var image = Clip(kind: .image, text: "")
        image.snippet = true
        library.clips = [snippet, Clip(kind: .text, text: "a favorite", favorite: true), image]
        let file = SnippetFile(library: library)
        XCTAssertEqual(file.snippets, [.init(name: "Status", text: "git status")])

        let decoded = try JSONDecoder().decode(SnippetFile.self, from: JSONEncoder().encode(SnippetFile(snippets: [
            .init(name: "Other name", text: "git status", tags: ["Git"], language: "Bash"),
            .init(name: "Signature", text: "Kind regards", tags: ["mail"]),
        ])))
        let merged = try decoded.merged(into: library)
        XCTAssertEqual(merged.payloads.count, 1)
        XCTAssertEqual(merged.library.clips.count, 4)
        let existing = try XCTUnwrap(merged.library.clips.first { $0.text == "git status" })
        XCTAssertEqual(existing.name, "Status")
        XCTAssertEqual(existing.tags, ["git"])
        XCTAssertEqual(existing.language, "Bash")
        let added = try XCTUnwrap(merged.library.clips.first { $0.text == "Kind regards" })
        XCTAssertTrue(added.snippet)
        XCTAssertFalse(added.favorite)
        XCTAssertTrue(added.isProtected)

        // Items named in development builds, before the snippet flag, become snippets.
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(snippet)) as? [String: Any])
        json.removeValue(forKey: "snippet")
        XCTAssertTrue(try JSONDecoder().decode(Clip.self, from: JSONSerialization.data(withJSONObject: json)).snippet)
        json["name"] = ""
        XCTAssertFalse(try JSONDecoder().decode(Clip.self, from: JSONSerialization.data(withJSONObject: json)).snippet)
        XCTAssertEqual(added.name, "Signature")
        XCTAssertEqual(added.fingerprint, ClipPayload.text("Kind regards").fingerprint)
    }

    func testFavoritesGroupByLanguageThenFirstTag() {
        var code = Clip(kind: .code, text: "x"); code.language = "Swift"; code.tags = ["work"]
        var tagged = Clip(kind: .text, text: "y"); tagged.tags = ["work", "admin"]
        XCTAssertEqual(code.snippetGroup, "Swift")
        XCTAssertEqual(tagged.snippetGroup, "#admin")
        XCTAssertEqual(Clip(kind: .text, text: "z").snippetGroup, "")
    }

    func testLanguageCatalogAndDetection() {
        XCTAssertGreaterThan(CodeLanguage.all.count, 80)
        XCTAssertEqual(Set(CodeLanguage.all.map(\.name)).count, CodeLanguage.all.count)
        XCTAssertEqual(CodeLanguage.named("py")?.name, "Python")
        XCTAssertEqual(CodeLanguage.named("c#")?.name, "C#")
        XCTAssertEqual(CodeLanguage.search("ty").first?.name, "TypeScript")
        XCTAssertEqual(CodeLanguage.search("js").first?.name, "JavaScript")
        var clip = Clip(kind: .code, text: "x")
        clip.language = "JavaScript"
        XCTAssertTrue(ClipQuery(query: "lang:js").matches(clip))

        let samples: [(String, String?)] = [
            ("#!/usr/bin/env python3\nprint('hi')", "Python"),
            ("def greet(name):\n    return f'hi {name}'\n\nimport os", "Python"),
            ("import SwiftUI\n\nstruct A: View {\n    @State var x = 0\n}", "Swift"),
            ("fn main() {\n    let mut x = 1;\n    println!(\"{}\", x);\n}", "Rust"),
            ("package main\n\nfunc main() {\n\tx := 1\n\tfmt.Println(x)\n}", "Go"),
            ("SELECT id, name\nFROM users\nWHERE id = 1;", "SQL"),
            ("select * from users;\ninsert into logs values (1);", "SQL"),
            ("const add = (a, b) => a + b;\nconsole.log(add(1, 2));", "JavaScript"),
            ("interface User {\n  name: string;\n  age: number;\n}", "TypeScript"),
            ("{\"name\": \"encore\", \"version\": 1}", "JSON"),
            ("<!DOCTYPE html>\n<html><body></body></html>", "HTML"),
            ("<?php echo 'hi'; ?>", "PHP"),
            ("FROM swift:5.10\nRUN swift build", "Dockerfile"),
            (".card {\n  color: red;\n  margin: 0;\n}", "CSS"),
            ("# Title\n\nSome [link](https://x.y) here.", "Markdown"),
            ("defmodule Hello do\n  def world, do: :ok |> IO.inspect\nend", "Elixir"),
            ("Bonjour, à demain pour le point projet.", nil),
            ("https://example.com/path?x=1", nil),
        ]
        for (text, expected) in samples { XCTAssertEqual(CodeLanguage.detect(text)?.name, expected, text) }
        // Long single lines must not make any pattern backtrack for seconds.
        let start = Date()
        for filler in ["a-b ", "select ", "def x(", ".a .b ", "$x = ", "- k: "] { _ = CodeLanguage.detect(String(repeating: filler, count: 2_000)) }
        XCTAssertLessThan(Date().timeIntervalSince(start), 1)
    }
}
