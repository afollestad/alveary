import SwiftUI
import XCTest

@testable import Alveary

@MainActor
extension ScheduledTasksViewModelTests {
    // MARK: - Formatter caching

    /// The formatters are cached across calls, so a second call must not serve the first
    /// call's locale or time zone. `recurrenceSummary` is covered for content elsewhere;
    /// this pins the caching itself.
    func testCachedFormattersStayKeyedToTheirLocaleAndTimeZone() {
        let date = Date(timeIntervalSince1970: 1_752_408_840)

        let chicago = ScheduledTaskPresentationFormatting.dateTime(
            date,
            timeZoneIdentifier: "America/Chicago",
            locale: Locale(identifier: "en_US")
        )
        let utc = ScheduledTaskPresentationFormatting.dateTime(
            date,
            timeZoneIdentifier: "UTC",
            locale: Locale(identifier: "en_US")
        )
        let german = ScheduledTaskPresentationFormatting.dateTime(
            date,
            timeZoneIdentifier: "UTC",
            locale: Locale(identifier: "de_DE")
        )

        XCTAssertNotEqual(chicago, utc)
        XCTAssertNotEqual(german, utc)
        // Repeating each call hits the cache and must return the same string.
        XCTAssertEqual(
            chicago,
            ScheduledTaskPresentationFormatting.dateTime(
                date,
                timeZoneIdentifier: "America/Chicago",
                locale: Locale(identifier: "en_US")
            )
        )
        XCTAssertEqual(
            utc,
            ScheduledTaskPresentationFormatting.dateTime(
                date,
                timeZoneIdentifier: "UTC",
                locale: Locale(identifier: "en_US")
            )
        )
    }

    func testCachedWeekdaySymbolsStayKeyedToTheirLocale() {
        let english = Locale(identifier: "en_US")
        let german = Locale(identifier: "de_DE")

        XCTAssertEqual(ScheduledTaskPresentationFormatting.weekdayName(2, locale: english), "Monday")
        XCTAssertEqual(ScheduledTaskPresentationFormatting.weekdayName(2, locale: german), "Montag")
        XCTAssertEqual(ScheduledTaskPresentationFormatting.weekdayName(2, locale: english), "Monday")
        // Full and short symbols come from one cached entry, so both must stay correct.
        XCTAssertEqual(ScheduledTaskPresentationFormatting.shortWeekdayName(2, locale: english), "Mo")
        XCTAssertEqual(ScheduledTaskPresentationFormatting.weekdayName(2, locale: english), "Monday")
    }

    // MARK: - Render stability

    func testScheduledTaskRowEqualityIgnoresItsActionsAndComparesTheRenderedTask() {
        let task = makeRowPresentation(title: "Nightly sweep")
        let row = makeScheduledRow(task: task)

        XCTAssertEqual(row, makeScheduledRow(task: task, onEdit: { XCTFail("unused") }))
        XCTAssertNotEqual(row, makeScheduledRow(task: task, isRunNowPending: true))
        XCTAssertNotEqual(row, makeScheduledRow(task: task, providerName: "Codex"))
        XCTAssertNotEqual(row, makeScheduledRow(task: task, focusID: "scheduled-edit-other"))
        XCTAssertNotEqual(row, makeScheduledRow(task: makeRowPresentation(title: "Renamed")))
    }

    private func makeRowPresentation(title: String) -> ScheduledTaskRowPresentation {
        ScheduledTaskRowPresentation(
            id: "definition",
            revision: 1,
            title: title,
            prompt: "Do the thing",
            state: .active,
            recurrence: .daily(hour: 9, minute: 0),
            timeZoneIdentifier: "UTC",
            providerID: "claude",
            workspaceSummary: "/tmp/project",
            destination: nil,
            targetThreadName: nil,
            isWaitingForTarget: false,
            nextOccurrenceAt: Date(timeIntervalSince1970: 1_752_408_840),
            pauseReason: nil,
            lastError: nil,
            hasActiveRun: false,
            modifiedAt: Date(timeIntervalSince1970: 1_752_400_000)
        )
    }
}

/// `ScheduledTaskRow` stores a `FocusState` binding, which only a `View` can vend. SwiftUI
/// logs that the binding is read outside a `View` body and is therefore constant — which is
/// what an `==` fixture wants, since the binding is excluded from `==`.
@MainActor
private func makeScheduledRow(
    task: ScheduledTaskRowPresentation,
    providerName: String = "Claude",
    isRunNowPending: Bool = false,
    focusID: String = "scheduled-edit-definition",
    onEdit: @escaping () -> Void = {}
) -> ScheduledTaskRow {
    ScheduledTaskRowEqualityHost(
        task: task,
        providerName: providerName,
        isRunNowPending: isRunNowPending,
        focusID: focusID,
        onEdit: onEdit
    ).row
}

private struct ScheduledTaskRowEqualityHost: View {
    let task: ScheduledTaskRowPresentation
    let providerName: String
    let isRunNowPending: Bool
    let focusID: String
    let onEdit: () -> Void

    @FocusState private var focus: String?

    var row: ScheduledTaskRow {
        ScheduledTaskRow(
            task: task,
            providerName: providerName,
            isRunNowPending: isRunNowPending,
            onEdit: onEdit,
            onPause: {},
            onResume: {},
            onRunNow: {},
            onDelete: {},
            editFocus: $focus,
            editFocusID: focusID
        )
    }

    var body: some View {
        row
    }
}
