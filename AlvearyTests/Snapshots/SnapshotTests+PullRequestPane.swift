import SwiftData
import SwiftUI
import XCTest

@testable import Alveary

extension SnapshotTests {
    // Tall enough to show the divider and the appended activity timeline —
    // comment cards, review cards, status-event rows, and review threads.
    // The Overview's linked-owners section queries SwiftData, so every host of
    // it needs a container; an empty store leaves the section unrendered.
    func testPullRequestPaneOverview() async throws {
        await assertMacModelSnapshot(
            modelContainer: try PullRequestPaneSnapshots.makeModelContainer(),
            size: CGSize(width: 460, height: 1_400),
            named: "pull_request_pane_overview"
        ) {
            PullRequestPaneOverview(
                session: PullRequestPaneSnapshots.loadedSession,
                viewModel: PullRequestPaneSnapshots.inertViewModel,
                onOpenFiles: {}
            )
        }
    }

    func testPullRequestPaneOverviewDark() async throws {
        await assertMacModelSnapshot(
            modelContainer: try PullRequestPaneSnapshots.makeModelContainer(),
            size: CGSize(width: 460, height: 1_400),
            named: "pull_request_pane_overview_dark",
            colorScheme: .dark
        ) {
            PullRequestPaneOverview(
                session: PullRequestPaneSnapshots.loadedSession,
                viewModel: PullRequestPaneSnapshots.inertViewModel,
                onOpenFiles: {}
            )
        }
    }

    /// The header pads its trailing edge so the diff stats and the description's
    /// Edit menu share the timeline cards' menu column, which also keeps the menu
    /// out of the scroll indicator's grab region. Without `viewerCanUpdate` the
    /// menu does not render at all, so the other Overview baselines never see it.
    func testPullRequestPaneOverviewEditableDescription() async throws {
        var session = PullRequestPaneSnapshots.loadedSession
        session.detail?.viewerCanUpdate = true

        await assertMacModelSnapshot(
            modelContainer: try PullRequestPaneSnapshots.makeModelContainer(),
            size: CGSize(width: 460, height: 1_400),
            named: "pull_request_pane_overview_editable_description"
        ) {
            PullRequestPaneOverview(
                session: session,
                viewModel: PullRequestPaneSnapshots.inertViewModel,
                onOpenFiles: {}
            )
        }
    }

    /// The linked-owners section: a project and a live thread both linking this
    /// pull request, so the header names both kinds and each glyph renders. The
    /// third thread links nothing and must stay out of the list.
    func testPullRequestPaneOverviewLinkedOwners() async throws {
        let container = try PullRequestPaneSnapshots.makeLinkedOwnersContainer()

        await assertMacModelSnapshot(
            modelContainer: container,
            size: CGSize(width: 460, height: 1_400),
            named: "pull_request_pane_overview_linked_owners"
        ) {
            PullRequestPaneOverview(
                session: PullRequestPaneSnapshots.loadedSession,
                viewModel: PullRequestPaneSnapshots.inertViewModel,
                onOpenFiles: {}
            )
        }
    }

    /// Thread cards float on the hunk's code surface (the row carries the shared
    /// hunk chrome, so the surface flows behind the card instead of a pane-color
    /// band interrupting it), and their interior trailing padding keeps the
    /// three-dot menu out of the scroll indicator's grab region. The shared
    /// fixture's threads are outdated or anchored to paths outside the diff, so
    /// no other Changes baseline renders a thread row.
    func testPullRequestPaneFilesCommentThread() {
        var session = PullRequestPaneSnapshots.loadedSession
        session.detail?.reviewThreads = [PullRequestPaneSnapshots.diffAnchoredThread]

        assertMacSnapshot(
            PullRequestPaneFiles(
                session: session,
                viewModel: PullRequestPaneSnapshots.inertViewModel,
                target: PullRequestPaneSnapshots.target
            ),
            size: CGSize(width: 460, height: 520),
            named: "pull_request_pane_files_comment_thread"
        )
    }

    /// Dark mode is where the surface-continuity behind thread cards is visible:
    /// the code surface and the pane background diverge most there, so a band of
    /// pane color around the card would show as a clear seam.
    func testPullRequestPaneFilesCommentThreadDark() {
        var session = PullRequestPaneSnapshots.loadedSession
        session.detail?.reviewThreads = [PullRequestPaneSnapshots.diffAnchoredThread]

        assertMacSnapshot(
            PullRequestPaneFiles(
                session: session,
                viewModel: PullRequestPaneSnapshots.inertViewModel,
                target: PullRequestPaneSnapshots.target
            ),
            size: CGSize(width: 460, height: 520),
            named: "pull_request_pane_files_comment_thread_dark",
            colorScheme: .dark
        )
    }

    /// The full pane is the only surface where the header's close button, the tab
    /// row's Open-on-GitHub button, and the scroll content meet: both glyphs center
    /// their *ink* on the pane's trailing glyph lane, while the diff stats and footer
    /// button below them stay right-aligned on the 16pt content column. The
    /// Overview-only baselines have neither the header nor the tab row, so they
    /// cannot catch either drifting — they guard the row glyphs on the same lane.
    func testPullRequestPaneTrailingColumn() async throws {
        let fixture = await PullRequestPaneSnapshots.makeLoadedFixture()

        await assertMacModelSnapshot(
            modelContainer: try PullRequestPaneSnapshots.makeModelContainer(),
            size: CGSize(width: 460, height: 400),
            named: "pull_request_pane_trailing_column"
        ) {
            fixture.pane
        }
    }

    /// A failed detail fetch is recoverable in place: the banner carries Retry, and
    /// the summary header stays so the pane still names the pull request. Hosted with
    /// a container because the Overview reaches SwiftData even before its detail lands.
    func testPullRequestPaneOverviewDetailErrorOffersRetry() async throws {
        var session = PullRequestPaneSnapshots.loadedSession
        session.detail = nil
        session.detailError = "gh timed out after 30 seconds"

        await assertMacModelSnapshot(
            modelContainer: try PullRequestPaneSnapshots.makeModelContainer(),
            size: CGSize(width: 460, height: 320),
            named: "pull_request_pane_overview_detail_error"
        ) {
            PullRequestPaneOverview(
                session: session,
                viewModel: PullRequestPaneSnapshots.inertViewModel,
                onOpenFiles: {}
            )
        }
    }

    /// A failed diff is retryable; `.tooLarge` deliberately is not, so the two empty
    /// states differ by exactly that button.
    func testPullRequestPaneFilesDiffFailedOffersRetry() {
        var session = PullRequestPaneSnapshots.loadedSession
        session.diffFiles = nil
        session.diffState = .failed("gh timed out after 60 seconds")

        assertMacSnapshot(
            PullRequestPaneFiles(
                session: session,
                viewModel: PullRequestPaneSnapshots.inertViewModel,
                target: PullRequestPaneSnapshots.target
            ),
            size: CGSize(width: 460, height: 480),
            named: "pull_request_pane_files_diff_failed"
        )
    }

    func testPullRequestPaneFiles() async throws {
        let fixture = await PullRequestPaneSnapshots.makeLoadedFixture()
        let session = try XCTUnwrap(fixture.viewModel.paneSessions[fixture.target])

        assertMacSnapshot(
            PullRequestPaneFiles(session: session, viewModel: fixture.viewModel, target: fixture.target),
            size: CGSize(width: 460, height: 720),
            named: "pull_request_pane_files"
        )
    }

    /// A review proposal's staged comments render on the Changes tab badged "Proposed" — the
    /// orange sibling of "Pending", which marks the viewer's server-side draft. Nothing here
    /// exists on GitHub: the comment lives in Alveary's envelope until the review is submitted.
    ///
    /// Which comments show follows the *pull request*, not the route that opened the pane, so this
    /// host renders the tab directly with no jump involved.
    func testPullRequestPaneFilesProposedComment() throws {
        let viewModel = try PullRequestPaneSnapshots.viewModelWithPendingProposal()
        assertMacSnapshot(
            PullRequestPaneFiles(
                session: PullRequestPaneSnapshots.loadedSession,
                viewModel: viewModel,
                target: PullRequestPaneSnapshots.target
            ),
            size: CGSize(width: 460, height: 520),
            named: "pull_request_pane_files_proposed_comment"
        )
    }

    /// Dark mode is where the card's surface continuity against the code shows, as it is for the
    /// Pending baseline above.
    func testPullRequestPaneFilesProposedCommentDark() throws {
        let viewModel = try PullRequestPaneSnapshots.viewModelWithPendingProposal()
        assertMacSnapshot(
            PullRequestPaneFiles(
                session: PullRequestPaneSnapshots.loadedSession,
                viewModel: viewModel,
                target: PullRequestPaneSnapshots.target
            ),
            size: CGSize(width: 460, height: 520),
            named: "pull_request_pane_files_proposed_comment_dark",
            colorScheme: .dark
        )
    }

    /// The Overview renders staged comments as threads too, so a review reads the same on both
    /// tabs: "Proposed" badge, the location header, and a Remove in the card's own menu — the
    /// only action, since a staged comment is removed rather than edited.
    func testPullRequestPaneOverviewProposedThread() async throws {
        let viewModel = try PullRequestPaneSnapshots.viewModelWithPendingProposal()

        await assertMacModelSnapshot(
            modelContainer: try PullRequestPaneSnapshots.makeModelContainer(),
            size: CGSize(width: 460, height: 1_400),
            named: "pull_request_pane_overview_proposed_thread"
        ) {
            PullRequestPaneOverview(
                session: PullRequestPaneSnapshots.loadedSession,
                viewModel: viewModel,
                onOpenFiles: {}
            )
        }
    }

    /// With a review already written, the footer's default action is finishing it — the stored
    /// "Agentic review" pick is overridden. The note reads "2 comments in this review": the
    /// fixture's own GitHub draft plus the staged comment beside it, because Submit here routes
    /// through the coordinator and publishes both. It deliberately does not say "pending" — that is
    /// GitHub's word for the draft alone, and a staged comment wears the "Proposed" pill.
    func testPullRequestPaneFooterPrefersSubmitWithProposedComments() throws {
        let viewModel = try PullRequestPaneSnapshots.viewModelWithPendingProposal()
        viewModel.selectReviewFooterAction(.agenticReview)

        assertMacSnapshot(
            PullRequestPaneReviewFooter(
                viewModel: viewModel,
                session: PullRequestPaneSnapshots.loadedSession,
                target: PullRequestPaneSnapshots.target
            ),
            size: CGSize(width: 460, height: 140),
            named: "pull_request_pane_footer_proposed_prefers_submit"
        )
    }

    /// A diff past the paging window pins the "Show N more files" bar under the
    /// diff; it wears the same `contextualPaneFooterChrome()` as the review footer
    /// directly beneath it, so the two stacked strips must read as one system.
    func testPullRequestPaneFilesShowMoreFooter() {
        var session = PullRequestPaneSnapshots.loadedSession
        session.diffFiles = DiffParser.parse(makeUnifiedDiffFixture(fileCount: 20, addedLinesPerFile: 1))

        assertMacSnapshot(
            PullRequestPaneFiles(
                session: session,
                viewModel: PullRequestPaneSnapshots.inertViewModel,
                target: PullRequestPaneSnapshots.target
            ),
            size: CGSize(width: 460, height: 320),
            named: "pull_request_pane_files_show_more"
        )
    }

    /// A visited tab stays mounted behind the selected one so its scroll offset
    /// survives, which puts the Changes diff in the hierarchy while the Overview shows.
    /// The hidden tab must contribute nothing, so this baseline is pixel-identical to
    /// `testPullRequestPaneTrailingColumn`, which renders the same pane with only the
    /// Overview mounted. Switching behavior is covered by `KeepAliveTabContainerTests`.
    func testPullRequestPaneKeepsHiddenTabMounted() async throws {
        let fixture = await PullRequestPaneSnapshots.makeLoadedFixture()

        await assertMacModelSnapshot(
            modelContainer: try PullRequestPaneSnapshots.makeModelContainer(),
            size: CGSize(width: 460, height: 400),
            named: "pull_request_pane_hidden_tab_mounted"
        ) {
            fixture.pane(selectedTab: .overview, mountedTabs: [.overview, .files])
        }
    }

    func testPullRequestPaneLoading() async throws {
        let fixture = PullRequestPaneSnapshots.makeLoadingFixture()

        await assertMacModelSnapshot(
            modelContainer: try PullRequestPaneSnapshots.makeModelContainer(),
            size: CGSize(width: 460, height: 500),
            named: "pull_request_pane_loading"
        ) {
            fixture.pane
        }
    }
}
