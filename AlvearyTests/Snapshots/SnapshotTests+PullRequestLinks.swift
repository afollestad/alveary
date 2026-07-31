import SwiftData
import SwiftUI
import XCTest

@testable import Alveary

/// The toolbar's pull-request button and its links popover. Popover *content*
/// is snapshotted directly — a live `NSPopover` host crashes on macOS 26, see
/// `AlvearyTests/AGENTS.md`.
extension SnapshotTests {
    func testPrimaryToolbarButtonGroupWithoutLinkedPullRequests() {
        assertMacSnapshot(
            primaryToolbarButtonGroup(
                pullRequestState: PullRequestLinksToolbarState(linkCount: 0, status: nil),
                diffDisplayState: .idle(.empty)
            )
            .padding(8),
            size: CGSize(width: 214, height: 64),
            named: "primary_toolbar_button_group_pull_requests_none"
        )
    }

    /// One link tints the glyph with that pull request's status; these four are
    /// the whole vocabulary the button can render.
    func testPrimaryToolbarButtonGroupSingleLinkedPullRequestStatuses() {
        for status in [PullRequestStatus.open, .draft, .merged, .closed] {
            assertMacSnapshot(
                primaryToolbarButtonGroup(
                    pullRequestState: PullRequestLinksToolbarState(linkCount: 1, status: status),
                    diffDisplayState: .idle(.empty)
                )
                .padding(8),
                size: CGSize(width: 214, height: 64),
                named: "primary_toolbar_button_group_pull_request_\(status.rawValue)"
            )
        }
    }

    func testPrimaryToolbarButtonGroupMultipleLinkedPullRequests() {
        assertMacSnapshot(
            primaryToolbarButtonGroup(
                pullRequestState: PullRequestLinksToolbarState(linkCount: 3, status: nil),
                diffDisplayState: .idle(.empty)
            )
            .padding(8),
            size: CGSize(width: 214, height: 64),
            named: "primary_toolbar_button_group_pull_requests_multiple"
        )
    }

    func testPullRequestLinksPopoverEmpty() throws {
        let popover = try pullRequestLinksPopover(links: { _ in [] })
        assertMacSnapshot(
            popover,
            size: CGSize(width: 340, height: 78),
            named: "pull_request_links_popover_empty"
        )
    }

    /// The third row carries a child-thread source label — the shape a project
    /// selection renders when it aggregates a thread's link.
    func testPullRequestLinksPopoverWithLinks() throws {
        let popover = try pullRequestLinksPopover(links: { owner in
            [
                makeOwnedPullRequestLink(number: 412, title: "Add response caching", status: .open, owner: owner),
                makeOwnedPullRequestLink(number: 418, title: "Fix scheduler races", status: .draft, owner: owner),
                makeOwnedPullRequestLink(
                    number: 402,
                    title: "Retire the legacy exporter",
                    status: .merged,
                    owner: owner,
                    sourceLabel: "Exporter cleanup"
                )
            ]
        })
        assertMacSnapshot(
            popover,
            size: CGSize(width: 340, height: 244),
            named: "pull_request_links_popover_links"
        )
    }

    func testPullRequestLinksPopoverUnavailableGitHubCLI() throws {
        let popover = try pullRequestLinksPopover(
            links: { _ in [] },
            errorMessage: "GitHub CLI (gh) is not installed",
            showsGitSettingsAction: true
        )
        assertMacSnapshot(
            popover,
            size: CGSize(width: 340, height: 172),
            named: "pull_request_links_popover_unavailable"
        )
    }

    /// The rows need a real `PullRequestLinkOwner`, so a throwaway in-memory
    /// container mints one; the popover itself never observes SwiftData, the
    /// identifier is inert row data.
    private func pullRequestLinksPopover(
        links: (PullRequestLinkOwner) throws -> [OwnedPullRequestLink],
        errorMessage: String? = nil,
        showsGitSettingsAction: Bool = false
    ) throws -> some View {
        PullRequestLinksPopover(
            links: try links(try makePlaceholderLinkOwner()),
            isLinking: false,
            errorMessage: errorMessage,
            showsGitSettingsAction: showsGitSettingsAction,
            onOpen: { _ in },
            onRemove: { _ in },
            onLink: { _ in },
            onOpenGitSettings: {},
            onEditURL: {}
        )
    }

    private func makePlaceholderLinkOwner() throws -> PullRequestLinkOwner {
        let container = try ModelContainer(
            for: Project.self,
            AgentThread.self,
            Conversation.self,
            ConversationEventRecord.self,
            ScheduledTask.self,
            ScheduledTaskRun.self,
            ScheduledTaskProposal.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let project = Project(path: "/tmp/alpha", name: "Alpha")
        context.insert(project)
        try context.save()
        return .project(project.persistentModelID)
    }

    private func makeOwnedPullRequestLink(
        number: Int,
        title: String,
        status: PullRequestStatus,
        owner: PullRequestLinkOwner,
        sourceLabel: String? = nil
    ) -> OwnedPullRequestLink {
        OwnedPullRequestLink(
            link: LinkedPullRequest(
                summary: makePullRequestSummary(number: number, title: title, status: status),
                linkedAt: Date(timeIntervalSince1970: 1_700_000_000)
            ),
            owner: owner,
            sourceLabel: sourceLabel
        )
    }
}
