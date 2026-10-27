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

    func testSnippetFileExportsTextFavoritesAndMergesWithoutDuplicates() throws {
        var library = Library()
        var favorite = Clip(fingerprint: ClipPayload.text("git status").fingerprint, kind: .code, text: "git status", favorite: true)
        favorite.name = "Status"
        library.clips = [favorite, Clip(kind: .text, text: "not a favorite"), Clip(kind: .image, text: "", favorite: true)]
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
        XCTAssertTrue(added.favorite)
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
}
