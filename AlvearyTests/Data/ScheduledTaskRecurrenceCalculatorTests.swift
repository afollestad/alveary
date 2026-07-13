import Foundation
import XCTest

@testable import Alveary

final class ScheduledTaskRecurrenceCalculatorTests: XCTestCase {
    private let calculator = ScheduledTaskRecurrenceCalculator()

    func testIntervalRequiresAtLeastOneMinute() throws {
        let anchor = date("2026-01-01T00:00:00Z")

        XCTAssertThrowsError(
            try calculator.nextOccurrence(
                strictlyAfter: anchor,
                recurrence: .interval(minutes: 0, anchor: anchor),
                timeZoneIdentifier: "Etc/UTC"
            )
        ) { error in
            XCTAssertEqual(
                error as? ScheduledTaskRecurrenceError,
                .intervalBelowMinimum(minutes: 0, minimum: 1)
            )
        }

        XCTAssertEqual(
            try calculator.nextOccurrence(
                strictlyAfter: anchor,
                recurrence: .interval(minutes: 1, anchor: anchor),
                timeZoneIdentifier: "Etc/UTC"
            ),
            date("2026-01-01T00:01:00Z")
        )
    }

    func testIntervalRemainsAnchoredToPriorScheduledInstant() throws {
        let anchor = date("2026-01-01T00:00:00Z")

        XCTAssertEqual(
            try calculator.nextOccurrence(
                strictlyAfter: date("2026-01-01T00:02:30Z"),
                recurrence: .interval(minutes: 1, anchor: anchor),
                timeZoneIdentifier: "Etc/UTC"
            ),
            date("2026-01-01T00:03:00Z")
        )
    }

    func testOnceOnlyReturnsOccurrenceStrictlyAfterInstant() throws {
        let occurrence = date("2026-01-01T12:00:00Z")
        let recurrence = ScheduledTaskRecurrence.once(occurrence)

        XCTAssertEqual(
            try calculator.nextOccurrence(
                strictlyAfter: date("2026-01-01T11:59:59Z"),
                recurrence: recurrence,
                timeZoneIdentifier: "Etc/UTC"
            ),
            occurrence
        )
        XCTAssertNil(
            try calculator.nextOccurrence(
                strictlyAfter: occurrence,
                recurrence: recurrence,
                timeZoneIdentifier: "Etc/UTC"
            )
        )
    }

    func testDailyAdvancesNonexistentDSTTimeToNextValidLocalInstant() throws {
        XCTAssertEqual(
            try calculator.nextOccurrence(
                strictlyAfter: date("2026-03-08T06:00:00Z"),
                recurrence: .daily(hour: 2, minute: 30),
                timeZoneIdentifier: "America/Chicago"
            ),
            date("2026-03-08T08:00:00Z")
        )
    }

    func testDailyUsesFirstOccurrenceOfRepeatedDSTTime() throws {
        let firstOccurrence = try XCTUnwrap(
            calculator.nextOccurrence(
                strictlyAfter: date("2026-11-01T05:00:00Z"),
                recurrence: .daily(hour: 1, minute: 30),
                timeZoneIdentifier: "America/Chicago"
            )
        )

        XCTAssertEqual(firstOccurrence, date("2026-11-01T06:30:00Z"))
        XCTAssertEqual(
            try calculator.nextOccurrence(
                strictlyAfter: firstOccurrence,
                recurrence: .daily(hour: 1, minute: 30),
                timeZoneIdentifier: "America/Chicago"
            ),
            date("2026-11-02T07:30:00Z")
        )
    }

    func testDailyPreservesWallClockTimeAcrossDSTOffsetChange() throws {
        let recurrence = ScheduledTaskRecurrence.daily(hour: 9, minute: 15)
        let beforeTransition = try XCTUnwrap(
            calculator.nextOccurrence(
                strictlyAfter: date("2026-03-07T06:00:00Z"),
                recurrence: recurrence,
                timeZoneIdentifier: "America/Chicago"
            )
        )
        let afterTransition = try calculator.nextOccurrence(
            strictlyAfter: beforeTransition,
            recurrence: recurrence,
            timeZoneIdentifier: "America/Chicago"
        )

        XCTAssertEqual(beforeTransition, date("2026-03-07T15:15:00Z"))
        XCTAssertEqual(afterTransition, date("2026-03-08T14:15:00Z"))
    }

    func testWeekdaysSkipSaturdayAndSunday() throws {
        XCTAssertEqual(
            try calculator.nextOccurrence(
                strictlyAfter: date("2026-07-10T17:00:00Z"),
                recurrence: .weekdays(hour: 9, minute: 0),
                timeZoneIdentifier: "America/Chicago"
            ),
            date("2026-07-13T14:00:00Z")
        )
    }

    func testWeekdaysUseExactSelectedDays() throws {
        let recurrence = ScheduledTaskRecurrence.weekdays(days: [2, 4, 7], hour: 9, minute: 0)

        let wednesday = try XCTUnwrap(
            calculator.nextOccurrence(
                strictlyAfter: date("2026-07-13T14:00:00Z"),
                recurrence: recurrence,
                timeZoneIdentifier: "America/Chicago"
            )
        )
        let saturday = try calculator.nextOccurrence(
            strictlyAfter: wednesday,
            recurrence: recurrence,
            timeZoneIdentifier: "America/Chicago"
        )

        XCTAssertEqual(wednesday, date("2026-07-15T14:00:00Z"))
        XCTAssertEqual(saturday, date("2026-07-18T14:00:00Z"))
    }

    func testWeekdaysRequireNonemptyCanonicalSelection() {
        XCTAssertThrowsError(
            try calculator.validate(.weekdays(days: [], hour: 9, minute: 0), timeZoneIdentifier: "Etc/UTC")
        ) { error in
            XCTAssertEqual(error as? ScheduledTaskRecurrenceError, .emptyWeekdaySelection)
        }
        XCTAssertThrowsError(
            try calculator.validate(.weekdays(days: [4, 2], hour: 9, minute: 0), timeZoneIdentifier: "Etc/UTC")
        ) { error in
            XCTAssertEqual(error as? ScheduledTaskRecurrenceError, .noncanonicalWeekdaySelection([4, 2]))
        }
        XCTAssertThrowsError(
            try calculator.validate(.weekdays(days: [2, 8], hour: 9, minute: 0), timeZoneIdentifier: "Etc/UTC")
        ) { error in
            XCTAssertEqual(error as? ScheduledTaskRecurrenceError, .invalidWeekday(8))
        }
    }

    func testWeeklyUsesFoundationCalendarWeekday() throws {
        XCTAssertEqual(
            try calculator.nextOccurrence(
                strictlyAfter: date("2026-07-12T12:00:00Z"),
                recurrence: .weekly(weekday: 2, hour: 8, minute: 30),
                timeZoneIdentifier: "America/Chicago"
            ),
            date("2026-07-13T13:30:00Z")
        )
    }

    func testWeeklyAdvancesNonexistentDSTTimeToNextValidLocalInstant() throws {
        XCTAssertEqual(
            try calculator.nextOccurrence(
                strictlyAfter: date("2026-03-08T06:00:00Z"),
                recurrence: .weekly(weekday: 1, hour: 2, minute: 30),
                timeZoneIdentifier: "America/Chicago"
            ),
            date("2026-03-08T08:00:00Z")
        )
    }

    func testWeeklyUsesFirstOccurrenceOfRepeatedDSTTime() throws {
        XCTAssertEqual(
            try calculator.nextOccurrence(
                strictlyAfter: date("2026-11-01T05:00:00Z"),
                recurrence: .weekly(weekday: 1, hour: 1, minute: 30),
                timeZoneIdentifier: "America/Chicago"
            ),
            date("2026-11-01T06:30:00Z")
        )
    }

    func testMonthlyClampsDayToFinalDayOfMonth() throws {
        let recurrence = ScheduledTaskRecurrence.monthly(day: 31, hour: 9, minute: 0)
        let februaryOccurrence = try XCTUnwrap(
            calculator.nextOccurrence(
                strictlyAfter: date("2026-01-31T15:00:00Z"),
                recurrence: recurrence,
                timeZoneIdentifier: "America/Chicago"
            )
        )
        let marchOccurrence = try calculator.nextOccurrence(
            strictlyAfter: februaryOccurrence,
            recurrence: recurrence,
            timeZoneIdentifier: "America/Chicago"
        )

        XCTAssertEqual(februaryOccurrence, date("2026-02-28T15:00:00Z"))
        XCTAssertEqual(marchOccurrence, date("2026-03-31T14:00:00Z"))
    }

    func testMonthlyAdvancesNonexistentDSTTimeToNextValidLocalInstant() throws {
        XCTAssertEqual(
            try calculator.nextOccurrence(
                strictlyAfter: date("2026-03-08T06:00:00Z"),
                recurrence: .monthly(day: 8, hour: 2, minute: 30),
                timeZoneIdentifier: "America/Chicago"
            ),
            date("2026-03-08T08:00:00Z")
        )
    }

    func testMonthlyUsesFirstOccurrenceOfRepeatedDSTTime() throws {
        XCTAssertEqual(
            try calculator.nextOccurrence(
                strictlyAfter: date("2026-11-01T05:00:00Z"),
                recurrence: .monthly(day: 1, hour: 1, minute: 30),
                timeZoneIdentifier: "America/Chicago"
            ),
            date("2026-11-01T06:30:00Z")
        )
    }

    func testCoalescingKeepsOnlyLatestDueOccurrenceAndNextFutureOccurrence() throws {
        let result = try calculator.coalescedOccurrences(
            startingAt: date("2026-01-01T00:00:00Z"),
            through: date("2026-01-01T00:03:30Z"),
            recurrence: .interval(minutes: 1, anchor: date("2026-01-01T00:00:00Z")),
            timeZoneIdentifier: "Etc/UTC"
        )

        XCTAssertEqual(result.latestDueOccurrence, date("2026-01-01T00:03:00Z"))
        XCTAssertEqual(result.nextOccurrence, date("2026-01-01T00:04:00Z"))
    }

    func testCatchUpRunsLatestOccurrenceAtInclusiveSevenDayBoundary() throws {
        let occurrence = date("2026-01-01T00:00:00Z")
        let result = try calculator.catchUp(
            startingAt: occurrence,
            through: date("2026-01-08T00:00:00Z"),
            recurrence: .once(occurrence),
            timeZoneIdentifier: "Etc/UTC",
            isPaused: false
        )

        XCTAssertEqual(result.action, .run(occurrence))
        XCTAssertNil(result.nextOccurrence)
    }

    func testCatchUpCompletesStaleOneShotWithoutRunning() throws {
        let occurrence = date("2026-01-01T00:00:00Z")
        let result = try calculator.catchUp(
            startingAt: occurrence,
            through: date("2026-01-08T00:00:01Z"),
            recurrence: .once(occurrence),
            timeZoneIdentifier: "Etc/UTC",
            isPaused: false
        )

        XCTAssertEqual(result.action, .completeStaleOneShot(occurrence))
        XCTAssertNil(result.nextOccurrence)
    }

    func testCatchUpSkipsPausedOccurrences() throws {
        let result = try calculator.catchUp(
            startingAt: date("2026-01-01T09:00:00Z"),
            through: date("2026-01-03T12:00:00Z"),
            recurrence: .daily(hour: 9, minute: 0),
            timeZoneIdentifier: "Etc/UTC",
            isPaused: true
        )

        XCTAssertEqual(result.action, .skipPaused(date("2026-01-03T09:00:00Z")))
        XCTAssertEqual(result.nextOccurrence, date("2026-01-04T09:00:00Z"))
    }

    func testCatchUpSkipsStaleRecurringOccurrence() throws {
        let result = try calculator.catchUp(
            startingAt: date("2026-01-31T09:00:00Z"),
            through: date("2026-02-20T12:00:00Z"),
            recurrence: .monthly(day: 31, hour: 9, minute: 0),
            timeZoneIdentifier: "Etc/UTC",
            isPaused: false
        )

        XCTAssertEqual(result.action, .skipStale(date("2026-01-31T09:00:00Z")))
        XCTAssertEqual(result.nextOccurrence, date("2026-02-28T09:00:00Z"))
    }

    func testLatestCoalescedOccurrenceKeepsNewestCandidate() {
        let earlier = date("2026-01-01T00:00:00Z")
        let later = date("2026-01-02T00:00:00Z")

        XCTAssertEqual(
            ScheduledTaskRecurrenceCalculator.latestCoalescedOccurrence(
                existing: later,
                candidate: earlier
            ),
            later
        )
        XCTAssertEqual(
            ScheduledTaskRecurrenceCalculator.latestCoalescedOccurrence(
                existing: earlier,
                candidate: later
            ),
            later
        )
        XCTAssertEqual(
            ScheduledTaskRecurrenceCalculator.latestCoalescedOccurrence(
                existing: nil,
                candidate: earlier
            ),
            earlier
        )
    }

    func testValidationRejectsInvalidStructuredFieldsAndTimeZone() {
        XCTAssertThrowsError(
            try calculator.validate(.daily(hour: 24, minute: 0), timeZoneIdentifier: "Etc/UTC")
        )
        XCTAssertThrowsError(
            try calculator.validate(.weekly(weekday: 0, hour: 9, minute: 0), timeZoneIdentifier: "Etc/UTC")
        )
        XCTAssertThrowsError(
            try calculator.validate(.monthly(day: 32, hour: 9, minute: 0), timeZoneIdentifier: "Etc/UTC")
        )
        XCTAssertThrowsError(
            try calculator.validate(.daily(hour: 9, minute: 0), timeZoneIdentifier: "Not/A-Time-Zone")
        )
    }

    func testValidationAcceptsCanonicalAndIANAIdentifiers() throws {
        try calculator.validate(.daily(hour: 9, minute: 0), timeZoneIdentifier: "America/Chicago")
        try calculator.validate(.daily(hour: 9, minute: 0), timeZoneIdentifier: "UTC")
        try calculator.validate(.daily(hour: 9, minute: 0), timeZoneIdentifier: "Etc/UTC")
        try calculator.validate(.daily(hour: 9, minute: 0), timeZoneIdentifier: "US/Central")
    }

    func testValidationRejectsAmbiguousAndOffsetStyleTimeZoneIdentifiers() {
        for identifier in ["CST", "GMT+1", "GMT+0100"] {
            XCTAssertThrowsError(
                try calculator.validate(.daily(hour: 9, minute: 0), timeZoneIdentifier: identifier),
                "Expected \(identifier) to be rejected"
            )
        }
    }

    func testStructuredRecurrencesRoundTripThroughCodable() throws {
        let recurrences: [ScheduledTaskRecurrence] = [
            .once(date("2026-01-01T12:00:00Z")),
            .interval(minutes: 15, anchor: date("2026-01-01T12:00:00Z")),
            .daily(hour: 9, minute: 30),
            .weekdays(days: [2, 4, 6], hour: 10, minute: 45),
            .weekly(weekday: 2, hour: 8, minute: 15),
            .monthly(day: 31, hour: 17, minute: 0)
        ]

        for recurrence in recurrences {
            let encoded = try JSONEncoder().encode(recurrence)
            XCTAssertEqual(try JSONDecoder().decode(ScheduledTaskRecurrence.self, from: encoded), recurrence)
        }
        XCTAssertEqual(recurrences.map(\.kind), ScheduledTaskRecurrence.Kind.allCases)
    }

    func testWeekdaysDecodeLegacyPayloadWithoutExplicitDays() throws {
        let payload = Data(#"{"weekdays":{"hour":9,"minute":30}}"#.utf8)

        XCTAssertEqual(
            try JSONDecoder().decode(ScheduledTaskRecurrence.self, from: payload),
            .weekdays(hour: 9, minute: 30)
        )
    }
}

private extension ScheduledTaskRecurrenceCalculatorTests {
    func date(_ value: String) -> Date {
        guard let date = ISO8601DateFormatter().date(from: value) else {
            XCTFail("Invalid test date: \(value)")
            return .distantPast
        }
        return date
    }
}
