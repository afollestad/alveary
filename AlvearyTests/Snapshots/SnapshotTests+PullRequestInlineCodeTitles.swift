import SwiftUI
import XCTest

@testable import Alveary

/// Pull request titles are author-written and routinely carry backticked identifiers, so every
/// surface that shows one renders it as inline markdown. The treatment splits by whether the
/// surface wraps: single-line rows get the rounded chip, the wrapping pane title gets a flat
/// attributed run (a chip cannot break, so a wide code span would truncate).
///
/// These live in their own companion so the coverage cannot churn the unrelated pull-request
/// baselines, whose fixtures deliberately stay plain prose.
extension SnapshotTests {
    /// Unselected and selected rows sit together because `AppMarkdownInlineLabel` always draws
    /// the `.standard` palette — the chip must keep its gray fill over the selected row's
    /// `AppAccentFill.primary` card.
    func testPullRequestRowsRenderInlineCodeTitles() {
        assertMacSnapshot(
            PullRequestInlineCodeTitleSnapshots.sectionedList,
            size: CGSize(width: 1_120, height: 200),
            named: "pull_requests_inline_code_titles"
        )
    }

    func testPullRequestRowsRenderInlineCodeTitlesDark() {
        assertMacSnapshot(
            PullRequestInlineCodeTitleSnapshots.sectionedList,
            size: CGSize(width: 1_120, height: 200),
            named: "pull_requests_inline_code_titles_dark",
            colorScheme: .dark
        )
    }

    /// The pane title wraps, so its inline code renders flat. The status octicon and the diff
    /// stats are framed to the title's *first line* height, so this baseline is also what catches
    /// a code run inflating that line and breaking their alignment.
    func testPullRequestPaneOverviewInlineCodeTitle() async throws {
        await assertMacModelSnapshot(
            modelContainer: try PullRequestPaneSnapshots.makeModelContainer(),
            size: CGSize(width: 460, height: 220),
            named: "pull_request_pane_inline_code_title"
        ) {
            PullRequestInlineCodeTitleSnapshots.paneOverview
        }
    }

    func testPullRequestPaneOverviewInlineCodeTitleDark() async throws {
        await assertMacModelSnapshot(
            modelContainer: try PullRequestPaneSnapshots.makeModelContainer(),
            size: CGSize(width: 460, height: 220),
            named: "pull_request_pane_inline_code_title_dark",
            colorScheme: .dark
        ) {
            PullRequestInlineCodeTitleSnapshots.paneOverview
        }
    }
}

@MainActor
private enum PullRequestInlineCodeTitleSnapshots {
    static let referenceDate = Date(timeIntervalSince1970: 1_800_000_000)

    /// `@octocat` and `/api/orders` are here on purpose: the composer's mention pattern and the
    /// transcript formatter's slash-command pattern would both chip them, and titles opt out.
    static let summaries: [PullRequestSummary] = [
        makePullRequestSummary(
            number: 212,
            repo: "AAkira/Kotlin-Multiplatform-Libraries",
            title: "Add `arkivanov/parcelize-darwin` to Serializer section",
            author: "afollestad",
            branch: "patch-1",
            updatedAt: referenceDate.addingTimeInterval(-25 * 60),
            isAuthored: true
        ),
        makePullRequestSummary(
            number: 77,
            repo: "octo/alveary",
            title: "Thanks @octocat — harden `/api/orders` retries",
            author: "kanna",
            branch: "retry-hardening",
            updatedAt: referenceDate.addingTimeInterval(-6 * 60 * 60),
            isReviewRequested: true
        )
    ]

    static var sectionedList: some View {
        PullRequestsSectionedList(
            sections: [PullRequestListSection(id: "inline-code", title: nil, rows: summaries)],
            showsRepository: true,
            referenceDate: referenceDate,
            avatarLoader: GitHubAvatarLoader(),
            isSelected: { $0.number == 212 },
            onSelect: { _ in }
        )
        .padding(20)
    }

    /// Header-only: no detail and nothing loading, so the Overview renders `headerSection` and
    /// stops. A long title is what makes it wrap at the pane's width.
    static var paneOverview: some View {
        var session = PullRequestPaneSession(
            generation: UUID(),
            summary: makePullRequestSummary(
                number: 212,
                repo: "AAkira/Kotlin-Multiplatform-Libraries",
                title: "Add `arkivanov/parcelize-darwin` to Serializer section, "
                    + "thanks @octocat, and retry `/api/orders`",
                author: "afollestad",
                branch: "patch-1",
                updatedAt: referenceDate.addingTimeInterval(-25 * 60),
                isAuthored: true
            )
        )
        session.isLoadingDetail = false
        return PullRequestPaneOverview(
            session: session,
            viewModel: PullRequestPaneSnapshots.inertViewModel,
            onOpenFiles: {}
        )
    }
}
