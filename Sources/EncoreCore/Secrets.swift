import Foundation

/// Copied text that looks like a secret. Detection is a guess: it is opt-in, and the settings warn about false positives.
public enum SecretKind: String, Codable, CaseIterable, Sendable {
    case privateKey, card, apiKey, token, password

    public var title: String {
        switch self {
        case .privateKey: L("Private key")
        case .card: L("Card number")
        case .apiKey: L("API key")
        case .token: L("Token")
        case .password: L("Password")
        }
    }

    /// Known prefixes of API keys: OpenAI and Anthropic, Stripe, GitHub, Slack, AWS, Google, GitLab, npm and SendGrid.
    private static let apiKeyPatterns = [
        #"^sk-[A-Za-z0-9_\-]{20,}$"#, #"^(sk|pk|rk)_(live|test)_[A-Za-z0-9]{16,}$"#, #"^gh[pousr]_[A-Za-z0-9]{30,}$"#,
        #"^github_pat_[A-Za-z0-9_]{30,}$"#, #"^xox[abposr]-[A-Za-z0-9\-]{10,}$"#, #"^(AKIA|ASIA)[0-9A-Z]{16}$"#,
        #"^AIza[0-9A-Za-z_\-]{35}$"#, #"^glpat-[A-Za-z0-9_\-]{20,}$"#, #"^npm_[A-Za-z0-9]{36}$"#, #"^SG\.[\w\-]{22}\.[\w\-]{43}$"#,
    ].map { try! NSRegularExpression(pattern: $0) }
    private static let jwt = try! NSRegularExpression(pattern: #"^eyJ[\w\-]{8,}\.[\w\-]{8,}\.[\w\-]{8,}$"#)
    private static let uuid = try! NSRegularExpression(pattern: #"^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$"#)

    public static func detect(_ text: String) -> SecretKind? {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value.count <= 8192 else { return nil }
        if value.contains("-----BEGIN") && value.contains("PRIVATE KEY-----") { return .privateKey }
        if isCard(value) { return .card }
        // The others are a single word.
        guard !value.contains(where: \.isWhitespace) else { return nil }
        if apiKeyPatterns.contains(where: { matches($0, value) }) { return .apiKey }
        if matches(jwt, value) || isRandomToken(value) { return .token }
        if isPassword(value) { return .password }
        return nil
    }

    /// The first characters, then dots: enough to tell secrets apart without showing them.
    public static func mask(_ text: String, keeping count: Int) -> String {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return String(value.prefix(max(0, min(count, value.count / 2)))) + String(repeating: "•", count: 8)
    }

    private static func matches(_ expression: NSRegularExpression, _ value: String) -> Bool {
        expression.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)) != nil
    }

    /// 13 to 19 digits, grouped by spaces or dashes at most, that pass the Luhn check.
    private static func isCard(_ value: String) -> Bool {
        guard value.allSatisfy({ $0.isASCII && ($0.isNumber || $0 == " " || $0 == "-") }) else { return false }
        let digits = value.compactMap(\.wholeNumberValue)
        guard (13...19).contains(digits.count), Set(digits).count > 1 else { return false }
        let sum = digits.reversed().enumerated().reduce(0) { total, pair in
            let doubled = pair.offset % 2 == 1 ? pair.element * 2 : pair.element
            return total + (doubled > 9 ? doubled - 9 : doubled)
        }
        return sum % 10 == 0
    }

    /// A long run of letters and digits with upper case, lower case and digits mixed, like a random key.
    /// Hexadecimal strings are left alone: commit hashes and checksums are copied far more often than hex secrets.
    private static func isRandomToken(_ value: String) -> Bool {
        guard (24...512).contains(value.count), !matches(uuid, value),
              value.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || "_-+/=".contains($0)) }),
              !value.allSatisfy(\.isHexDigit) else { return false }
        return value.contains(where: \.isUppercase) && value.contains(where: \.isLowercase) && value.contains(where: \.isNumber)
    }

    /// 8 to 64 characters with letters, digits and a symbol, or 12 and more mixing three kinds of characters:
    /// generated passwords look like that, words, links, addresses and paths do not.
    private static func isPassword(_ value: String) -> Bool {
        guard (8...64).contains(value.count), !value.contains("://"), !value.hasPrefix("www."), !value.hasPrefix("/"), !value.hasPrefix("~"),
              !(value.contains("@") && value.split(separator: "@").last?.contains(".") == true),
              !(value.hasPrefix("#") && value.count <= 9) else { return false }
        let letters = value.contains(where: \.isLetter), digits = value.contains(where: \.isNumber)
        let symbol = value.contains { !$0.isLetter && !$0.isNumber && !"_-.".contains($0) }
        if letters && digits && symbol { return true }
        let kinds = [value.contains(where: \.isUppercase), value.contains(where: \.isLowercase), digits].filter { $0 }.count
        return value.count >= 12 && kinds == 3
    }
}
