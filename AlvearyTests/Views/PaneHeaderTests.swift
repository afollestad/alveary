import AppKit
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
            options: [ArchivedProjectFilter.all, .noProject, .project(id: "/tmp/demo")],
            selection: .constant(.project(id: "/tmp/demo")),
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

    func testRenderedSearchRespectsDefaultAndCustomCaps() throws {
        let searches = [
            PaneHeaderSearch(placeholder: "Search cases", text: .constant("")),
            PaneHeaderSearch(placeholder: "Search cases", text: .constant(""), maximumWidth: 220)
        ]
        var fieldWidths: [CGFloat] = []
        for search in searches {
            XCTAssertGreaterThan(search.maximumWidth, PaneHeaderLayout.searchMinimumWidth)
            let host = NSHostingView(rootView: ResponsivePaneHeader(search: search) { _ in EmptyView() })
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 900, height: PaneHeaderLayout.height),
                styleMask: [.borderless], backing: .buffered, defer: false
            )
            window.isReleasedWhenClosed = false
            window.contentView = host
            defer {
                window.contentView = nil
                window.close()
            }
            host.layoutSubtreeIfNeeded()
            let field = try XCTUnwrap(searchFields(in: host).first { $0.placeholderString == "Search cases" })
            XCTAssertGreaterThan(field.frame.width, 0)
            XCTAssertLessThanOrEqual(field.frame.width, search.maximumWidth)
            fieldWidths.append(field.frame.width)
        }
        XCTAssertGreaterThan(fieldWidths[0], fieldWidths[1], "The tighter cap must constrain the actual mounted field")
    }

    private func searchFields(in view: NSView) -> [NSTextField] {
        (view as? NSTextField).map { [$0] } ?? view.subviews.flatMap { searchFields(in: $0) }
    }
}
