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

    func testScheduledTaskCardEqualityIgnoresItsActionsAndComparesTheRenderedTask() {
        let task = makeRowPresentation(title: "Nightly sweep")
        let card = makeScheduledCard(task: task)

        XCTAssertEqual(card, makeScheduledCard(task: task, onOpen: { XCTFail("unused") }))
        XCTAssertNotEqual(card, makeScheduledCard(task: task, isRunNowPending: true))
        XCTAssertNotEqual(card, makeScheduledCard(task: task, isSelected: true))
        XCTAssertNotEqual(card, makeScheduledCard(task: task, providerName: "Codex"))
        XCTAssertNotEqual(card, makeScheduledCard(task: task, focusID: "scheduled-edit-other"))
        XCTAssertNotEqual(card, makeScheduledCard(task: makeRowPresentation(title: "Renamed")))
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
            isWaitingForTarget: false,
            nextOccurrenceAt: Date(timeIntervalSince1970: 1_752_408_840),
            pauseReason: nil,
            lastError: nil,
            hasActiveRun: false,
            modifiedAt: Date(timeIntervalSince1970: 1_752_400_000)
        )
    }
}

/// `ScheduledTaskCard` stores a `FocusState` binding, which only a `View` can vend. SwiftUI
/// logs that the binding is read outside a `View` body and is therefore constant — which is
/// what an `==` fixture wants, since the binding is excluded from `==`.
@MainActor
private func makeScheduledCard(
    task: ScheduledTaskRowPresentation,
    providerName: String = "Claude",
    isRunNowPending: Bool = false,
    isSelected: Bool = false,
    focusID: String = "scheduled-edit-definition",
    onOpen: @escaping () -> Void = {}
) -> ScheduledTaskCard {
    ScheduledTaskCardEqualityHost(
        task: task,
        providerName: providerName,
        isRunNowPending: isRunNowPending,
        isSelected: isSelected,
        focusID: focusID,
        onOpen: onOpen
    ).card
}

private struct ScheduledTaskCardEqualityHost: View {
    let task: ScheduledTaskRowPresentation
    let providerName: String
    let isRunNowPending: Bool
    let isSelected: Bool
    let focusID: String
    let onOpen: () -> Void

    @FocusState private var focus: String?

    var card: ScheduledTaskCard {
        ScheduledTaskCard(
            task: task,
            providerName: providerName,
            isRunNowPending: isRunNowPending,
            isSelected: isSelected,
            onOpen: onOpen,
            onPause: {},
            onResume: {},
            onRunNow: {},
            onDelete: {},
            cardFocus: $focus,
            cardFocusID: focusID
        )
    }

    var body: some View {
        card
    }
}
