import Foundation

struct ScheduledTaskRecurrenceCalculator: Sendable {
    static let minimumIntervalMinutes = 1
    static let defaultCatchUpAge: TimeInterval = 7 * 24 * 60 * 60

    private let calendarIdentifier: Calendar.Identifier

    init(calendarIdentifier: Calendar.Identifier = .gregorian) {
        self.calendarIdentifier = calendarIdentifier
    }

    func validate(
        _ recurrence: ScheduledTaskRecurrence,
        timeZoneIdentifier: String
    ) throws {
        _ = try timeZone(identifier: timeZoneIdentifier)

        switch recurrence {
        case .once:
            break
        case let .interval(minutes, _):
            guard minutes >= Self.minimumIntervalMinutes else {
                throw ScheduledTaskRecurrenceError.intervalBelowMinimum(
                    minutes: minutes,
                    minimum: Self.minimumIntervalMinutes
                )
            }
        case let .daily(hour, minute):
            try validateWallClock(hour: hour, minute: minute)
        case let .weekdays(days, hour, minute):
            try validateWeekdaySelection(days)
            try validateWallClock(hour: hour, minute: minute)
        case let .weekly(weekday, hour, minute):
            guard (1 ... 7).contains(weekday) else {
                throw ScheduledTaskRecurrenceError.invalidWeekday(weekday)
            }
            try validateWallClock(hour: hour, minute: minute)
        case let .monthly(day, hour, minute):
            guard (1 ... 31).contains(day) else {
                throw ScheduledTaskRecurrenceError.invalidMonthlyDay(day)
            }
            try validateWallClock(hour: hour, minute: minute)
        }
    }

    /// Returns the first scheduled instant strictly after `instant`.
    func nextOccurrence(
        strictlyAfter instant: Date,
        recurrence: ScheduledTaskRecurrence,
        timeZoneIdentifier: String
    ) throws -> Date? {
        try validate(recurrence, timeZoneIdentifier: timeZoneIdentifier)
        let calendar = try calendar(timeZoneIdentifier: timeZoneIdentifier)

        switch recurrence {
        case let .once(occurrence):
            return occurrence > instant ? occurrence : nil
        case let .interval(minutes, anchor):
            return nextIntervalOccurrence(after: instant, anchor: anchor, minutes: minutes)
        case let .daily(hour, minute):
            return nextWallClockOccurrence(
                after: instant,
                hour: hour,
                minute: minute,
                calendar: calendar
            )
        case let .weekdays(days, hour, minute):
            return nextWeekdayOccurrence(
                after: instant,
                selectedWeekdays: Set(days),
                hour: hour,
                minute: minute,
                calendar: calendar
            )
        case let .weekly(weekday, hour, minute):
            var components = DateComponents()
            components.weekday = weekday
            components.hour = hour
            components.minute = minute
            components.second = 0
            return calendar.nextDate(
                after: instant,
                matching: components,
                matchingPolicy: .nextTime,
                repeatedTimePolicy: .first,
                direction: .forward
            )
        case let .monthly(day, hour, minute):
            return nextMonthlyOccurrence(
                after: instant,
                requestedDay: day,
                hour: hour,
                minute: minute,
                calendar: calendar
            )
        }
    }

    /// Coalesces all due instants into the latest one and returns the next future instant.
    func coalescedOccurrences(
        startingAt firstOccurrence: Date,
        through instant: Date,
        recurrence: ScheduledTaskRecurrence,
        timeZoneIdentifier: String
    ) throws -> ScheduledTaskOccurrenceWindow {
        try validate(recurrence, timeZoneIdentifier: timeZoneIdentifier)
        guard firstOccurrence <= instant else {
            return ScheduledTaskOccurrenceWindow(
                latestDueOccurrence: nil,
                nextOccurrence: firstOccurrence
            )
        }

        if case let .interval(minutes, _) = recurrence {
            let interval = TimeInterval(minutes) * 60
            let elapsed = instant.timeIntervalSince(firstOccurrence)
            let elapsedIntervals = floor(elapsed / interval)
            let latestDueOccurrence = firstOccurrence.addingTimeInterval(elapsedIntervals * interval)
            return ScheduledTaskOccurrenceWindow(
                latestDueOccurrence: latestDueOccurrence,
                nextOccurrence: latestDueOccurrence.addingTimeInterval(interval)
            )
        }

        var latestDueOccurrence = firstOccurrence
        while let nextOccurrence = try nextOccurrence(
            strictlyAfter: latestDueOccurrence,
            recurrence: recurrence,
            timeZoneIdentifier: timeZoneIdentifier
        ) {
            guard nextOccurrence <= instant else {
                return ScheduledTaskOccurrenceWindow(
                    latestDueOccurrence: latestDueOccurrence,
                    nextOccurrence: nextOccurrence
                )
            }
            latestDueOccurrence = nextOccurrence
        }

        return ScheduledTaskOccurrenceWindow(
            latestDueOccurrence: latestDueOccurrence,
            nextOccurrence: nil
        )
    }

    /// Applies the seven-day catch-up policy to an already persisted first due occurrence.
    func catchUp(
        startingAt firstOccurrence: Date?,
        through instant: Date,
        recurrence: ScheduledTaskRecurrence,
        timeZoneIdentifier: String,
        isPaused: Bool,
        maximumAge: TimeInterval = Self.defaultCatchUpAge
    ) throws -> ScheduledTaskCatchUpResult {
        guard maximumAge >= 0 else {
            throw ScheduledTaskRecurrenceError.invalidCatchUpAge(maximumAge)
        }
        try validate(recurrence, timeZoneIdentifier: timeZoneIdentifier)
        guard let firstOccurrence else {
            return ScheduledTaskCatchUpResult(action: .none, nextOccurrence: nil)
        }

        let window = try coalescedOccurrences(
            startingAt: firstOccurrence,
            through: instant,
            recurrence: recurrence,
            timeZoneIdentifier: timeZoneIdentifier
        )
        guard let latestDueOccurrence = window.latestDueOccurrence else {
            return ScheduledTaskCatchUpResult(action: .none, nextOccurrence: window.nextOccurrence)
        }

        let action: ScheduledTaskCatchUpAction
        if isPaused {
            action = .skipPaused(latestDueOccurrence)
        } else if instant.timeIntervalSince(latestDueOccurrence) <= maximumAge {
            action = .run(latestDueOccurrence)
        } else if recurrence.isOneShot {
            action = .completeStaleOneShot(latestDueOccurrence)
        } else {
            action = .skipStale(latestDueOccurrence)
        }
        return ScheduledTaskCatchUpResult(action: action, nextOccurrence: window.nextOccurrence)
    }

    static func latestCoalescedOccurrence(existing: Date?, candidate: Date?) -> Date? {
        switch (existing, candidate) {
        case let (existing?, candidate?):
            max(existing, candidate)
        case let (existing?, nil):
            existing
        case let (nil, candidate?):
            candidate
        case (nil, nil):
            nil
        }
    }
}

private extension ScheduledTaskRecurrenceCalculator {
    func validateWeekdaySelection(_ weekdays: [Int]) throws {
        guard !weekdays.isEmpty else {
            throw ScheduledTaskRecurrenceError.emptyWeekdaySelection
        }
        guard weekdays == Array(Set(weekdays)).sorted() else {
            throw ScheduledTaskRecurrenceError.noncanonicalWeekdaySelection(weekdays)
        }
        if let invalidWeekday = weekdays.first(where: { !(1 ... 7).contains($0) }) {
            throw ScheduledTaskRecurrenceError.invalidWeekday(invalidWeekday)
        }
    }

    func validateWallClock(hour: Int, minute: Int) throws {
        guard (0 ... 23).contains(hour) else {
            throw ScheduledTaskRecurrenceError.invalidHour(hour)
        }
        guard (0 ... 59).contains(minute) else {
            throw ScheduledTaskRecurrenceError.invalidMinute(minute)
        }
    }

    func timeZone(identifier: String) throws -> TimeZone {
        let isKnownIdentifier = TimeZone.knownTimeZoneIdentifiers.contains(identifier)
        let isExplicitUTC = identifier == "UTC"
        let isIANAOrLinkIdentifier = identifier.contains("/")
        guard isKnownIdentifier || isExplicitUTC || isIANAOrLinkIdentifier,
              let timeZone = TimeZone(identifier: identifier)
        else {
            throw ScheduledTaskRecurrenceError.invalidTimeZoneIdentifier(identifier)
        }
        return timeZone
    }

    func calendar(timeZoneIdentifier: String) throws -> Calendar {
        var calendar = Calendar(identifier: calendarIdentifier)
        calendar.timeZone = try timeZone(identifier: timeZoneIdentifier)
        return calendar
    }

    func nextIntervalOccurrence(after instant: Date, anchor: Date, minutes: Int) -> Date {
        guard instant >= anchor else {
            return anchor
        }
        let interval = TimeInterval(minutes) * 60
        let elapsedIntervals = floor(instant.timeIntervalSince(anchor) / interval) + 1
        return anchor.addingTimeInterval(elapsedIntervals * interval)
    }

    func nextWallClockOccurrence(
        after instant: Date,
        hour: Int,
        minute: Int,
        calendar: Calendar
    ) -> Date? {
        calendar.nextDate(
            after: instant,
            matching: DateComponents(hour: hour, minute: minute, second: 0),
            matchingPolicy: .nextTime,
            repeatedTimePolicy: .first,
            direction: .forward
        )
    }

    func nextWeekdayOccurrence(
        after instant: Date,
        selectedWeekdays: Set<Int>,
        hour: Int,
        minute: Int,
        calendar: Calendar
    ) -> Date? {
        var searchInstant = instant
        for _ in 0 ..< 7 {
            guard let candidate = nextWallClockOccurrence(
                after: searchInstant,
                hour: hour,
                minute: minute,
                calendar: calendar
            ) else {
                return nil
            }
            let weekday = calendar.component(.weekday, from: candidate)
            if selectedWeekdays.contains(weekday) {
                return candidate
            }
            searchInstant = candidate
        }
        return nil
    }

    func nextMonthlyOccurrence(
        after instant: Date,
        requestedDay: Int,
        hour: Int,
        minute: Int,
        calendar: Calendar
    ) -> Date? {
        let instantComponents = calendar.dateComponents([.year, .month], from: instant)
        guard var monthStart = calendar.date(
            from: DateComponents(year: instantComponents.year, month: instantComponents.month, day: 1)
        ) else {
            return nil
        }

        while true {
            guard let dayRange = calendar.range(of: .day, in: .month, for: monthStart),
                  let candidate = monthlyCandidate(
                      monthStart: monthStart,
                      day: min(requestedDay, dayRange.count),
                      hour: hour,
                      minute: minute,
                      calendar: calendar
                  )
            else {
                return nil
            }
            if candidate > instant {
                return candidate
            }
            guard let nextMonth = calendar.date(byAdding: .month, value: 1, to: monthStart),
                  nextMonth > monthStart
            else {
                return nil
            }
            monthStart = nextMonth
        }
    }

    func monthlyCandidate(
        monthStart: Date,
        day: Int,
        hour: Int,
        minute: Int,
        calendar: Calendar
    ) -> Date? {
        let monthComponents = calendar.dateComponents([.year, .month], from: monthStart)
        guard let dayStart = calendar.date(
            from: DateComponents(year: monthComponents.year, month: monthComponents.month, day: day)
        ), let nextDay = calendar.date(byAdding: .day, value: 1, to: dayStart)
        else {
            return nil
        }
        let candidate = calendar.nextDate(
            after: dayStart.addingTimeInterval(-1),
            matching: DateComponents(hour: hour, minute: minute, second: 0),
            matchingPolicy: .nextTime,
            repeatedTimePolicy: .first,
            direction: .forward
        )
        guard let candidate, candidate < nextDay else {
            return nil
        }
        return candidate
    }
}
