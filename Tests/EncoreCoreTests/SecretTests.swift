import XCTest
@testable import EncoreCore

final class SecretTests: XCTestCase {
    func testRecognizesCommonSecrets() {
        let cases: [(String, SecretKind)] = [
            ("-----BEGIN OPENSSH PRIVATE KEY-----\nb3BlbnNzaC1rZXktdjEAAAAA\n-----END OPENSSH PRIVATE KEY-----", .privateKey),
            ("4111 1111 1111 1111", .card), ("5500-0000-0000-0004", .card), ("378282246310005", .card),
            ("sk-ant-api03-Zq8xV2mN5pL1kR7tY4wB9cD3", .apiKey), ("ghp_aB3dE5fG7hJ9kL1mN3pQ5rS7tU9vW1xY3zA5", .apiKey),
            ("AKIAIOSFODNN7EXAMPLE", .apiKey), ("xoxb-1234567890-abcdefghij", .apiKey), ("pk_test_EXAMPLE000000000000000000", .apiKey),
            ("eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.dozjgNryP4J3jVmNHl0w5N_XgL0n3I9PlFUP0THsR8U", .token),
            ("Zk3pQ9vX2mR7tL5wN8bC4dF6gH1jK0aS", .token),
            ("k9#Lm2!qZx", .password), ("Tr0ub4dor&3", .password), ("Xk7mQ2pL9vR4wT8n", .password),
            ("  k9#Lm2!qZx\n", .password),
        ]
        for (text, kind) in cases { XCTAssertEqual(SecretKind.detect(text), kind, text) }
    }

    func testLeavesOrdinaryCopiesAlone() {
        let ordinary = [
            "hello world", "Bonjour", "https://example.com/path?a=1&b=2", "www.example.com", "jp@example.com", "#A78BFA",
            "2026-10-29", "12:30:45", "a3f5c9e0b1d2a3f5c9e0b1d2a3f5c9e0b1d2a3f5", "3f2b8c1e-9d4a-4f6b-8e2c-1a5d7b9c0e3f",
            "1234 5678 9012 3456", "0000 0000 0000 0000", "/Users/kama/Documents/file.txt", "~/Library", "snake_case_name",
            "getUser", "v1.2.3-beta", "Les bonnes idées reviennent encore.", "C++", "password", "Password",
            "let value = compute(input) + 1", "",
        ]
        for text in ordinary { XCTAssertNil(SecretKind.detect(text), text) }
    }

    func testMaskKeepsAFewCharactersButNeverHalfTheSecret() {
        XCTAssertEqual(SecretKind.mask("sk-ant-api03-secret", keeping: 3), "sk-••••••••")
        XCTAssertEqual(SecretKind.mask("k9#Lm2!qZx", keeping: 0), "••••••••")
        XCTAssertEqual(SecretKind.mask("abcd", keeping: 8), "ab••••••••")
        XCTAssertEqual(SecretKind.mask("  k9#Lm2!qZx  ", keeping: 2), "k9••••••••")
    }

    func testSecretsExpireAfterTheirLifetimeUnlessProtected() {
        var secret = Clip(kind: .text, text: "sk••••••••", copiedAt: Date(timeIntervalSince1970: 1000))
        secret.secret = .apiKey
        let policy = RetentionPolicy(fallback: .init(30, .days), secretLifetime: 60)
        XCTAssertEqual(policy.decision(for: secret).expiresAt, Date(timeIntervalSince1970: 1060))
        XCTAssertNil(RetentionPolicy(fallback: .forever).decision(for: secret).expiresAt, "Detection off: the usual retention applies")
        secret.favorite = true
        XCTAssertNil(policy.decision(for: secret).expiresAt)
        var library = Library()
        var plain = Clip(kind: .text, text: "kept", copiedAt: Date(timeIntervalSince1970: 1000))
        plain.fingerprint = "plain"
        secret.favorite = false; secret.fingerprint = "secret"
        library.clips = [secret, plain]
        XCTAssertEqual(library.prune(policy: policy, limit: 0, now: Date(timeIntervalSince1970: 1061)), [secret.id])
    }

    func testACopyKeptBeforeDetectionIsMaskedWhenCopiedAgainAndNeverUnmasked() {
        var library = Library()
        let plain = Clip(fingerprint: "same", kind: .text, text: "k9#Lm2!qZx")
        library.upsert(plain)
        var again = Clip(fingerprint: "same", kind: .text, text: "k9#••••••••")
        again.secret = .password
        library.upsert(again)
        XCTAssertEqual(library.clips.count, 1)
        XCTAssertEqual(library.clips[0].text, "k9#••••••••")
        XCTAssertEqual(library.clips[0].secret, .password)
        library.upsert(Clip(fingerprint: "same", kind: .text, text: "k9#Lm2!qZx"))
        XCTAssertEqual(library.clips[0].secret, .password, "Copying it with detection off keeps it masked")
        XCTAssertEqual(library.clips[0].text, "k9#••••••••")
    }

    func testSecretsAreNeverSharedAndSurviveSaving() throws {
        var clip = Clip(kind: .text, text: "ghp••••••••", sourceBundle: "org.mozilla.firefox")
        XCTAssertTrue(LibraryShare.shareable(clip, excluded: []))
        clip.secret = .apiKey
        XCTAssertFalse(LibraryShare.shareable(clip, excluded: []))
        let decoded = try JSONDecoder().decode(Clip.self, from: JSONEncoder().encode(clip))
        XCTAssertEqual(decoded.secret, .apiKey)
    }
}
