import Foundation

public enum RetentionUnit: String, Codable, CaseIterable, Identifiable, Sendable {
    case minutes, hours, days, weeks, months, forever
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .minutes: "minute(s)"
        case .hours: "heure(s)"
        case .days: "jour(s)"
        case .weeks: "semaine(s)"
        case .months: "mois"
        case .forever: "Indéfiniment"
        }
    }
    private var component: Calendar.Component {
        switch self {
        case .minutes: .minute
        case .hours: .hour
        case .days: .day
        case .weeks: .weekOfYear
        case .months: .month
        case .forever: .year
        }
    }
    public func expiration(from date: Date, value: Int, calendar: Calendar) -> Date? {
        guard self != .forever else { return nil }
        return calendar.date(byAdding: component, value: value, to: date) ?? .distantFuture
    }
}

public struct RetentionDuration: Codable, Equatable, Sendable {
    public var value: Int
    public var unit: RetentionUnit
    public init(_ value: Int = 1, _ unit: RetentionUnit = .days) { self.value = value; self.unit = unit }
    public static let forever = RetentionDuration(1, .forever)
    public var isValid: Bool { unit == .forever || (1...10_000).contains(value) }
    public var title: String { unit == .forever ? "Indéfiniment" : "\(value) \(unit.title)" }
    public func expiration(from date: Date, calendar: Calendar = .current) -> Date? {
        guard isValid else { return nil }
        return unit.expiration(from: date, value: value, calendar: calendar)
    }
}

public struct RetentionRule: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var enabled: Bool
    public var kind: ClipKind?
    public var minimumBytes: Int64
    public var maximumBytes: Int64?
    public var duration: RetentionDuration

    public init(id: UUID = UUID(), name: String = "Nouvelle règle", enabled: Bool = true, kind: ClipKind? = nil, minimumBytes: Int64 = 0, maximumBytes: Int64? = nil, duration: RetentionDuration = .init(7, .days)) {
        self.id = id; self.name = name; self.enabled = enabled; self.kind = kind
        self.minimumBytes = minimumBytes; self.maximumBytes = maximumBytes; self.duration = duration
    }

    public var isValid: Bool {
        minimumBytes >= 0 && (maximumBytes.map { $0 > minimumBytes } ?? true) && duration.isValid
    }

    public func matches(_ clip: Clip) -> Bool {
        guard enabled, isValid, kind == nil || kind == clip.kind else { return false }
        guard let bytes = clip.retentionByteCount else { return minimumBytes == 0 && maximumBytes == nil }
        return bytes >= minimumBytes && (maximumBytes.map { bytes < $0 } ?? true)
    }

    public static var examples: [RetentionRule] {
        [
            .init(name: "Gros éléments", minimumBytes: 3_000_000_000, duration: .init(1, .hours)),
            .init(name: "De 0,5 à 1 Go", minimumBytes: 500_000_000, maximumBytes: 1_000_000_000, duration: .init(2, .days)),
            .init(name: "À partir de 300 Mo", minimumBytes: 300_000_000, duration: .init(1, .weeks)),
            .init(name: "Petits textes", kind: .text, maximumBytes: 1_000_000, duration: .forever)
        ]
    }
}

public struct RetentionDecision: Equatable, Sendable {
    public var expiresAt: Date?
    public var ruleID: UUID?
    public var ruleName: String?
    public var protected: Bool
    public var isRuleManaged: Bool { ruleID != nil }
    public func isExpired(at date: Date) -> Bool { expiresAt.map { date >= $0 } ?? false }
}

public struct RetentionPolicy: Equatable, Sendable {
    public var rules: [RetentionRule]
    public var fallback: RetentionDuration
    public init(rules: [RetentionRule] = [], fallback: RetentionDuration = .init(30, .days)) { self.rules = rules; self.fallback = fallback }

    public func decision(for clip: Clip, calendar: Calendar = .current) -> RetentionDecision {
        if clip.isProtected { return .init(expiresAt: nil, protected: true) }
        if let rule = rules.first(where: { $0.matches(clip) }) {
            return .init(expiresAt: rule.duration.expiration(from: clip.copiedAt, calendar: calendar), ruleID: rule.id, ruleName: rule.name, protected: false)
        }
        return .init(expiresAt: fallback.expiration(from: clip.copiedAt, calendar: calendar), protected: false)
    }
}
