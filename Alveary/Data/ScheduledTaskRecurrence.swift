import Foundation

enum ScheduledTaskRecurrence: Codable, Equatable, Sendable {
    static let standardWeekdays = [2, 3, 4, 5, 6]

    case once(Date)
    case interval(minutes: Int, anchor: Date)
    case daily(hour: Int, minute: Int)
    case weekdays(days: [Int] = [2, 3, 4, 5, 6], hour: Int, minute: Int)
    case weekly(weekday: Int, hour: Int, minute: Int)
    case monthly(day: Int, hour: Int, minute: Int)

    enum Kind: String, Codable, CaseIterable, Sendable {
        case once
        case interval
        case daily
        case weekdays
        case weekly
        case monthly
    }

    var kind: Kind {
        switch self {
        case .once:
            .once
        case .interval:
            .interval
        case .daily:
            .daily
        case .weekdays:
            .weekdays
        case .weekly:
            .weekly
        case .monthly:
            .monthly
        }
    }

    var isOneShot: Bool {
        kind == .once
    }

    var selectedWeekdays: [Int]? {
        guard case let .weekdays(days, _, _) = self else {
            return nil
        }
        return days
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard container.allKeys.count == 1, let key = container.allKeys.first else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "Scheduled recurrence must contain exactly one kind."
                )
            )
        }
        let values = try container.nestedContainer(keyedBy: ValueCodingKeys.self, forKey: key)
        switch key {
        case .once:
            self = .once(try values.decode(Date.self, forKey: .unlabeled))
        case .interval:
            self = .interval(
                minutes: try values.decode(Int.self, forKey: .minutes),
                anchor: try values.decode(Date.self, forKey: .anchor)
            )
        case .daily:
            self = .daily(
                hour: try values.decode(Int.self, forKey: .hour),
                minute: try values.decode(Int.self, forKey: .minute)
            )
        case .weekdays:
            self = .weekdays(
                days: try values.decodeIfPresent([Int].self, forKey: .days) ?? Self.standardWeekdays,
                hour: try values.decode(Int.self, forKey: .hour),
                minute: try values.decode(Int.self, forKey: .minute)
            )
        case .weekly:
            self = .weekly(
                weekday: try values.decode(Int.self, forKey: .weekday),
                hour: try values.decode(Int.self, forKey: .hour),
                minute: try values.decode(Int.self, forKey: .minute)
            )
        case .monthly:
            self = .monthly(
                day: try values.decode(Int.self, forKey: .day),
                hour: try values.decode(Int.self, forKey: .hour),
                minute: try values.decode(Int.self, forKey: .minute)
            )
        }
    }

    private enum CodingKeys: String, CodingKey {
        case once
        case interval
        case daily
        case weekdays
        case weekly
        case monthly
    }

    private enum ValueCodingKeys: String, CodingKey {
        case unlabeled = "_0"
        case minutes
        case anchor
        case days
        case hour
        case minute
        case weekday
        case day
    }
}

enum ScheduledTaskRecurrenceError: Error, Equatable, LocalizedError, Sendable {
    case intervalBelowMinimum(minutes: Int, minimum: Int)
    case invalidHour(Int)
    case invalidMinute(Int)
    case emptyWeekdaySelection
    case noncanonicalWeekdaySelection([Int])
    case invalidWeekday(Int)
    case invalidMonthlyDay(Int)
    case invalidTimeZoneIdentifier(String)
    case invalidCatchUpAge(TimeInterval)

    var errorDescription: String? {
        switch self {
        case let .intervalBelowMinimum(minutes, minimum):
            "Intervals must be at least \(minimum) minute(s); received \(minutes)."
        case let .invalidHour(hour):
            "Wall-clock hour must be between 0 and 23; received \(hour)."
        case let .invalidMinute(minute):
            "Wall-clock minute must be between 0 and 59; received \(minute)."
        case .emptyWeekdaySelection:
            "Select at least one day for a weekday schedule."
        case let .noncanonicalWeekdaySelection(days):
            "Weekday selections must be unique and ordered from Sunday through Saturday; received \(days)."
        case let .invalidWeekday(weekday):
            "Calendar weekday must be between 1 (Sunday) and 7 (Saturday); received \(weekday)."
        case let .invalidMonthlyDay(day):
            "Monthly day must be between 1 and 31; received \(day)."
        case let .invalidTimeZoneIdentifier(identifier):
            "Unknown IANA time zone identifier: \(identifier)."
        case let .invalidCatchUpAge(age):
            "Catch-up age must be nonnegative; received \(age)."
        }
    }
}

struct ScheduledTaskOccurrenceWindow: Equatable, Sendable {
    let latestDueOccurrence: Date?
    let nextOccurrence: Date?
}

enum ScheduledTaskCatchUpAction: Equatable, Sendable {
    case none
    case run(Date)
    case skipPaused(Date)
    case skipStale(Date)
    case completeStaleOneShot(Date)
}

struct ScheduledTaskCatchUpResult: Equatable, Sendable {
    let action: ScheduledTaskCatchUpAction
    let nextOccurrence: Date?
}
