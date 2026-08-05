import SwiftUI
import XCTest

@testable import Alveary

@MainActor
final class PaneHeaderTests: XCTestCase {
    /// `minimumMainPaneWidth` is a preference, not a floor: `bounds` yields it to the right
    /// pane's own minimum once the window cannot satisfy both. This is why the header's
    /// arrangement is chosen by fit rather than by a threshold picked around 420 — the pane
    /// reaches widths where even the last rung has to spill.
    func testTheMiddlePaneIsSqueezedBelowItsStatedMinimum() {
        let bounds = RightPaneWidthPolicy.bounds(availableWidth: 600)
        let squeezedMainPane = 600 - CGFloat(bounds.lowerBound) - RightPaneWidthPolicy.resizeHandleThickness

        XCTAssertLessThan(squeezedMainPane, RightPaneWidthPolicy.minimumMainPaneWidth)
        XCTAssertLessThan(squeezedMainPane, 300)
    }

    func testFilterPreservesOptionOrderAndTitles() {
        let filter = PaneHeaderFilter(
            options: PullRequestsFilter.allCases,
            selection: .constant(.reviewing),
            title: \.rawValue,
            accessibilityLabel: "Pull request filter"
        )

        XCTAssertEqual(filter.items.map(\.title), ["All", "Reviewing", "Authored"])
    }

    func testFilterMarksOnlyTheSelectedOption() {
        let filter = PaneHeaderFilter(
            options: PullRequestsFilter.allCases,
            selection: .constant(.reviewing),
            title: \.rawValue,
            accessibilityLabel: "Pull request filter"
        )

        XCTAssertEqual(filter.items.filter(\.isSelected).map(\.title), ["Reviewing"])
        XCTAssertEqual(filter.selectedTitle, "Reviewing")
    }

    func testSelectingAnItemWritesThroughTheBinding() {
        var selection = PullRequestsFilter.all
        let filter = PaneHeaderFilter(
            options: PullRequestsFilter.allCases,
            selection: Binding(get: { selection }, set: { selection = $0 }),
            title: \.rawValue,
            accessibilityLabel: "Pull request filter"
        )

        filter.items[2].select()

        XCTAssertEqual(selection, .authored)
    }

    /// Options need not be `CaseIterable` — the Archived screen computes its project
    /// filter options from live data — so erasure must not assume a fixed case list.
    func testFilterAcceptsDynamicOptions() {
        let filter = PaneHeaderFilter(
            options: [ArchivedProjectFilter.all, .noProject, .project(path: "/tmp/demo")],
            selection: .constant(.project(path: "/tmp/demo")),
            title: { filter in
                switch filter {
                case .all: "All Projects"
                case .noProject: "No Project"
                case let .project(path): path
                }
            },
            accessibilityLabel: "Filter by project"
        )

        XCTAssertEqual(filter.selectedTitle, "/tmp/demo")
    }

    /// An empty selection would otherwise render an unlabeled dropdown.
    func testSelectedTitleIsEmptyWhenNothingMatches() {
        let filter = PaneHeaderFilter(
            options: [ScheduledTasksFilter.active],
            selection: .constant(.paused),
            title: \.rawValue,
            accessibilityLabel: "Scheduled task filter"
        )

        XCTAssertEqual(filter.selectedTitle, "")
    }

    /// Pull Requests caps its field tighter than the default, and the cap has to stay above
    /// the floor or the field could never render at a width the header would accept.
    func testEverySearchCapClearsTheSharedMinimum() {
        let caps = [PaneHeaderSearch(placeholder: "", text: .constant("")).maximumWidth, 220]

        for cap in caps {
            XCTAssertGreaterThan(cap, PaneHeaderLayout.searchMinimumWidth)
        }
    }
}
