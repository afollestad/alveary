import SwiftUI
import XCTest

@testable import Alveary

extension SnapshotTests {
    func testPullRequestsScreenEmpty() async throws {
        let fixture = try await PullRequestsSnapshotFixture(summaries: [])

        await assertMacModelSnapshot(
            modelContainer: fixture.container,
            size: CGSize(width: 1_120, height: 900),
            named: "pull_requests_empty"
        ) { fixture.screen }
    }

    func testPullRequestsScreenPopulated() async throws {
        let fixture = try await PullRequestsSnapshotFixture()

        await assertMacModelSnapshot(
            modelContainer: fixture.container,
            size: CGSize(width: 1_120, height: 900),
            named: "pull_requests_populated"
        ) { fixture.screen }
    }

    func testPullRequestsScreenPopulatedDark() async throws {
        let fixture = try await PullRequestsSnapshotFixture()

        await assertMacModelSnapshot(
            modelContainer: fixture.container,
            size: CGSize(width: 1_120, height: 900),
            named: "pull_requests_populated_dark",
            colorScheme: .dark
        ) { fixture.screen }
    }

    func testPullRequestsScreenPopulatedNarrow() async throws {
        let fixture = try await PullRequestsSnapshotFixture()

        await assertMacModelSnapshot(
            modelContainer: fixture.container,
            size: CGSize(width: 620, height: 700),
            named: "pull_requests_populated_narrow"
        ) { fixture.screen }
    }

    func testPullRequestsScreenLinkedThreads() async throws {
        let fixture = try await PullRequestsSnapshotFixture(includeLinkedThreads: true)

        await assertMacModelSnapshot(
            modelContainer: fixture.container,
            size: CGSize(width: 1_120, height: 900),
            named: "pull_requests_linked_threads"
        ) { fixture.screen }
    }

    func testPullRequestsScreenLinkedThreadsDark() async throws {
        let fixture = try await PullRequestsSnapshotFixture(includeLinkedThreads: true)

        await assertMacModelSnapshot(
            modelContainer: fixture.container,
            size: CGSize(width: 1_120, height: 900),
            named: "pull_requests_linked_threads_dark",
            colorScheme: .dark
        ) { fixture.screen }
    }

    func testPullRequestsScreenLinkedThreadsNarrow() async throws {
        let fixture = try await PullRequestsSnapshotFixture(includeLinkedThreads: true)

        await assertMacModelSnapshot(
            modelContainer: fixture.container,
            size: CGSize(width: 620, height: 700),
            named: "pull_requests_linked_threads_narrow"
        ) { fixture.screen }
    }

    func testPullRequestsScreenLoadMoreFooter() async throws {
        let fixture = try await PullRequestsSnapshotFixture(hasNextPage: true)

        await assertMacModelSnapshot(
            modelContainer: fixture.container,
            size: CGSize(width: 1_120, height: 900),
            named: "pull_requests_load_more_footer"
        ) { fixture.screen }
    }

    func testPullRequestsScreenNoSearchMatches() async throws {
        let fixture = try await PullRequestsSnapshotFixture()
        fixture.viewModel.searchQuery = "nothing matches this"

        await assertMacModelSnapshot(
            modelContainer: fixture.container,
            size: CGSize(width: 1_120, height: 900),
            named: "pull_requests_no_search_matches"
        ) { fixture.screen }
    }

    func testPullRequestsScreenNotInstalled() async throws {
        let fixture = try await PullRequestsSnapshotFixture(failure: .ghNotInstalled, loadInitially: false)
        XCTAssertEqual(fixture.viewModel.loadPhase, .idle)
        let host = PullRequestsUnavailableSnapshotHost(viewModel: fixture.viewModel, modelContainer: fixture.container)
        do {
            try await host.requireNotInstalled {
                fixture.service.completedBuckets == fixture.viewModel.selectedFilter.requiredBuckets
            }
            host.assertSnapshot(named: "pull_requests_not_installed", file: #filePath, testName: #function)
        } catch {
            await host.close()
            throw error
        }
        await host.close()
    }

    func testPullRequestsReviewingSectionsPopulated() async throws {
        let fixture = try await PullRequestsSnapshotFixture()

        assertMacSnapshot(
            PullRequestsSectionedList(
                items: fixture.viewModel.visibleListItems(for: .reviewing),
                avatarLoader: fixture.viewModel.avatarLoader,
                activeDetailID: nil,
                onSelect: { _ in }
            )
            .padding(20),
            size: CGSize(width: 1_120, height: 460),
            named: "pull_requests_reviewing_sections"
        )
    }

    func testPullRequestsFilterChipsReviewingSelection() async throws {
        let fixture = try await PullRequestsSnapshotFixture()
        fixture.viewModel.selectFilter(.reviewing)

        assertMacSnapshot(
            PullRequestsScreenHeader(viewModel: fixture.viewModel),
            size: CGSize(width: 900, height: 72),
            named: "pull_requests_header_reviewing"
        )
    }

    func testPullRequestsScreenPopulatedSqueezed() async throws {
        let fixture = try await PullRequestsSnapshotFixture()

        await assertMacModelSnapshot(
            modelContainer: fixture.container,
            size: CGSize(width: 420, height: 700),
            named: "pull_requests_populated_squeezed"
        ) { fixture.screen }
    }

    /// Squeezed, the ladder gives up the field's width before the chips: the field
    /// compresses well below its 220 cap while every chip stays visible. 500 sits clear
    /// of the rung boundary (~480), where text measured a point wider on CI's renderer
    /// picked the dropdown instead.
    func testPullRequestsHeaderKeepsChipsBySqueezingTheField() async throws {
        let fixture = try await PullRequestsSnapshotFixture()
        fixture.viewModel.selectFilter(.reviewing)

        assertMacSnapshot(
            PullRequestsScreenHeader(viewModel: fixture.viewModel),
            size: CGSize(width: 500, height: 72),
            named: "pull_requests_header_chips_squeezed_field"
        )
    }

    /// The last rung: chips folded, search field traded for a button. 300 points is
    /// narrower than `RightPaneWidthPolicy.minimumMainPaneWidth`, which the pane really
    /// does reach once the window cannot satisfy both panes' minimums.
    func testPullRequestsHeaderCondensed() async throws {
        let fixture = try await PullRequestsSnapshotFixture()
        fixture.viewModel.selectFilter(.reviewing)

        assertMacSnapshot(
            PullRequestsScreenHeader(viewModel: fixture.viewModel),
            size: CGSize(width: 300, height: 72),
            named: "pull_requests_header_condensed"
        )
    }

    /// A collapsed search reports an active query by tinting its glyph with the accent,
    /// so the state survives losing the field itself.
    func testPullRequestsHeaderCondensedActiveSearch() async throws {
        let fixture = try await PullRequestsSnapshotFixture()
        fixture.viewModel.selectFilter(.reviewing)
        fixture.viewModel.searchQuery = "release"

        assertMacSnapshot(
            PullRequestsScreenHeader(viewModel: fixture.viewModel),
            size: CGSize(width: 300, height: 72),
            named: "pull_requests_header_condensed_active_search"
        )
    }

    /// The dropdown truncates and holds the leading edge instead of being pushed out.
    func testPullRequestsHeaderAtExtremeNarrowWidth() async throws {
        let fixture = try await PullRequestsSnapshotFixture()
        fixture.viewModel.selectFilter(.reviewing)

        assertMacSnapshot(
            PullRequestsScreenHeader(viewModel: fixture.viewModel),
            size: CGSize(width: 220, height: 72),
            named: "pull_requests_header_extreme_narrow"
        )
    }

    // Content-only: live popover hosts crash on macOS 26 (see AlvearyTests/AGENTS.md).
    func testPullRequestsFilterPopoverContent() async throws {
        let fixture = try await PullRequestsSnapshotFixture()
        fixture.viewModel.selectStatusFilter(.merged)

        assertMacSnapshot(
            PullRequestsFilterPopover(viewModel: fixture.viewModel),
            size: CGSize(width: 260, height: 300),
            named: "pull_requests_filter_popover"
        )
    }

    func testPullRequestsScreenWarningBanner() async throws {
        let fixture = try await PullRequestsSnapshotFixture(
            warnings: ["Resource protected by organization SAML enforcement."]
        )

        await assertMacModelSnapshot(
            modelContainer: fixture.container,
            size: CGSize(width: 1_120, height: 900),
            named: "pull_requests_warning_banner"
        ) { fixture.screen }
    }
}
