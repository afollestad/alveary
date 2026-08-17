import Foundation

enum ScheduledTasksFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case active = "Active"
    case paused = "Paused"

    var id: String { rawValue }
}

struct ScheduledTaskProjectOption: Identifiable, Equatable {
    let path: String
    let name: String

    var id: String { path }
}

struct ScheduledTaskThreadOption: Identifiable, Equatable {
    let conversationID: String
    /// Ends in `· Will be pinned` for an unpinned thread, because saving a schedule that targets
    /// it pins it — and a scheduled attachment then blocks unpinning until the schedule is gone.
    let label: String

    var id: String { conversationID }
}

struct ScheduledTaskPickerOption: Identifiable, Equatable {
    let value: String
    let label: String

    var id: String { value }
}

struct ScheduledTaskRowPresentation: Identifiable, Equatable {
    let id: String
    let revision: Int
    let title: String
    let prompt: String
    let state: ScheduledTaskState
    let recurrence: ScheduledTaskRecurrence?
    let timeZoneIdentifier: String
    let providerID: String
    let workspaceSummary: String
    let destination: ScheduledTaskDestination?
    let targetThreadName: String?
    let isWaitingForTarget: Bool
    let nextOccurrenceAt: Date?
    let pauseReason: String?
    let lastError: String?
    let hasActiveRun: Bool
    let modifiedAt: Date

    var canPause: Bool {
        state == .active
    }

    var canResume: Bool {
        state == .paused
    }

    var canRunNow: Bool {
        !hasActiveRun && !isWaitingForTarget
    }

    var blockedReason: String? {
        pauseReason ?? lastError
    }
}

struct ScheduledTaskEditorDraft: Identifiable, Equatable {
    let id: UUID
    let definitionID: String?
    let expectedRevision: Int?
    var title: String
    var prompt: String
    var destination: ScheduledTaskDestination = .newThreadPerRun
    var targetConversationID: String?
    var recurrenceKind: ScheduledTaskRecurrence.Kind
    var onceOccurrenceAt: Date
    var intervalAnchorAt: Date
    var intervalMinutes: Int
    var wallClockHour: Int
    var wallClockMinute: Int
    var selectedWeekdays: Set<Int>
    var weeklyWeekday: Int
    var monthlyDay: Int
    var timeZoneIdentifier: String
    var providerID: String
    var modelSelection: String
    var effort: String
    var permissionMode: String
    var workspaceKind: ScheduledTaskWorkspaceKind
    var workspaceStrategy: ScheduledTaskWorkspaceStrategy
    var projectPath: String?
    var grantedRoots: [String]

    var isEditing: Bool {
        definitionID != nil
    }

    var recurrence: ScheduledTaskRecurrence {
        switch recurrenceKind {
        case .once:
            .once(onceOccurrenceAt)
        case .interval:
            .interval(minutes: intervalMinutes, anchor: intervalAnchorAt)
        case .daily:
            .daily(hour: wallClockHour, minute: wallClockMinute)
        case .weekdays:
            .weekdays(days: selectedWeekdays.sorted(), hour: wallClockHour, minute: wallClockMinute)
        case .weekly:
            .weekly(weekday: weeklyWeekday, hour: wallClockHour, minute: wallClockMinute)
        case .monthly:
            .monthly(day: monthlyDay, hour: wallClockHour, minute: wallClockMinute)
        }
    }
}

struct ProposalDraftRecurrenceFields {
    var onceOccurrenceAt: Date
    var intervalAnchorAt: Date
    var intervalMinutes = 60
    var wallClockHour = 9
    var wallClockMinute = 0
    var selectedWeekdays = Set(ScheduledTaskRecurrence.standardWeekdays)
    var weeklyWeekday = 2
    var monthlyDay = 1

    init(
        recurrence: ScheduledTaskRecurrence,
        fallbackOnceOccurrence: Date,
        fallbackIntervalAnchor: Date
    ) {
        onceOccurrenceAt = fallbackOnceOccurrence
        intervalAnchorAt = fallbackIntervalAnchor
        switch recurrence {
        case .once(let occurrence):
            onceOccurrenceAt = occurrence
        case let .interval(minutes, anchor):
            intervalAnchorAt = anchor
            intervalMinutes = minutes
        case let .daily(hour, minute):
            wallClockHour = hour
            wallClockMinute = minute
        case let .weekdays(days, hour, minute):
            selectedWeekdays = Set(days)
            wallClockHour = hour
            wallClockMinute = minute
        case let .weekly(weekday, hour, minute):
            weeklyWeekday = weekday
            wallClockHour = hour
            wallClockMinute = minute
        case let .monthly(day, hour, minute):
            monthlyDay = day
            wallClockHour = hour
            wallClockMinute = minute
        }
    }
}

enum ScheduledTaskPresentationFormatting {
    static func recurrenceSummary(
        _ recurrence: ScheduledTaskRecurrence?,
        timeZoneIdentifier: String,
        locale: Locale = .current
    ) -> String {
        guard let recurrence else {
            return "Invalid schedule"
        }

        switch recurrence {
        case .once(let occurrence):
            return "Once on \(dateTime(occurrence, timeZoneIdentifier: timeZoneIdentifier, locale: locale))"
        case let .interval(minutes, anchor):
            let unit = minutes == 1 ? "minute" : "minutes"
            return "Every \(minutes) \(unit) from \(dateTime(anchor, timeZoneIdentifier: timeZoneIdentifier, locale: locale))"
        case let .daily(hour, minute):
            return "Daily at \(time(hour: hour, minute: minute, timeZoneIdentifier: timeZoneIdentifier, locale: locale))"
        case let .weekdays(days, hour, minute):
            let schedule = days == ScheduledTaskRecurrence.standardWeekdays
                ? "Weekdays"
                : "Every \(weekdayList(days, locale: locale))"
            return "\(schedule) at \(time(hour: hour, minute: minute, timeZoneIdentifier: timeZoneIdentifier, locale: locale))"
        case let .weekly(weekday, hour, minute):
            return "Weekly on \(weekdayName(weekday, locale: locale)) at "
                + time(hour: hour, minute: minute, timeZoneIdentifier: timeZoneIdentifier, locale: locale)
        case let .monthly(day, hour, minute):
            return "Monthly on day \(day) at "
                + time(hour: hour, minute: minute, timeZoneIdentifier: timeZoneIdentifier, locale: locale)
        }
    }

    static func dateTime(
        _ date: Date,
        timeZoneIdentifier: String,
        locale: Locale = .current
    ) -> String {
        let timeZone = TimeZone(identifier: timeZoneIdentifier) ?? .current
        return formatter(.init(dateStyle: .medium, timeStyle: .short, locale: locale, timeZone: timeZone))
            .string(from: date)
    }

    static func time(
        hour: Int,
        minute: Int,
        timeZoneIdentifier: String,
        locale: Locale = .current
    ) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timeZoneIdentifier) ?? .current
        let components = DateComponents(
            calendar: calendar,
            timeZone: calendar.timeZone,
            year: 2001,
            month: 1,
            day: 1,
            hour: hour,
            minute: minute
        )
        guard let date = calendar.date(from: components) else {
            return String(format: "%02d:%02d", hour, minute)
        }

        return formatter(.init(dateStyle: .none, timeStyle: .short, locale: locale, timeZone: calendar.timeZone))
            .string(from: date)
    }

    static func weekdayName(_ weekday: Int, locale: Locale = .current) -> String {
        let names = weekdaySymbols(for: locale).full
        let index = weekday - 1
        guard names.indices.contains(index) else {
            return "day \(weekday)"
        }
        return names[index]
    }

    static func shortWeekdayName(_ weekday: Int, locale: Locale = .current) -> String {
        let names = weekdaySymbols(for: locale).short
        let index = weekday - 1
        guard names.indices.contains(index) else {
            return String(weekday)
        }
        return String(names[index].prefix(2))
    }

    static func weekdayList(_ weekdays: [Int], locale: Locale = .current) -> String {
        let names = weekdays.map { weekdayName($0, locale: locale) }
        switch names.count {
        case 0:
            return "no days"
        case 1:
            return names[0]
        case 2:
            return names.joined(separator: " and ")
        default:
            return names.dropLast().joined(separator: ", ") + ", and \(names[names.count - 1])"
        }
    }
}

// MARK: - Formatter caching

/// Building a `DateFormatter` is the expensive part of date formatting, and every
/// scheduled-task row formats its recurrence plus its next occurrence on each body pass —
/// a weekday schedule once per named day. The keys carry everything that configures a
/// formatter, so a locale or time-zone change still derives a fresh one, and the live key
/// space is bounded by the time zones the user's tasks actually use.
private extension ScheduledTaskPresentationFormatting {
    /// Safe to share: `DateFormatter` is documented thread-safe for formatting once
    /// configured, and nothing mutates one after it enters the cache.
    static let formatters = LockedState<[FormatterKey: DateFormatter]>([:])

    /// Symbol arrays rather than the formatter that produced them, so the lazy first read
    /// of `weekdaySymbols` happens under the lock instead of on a shared instance.
    static let symbols = LockedState<[Locale: WeekdaySymbols]>([:])

    struct FormatterKey: Hashable {
        let dateStyle: DateFormatter.Style
        let timeStyle: DateFormatter.Style
        let locale: Locale
        let timeZone: TimeZone
    }

    struct WeekdaySymbols {
        let full: [String]
        let short: [String]
    }

    static func formatter(_ key: FormatterKey) -> DateFormatter {
        formatters.withLock { cache in
            if let cached = cache[key] {
                return cached
            }
            let formatter = DateFormatter()
            formatter.locale = key.locale
            formatter.timeZone = key.timeZone
            formatter.dateStyle = key.dateStyle
            formatter.timeStyle = key.timeStyle
            cache[key] = formatter
            return formatter
        }
    }

    static func weekdaySymbols(for locale: Locale) -> WeekdaySymbols {
        symbols.withLock { cache in
            if let cached = cache[locale] {
                return cached
            }
            let formatter = DateFormatter()
            formatter.locale = locale
            let resolved = WeekdaySymbols(
                full: formatter.weekdaySymbols ?? [],
                short: formatter.shortWeekdaySymbols ?? []
            )
            cache[locale] = resolved
            return resolved
        }
    }
}
