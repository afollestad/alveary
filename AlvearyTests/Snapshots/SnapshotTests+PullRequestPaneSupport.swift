import SwiftData
import SwiftUI

@testable import Alveary

@MainActor
enum PullRequestPaneSnapshots {
    static let identifier = PullRequestIdentifier(owner: "octo", repo: "alveary", number: 41)
    /// The pane target every fixture renders, so a host that builds a tab directly still names the
    /// pull request the session describes.
    static let target = PullRequestPaneTarget.details(identifier)

    /// An empty store for the Overview's linked-owners queries: the section
    /// renders nothing, which is what every baseline except the linked-owners
    /// one expects.
    static func makeModelContainer() throws -> ModelContainer {
        try ModelContainer(
            for: Project.self,
            AgentThread.self,
            Conversation.self,
            ConversationEventRecord.self,
            ScheduledTask.self,
            ScheduledTaskRun.self,
            ScheduledTaskProposal.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }

    /// A project and one of its threads linking the fixture pull request, plus a
    /// thread that links nothing.
    static func makeLinkedOwnersContainer() throws -> ModelContainer {
        let container = try makeModelContainer()
        let context = ModelContext(container)
        let project = Project(path: "/tmp/alveary", name: "alveary")
        context.insert(project)
        let linkedThread = AgentThread(name: "Pull request pane polish", project: project)
        let unlinkedThread = AgentThread(name: "Unrelated work", project: project)
        context.insert(linkedThread)
        context.insert(unlinkedThread)
        let link = LinkedPullRequest(
            summary: summary,
            linkedAt: Date(timeIntervalSince1970: 1_799_930_000)
        )
        project.linkedPullRequests = [link]
        linkedThread.linkedPullRequests = [link]
        try context.save()
        return container
    }

    /// A view model that never loads; standalone tab snapshots only need the
    /// avatar loader (letter placeholders for nil URLs) and toggle callbacks.
    /// The fixed clock sits just after the fixture dates so relative ages stay
    /// stable.
    static var inertViewModel: PullRequestsViewModel {
        makePullRequestsViewModel(
            service: StubPullRequestsService(),
            now: { Date(timeIntervalSince1970: 1_800_000_000) }
        )
    }

    /// An inert view model whose coordinator holds one pending review proposal for this fixture's
    /// pull request, so the Changes tab renders its staged comment badged "Proposed". Built over
    /// an in-memory store because the coordinator reads the envelope off a `Conversation`.
    static func viewModelWithPendingProposal() throws -> PullRequestsViewModel {
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
        let thread = AgentThread(name: "Review thread")
        let conversation = Conversation(id: "review-conversation", provider: "codex", thread: thread)
        thread.conversations = [conversation]
        context.insert(thread)
        try conversation.storePullRequestReviewProposal(
            PullRequestReviewProposalRecord(
                payloadVersion: PullRequestReviewProposalRecord.currentPayloadVersion,
                id: "proposal-snapshot",
                deduplicationKey: "dedup-snapshot",
                repositoryNameWithOwner: identifier.nameWithOwner,
                number: identifier.number,
                event: "comment",
                body: "A couple of notes.",
                comments: [
                    PullRequestReviewProposalRecord.Comment(
                        // The generated diff's own second added line, so the card sits mid-hunk
                        // with code above and below it.
                        path: "File0.swift",
                        line: 2,
                        side: "RIGHT",
                        body: "Prefer `guard let` over the force unwrap here."
                    )
                ],
                titleSnapshot: "Add pull request browsing to the sidebar",
                pendingCommentCountSnapshot: 0,
                sourceProviderID: "codex",
                sourceProcessToken: "token",
                sourceRequestID: "request-1",
                createdAt: Date(timeIntervalSince1970: 1_799_960_000)
            )
        )
        try context.save()

        return makePullRequestsViewModel(
            service: StubPullRequestsService(),
            reviewProposalCoordinator: PullRequestReviewProposalCoordinator(
                modelContext: context,
                pullRequestsService: StubPullRequestsService(),
                notificationCenter: NotificationCenter()
            ),
            now: { Date(timeIntervalSince1970: 1_800_000_000) }
        )
    }

    static var loadedSession: PullRequestPaneSession {
        var session = PullRequestPaneSession(generation: UUID(), summary: summary)
        session.detail = detail
        session.isLoadingDetail = false
        session.diffFiles = DiffParser.parse(makeUnifiedDiffFixture(fileCount: 2, addedLinesPerFile: 3))
        session.diffState = .loaded
        return session
    }

    /// Anchored to the generated diff's own first added line (`File0.swift`, new
    /// line 1) and not outdated, so `commentAnnotations` actually inserts a
    /// thread row into the Changes tab.
    static let diffAnchoredThread = PullRequestReviewThread(
        path: "File0.swift",
        line: 1,
        side: .right,
        isResolved: false,
        isOutdated: false,
        comments: [
            PullRequestComment(
                authorLogin: "priya",
                authorAvatarURL: nil,
                bodyMarkdown: "Clamp this before the fetch.",
                createdAt: Date(timeIntervalSince1970: 1_799_965_000),
                databaseId: 987,
                nodeID: "PRRC_diff",
                viewerCanUpdate: true,
                viewerCanDelete: true
            )
        ],
        nodeID: "PRT_diff"
    )

    static let summary = makePullRequestSummary(
        number: 41,
        repo: "octo/alveary",
        title: "Add pull request browsing to the sidebar",
        author: "afollestad",
        branch: "af/pull-requests",
        updatedAt: Date(timeIntervalSince1970: 1_799_990_000)
    )

    static let detail = PullRequestDetail(
        id: identifier,
        title: "Add pull request browsing to the sidebar",
        url: nil,
        status: .open,
        authorLogin: "afollestad",
        authorAvatarURL: nil,
        headRefName: "af/pull-requests",
        baseRefName: "main",
        createdAt: Date(timeIntervalSince1970: 1_799_900_000),
        updatedAt: Date(timeIntervalSince1970: 1_799_990_000),
        additions: 482,
        deletions: 37,
        changedFiles: 12,
        bodyMarkdown: "## Summary\nAdds a **Pull requests** sidebar item with filter tabs and a detail pane.\n\n"
            + "- Batched GraphQL listing\n- Review submission",
        reviewDecision: "REVIEW_REQUIRED",
        checks: [
            PullRequestCheck(name: "build", state: .passing, detailsURL: URL(string: "https://ci.example.com/build")),
            PullRequestCheck(name: "test", state: .pending, detailsURL: nil),
            PullRequestCheck(name: "ci/lint", state: .failing, detailsURL: URL(string: "https://ci.example.com/lint"))
        ],
        comments: [
            PullRequestComment(
                authorLogin: "codex-connector",
                authorAvatarURL: nil,
                bodyMarkdown: "Looks promising — one question about the throttle.",
                createdAt: Date(timeIntervalSince1970: 1_799_950_000),
                databaseId: 501,
                nodeID: "IC_1",
                // Delete-only permissions: the card's menu renders with just Delete,
                // like a collaborator viewing a bot's comment on GitHub.
                viewerCanDelete: true,
                reactions: [
                    PullRequestCommentReaction(content: .thumbsUp, count: 2, viewerHasReacted: false)
                ],
                isBot: true
            )
        ],
        reviews: [
            PullRequestReview(
                authorLogin: "miguel",
                authorAvatarURL: nil,
                state: .approved,
                bodyMarkdown: "Ship it.",
                submittedAt: Date(timeIntervalSince1970: 1_799_960_000),
                databaseId: 555,
                nodeID: "PRR_1",
                // Updatable: the review card's menu offers Edit (never Delete).
                viewerCanUpdate: true,
                reactions: [
                    PullRequestCommentReaction(content: .hooray, count: 1, viewerHasReacted: true)
                ]
            ),
            PullRequestReview(
                authorLogin: "priya",
                authorAvatarURL: nil,
                state: .changesRequested,
                bodyMarkdown: "",
                submittedAt: Date(timeIntervalSince1970: 1_799_970_000),
                nodeID: "PRR_2"
            )
        ],
        reviewThreads: [
            PullRequestReviewThread(
                path: "Alveary/Services/Git/PullRequestsService.swift",
                line: 42,
                side: .right,
                isResolved: false,
                isOutdated: true,
                comments: [
                    PullRequestComment(
                        authorLogin: "priya",
                        authorAvatarURL: nil,
                        bodyMarkdown: "Consider clamping this before the fetch.",
                        createdAt: Date(timeIntervalSince1970: 1_799_965_000),
                        databaseId: 987,
                        nodeID: "PRRC_1",
                        // Full permissions: the thread comment's menu offers both actions.
                        viewerCanUpdate: true,
                        viewerCanDelete: true
                    )
                ],
                nodeID: "PRT_1",
                // Submitted with priya's review: nests under her verdict card.
                reviewNodeID: "PRR_2"
            ),
            // The viewer's own unsubmitted comment. Its carrier review is dropped
            // from `reviews`, so it renders as a standalone timeline card wearing
            // the orange Pending pill, with no Reply/Resolve footer.
            PullRequestReviewThread(
                path: "Alveary/Views/PullRequests/PullRequestPane.swift",
                line: 18,
                side: .right,
                isResolved: false,
                isOutdated: false,
                comments: [
                    PullRequestComment(
                        authorLogin: "afollestad",
                        authorAvatarURL: nil,
                        bodyMarkdown: "Queue this rename for the same review.",
                        createdAt: Date(timeIntervalSince1970: 1_799_975_000),
                        databaseId: 988,
                        nodeID: "PRRC_pending",
                        viewerCanUpdate: true,
                        viewerCanDelete: true,
                        isPending: true
                    )
                ],
                nodeID: "PRT_pending",
                reviewNodeID: "PRR_pending"
            )
        ],
        timelineEvents: [
            PullRequestTimelineEvent(
                kind: .convertToDraft,
                actorLogin: "afollestad",
                actorAvatarURL: nil,
                createdAt: Date(timeIntervalSince1970: 1_799_940_000)
            ),
            PullRequestTimelineEvent(
                kind: .commit,
                actorLogin: "afollestad",
                actorAvatarURL: nil,
                createdAt: Date(timeIntervalSince1970: 1_799_945_000),
                detail: "abc1234 Wire up the sidebar row"
            ),
            PullRequestTimelineEvent(
                kind: .reviewRequested,
                actorLogin: "afollestad",
                actorAvatarURL: nil,
                createdAt: Date(timeIntervalSince1970: 1_799_952_000),
                detail: "priya"
            ),
            PullRequestTimelineEvent(
                kind: .readyForReview,
                actorLogin: "afollestad",
                actorAvatarURL: nil,
                createdAt: Date(timeIntervalSince1970: 1_799_955_000)
            )
        ],
        reviewers: [
            PullRequestReviewer(login: "copilot", avatarURL: nil, isBot: true, state: .requested, canReRequest: false),
            PullRequestReviewer(login: "miguel", avatarURL: nil, isBot: false, state: .approved, canReRequest: true),
            PullRequestReviewer(login: "priya", avatarURL: nil, isBot: false, state: .changesRequested, canReRequest: true)
        ],
        nodeID: "PR_41",
        reactions: [
            PullRequestCommentReaction(content: .rocket, count: 3, viewerHasReacted: true)
        ]
    )

    @MainActor
    struct Fixture {
        let viewModel: PullRequestsViewModel
        let target: PullRequestPaneTarget

        var pane: PullRequestPane {
            PullRequestPane(viewModel: viewModel, target: target, onDismiss: {})
        }

        /// Seeds the pane's tab state so a baseline can render one tab with the other
        /// already mounted behind it — the arrangement a tab switch leaves in place.
        func pane(
            selectedTab: PullRequestPaneTab,
            mountedTabs: Set<PullRequestPaneTab>
        ) -> PullRequestPane {
            PullRequestPane(
                viewModel: viewModel,
                target: target,
                onDismiss: {},
                initialSelectedTab: selectedTab,
                initiallyMountedTabs: mountedTabs
            )
        }
    }

    static func makeLoadedFixture() async -> Fixture {
        let service = StubPullRequestsService()
        service.detailResult = .success(detail)
        service.diffResult = .success(makeUnifiedDiffFixture(fileCount: 2, addedLinesPerFile: 3))
        // Fixed clock just after the fixture dates so relative ages stay stable.
        let viewModel = makePullRequestsViewModel(
            service: service,
            now: { Date(timeIntervalSince1970: 1_800_000_000) }
        )
        viewModel.requestDetails(summary)
        let target = PullRequestPaneTarget.details(identifier)
        for _ in 0..<2_000 {
            if let session = viewModel.paneSessions[target],
               !session.isLoadingDetail,
               session.diffState != .loading {
                break
            }
            await Task.yield()
        }
        return Fixture(viewModel: viewModel, target: target)
    }

    static func makeLoadingFixture() -> Fixture {
        let service = StubPullRequestsService()
        // Never-opened gates keep both loads in flight so the pane renders loading states.
        service.detailGate = PullRequestsServiceGate()
        service.diffGate = PullRequestsServiceGate()
        let viewModel = makePullRequestsViewModel(service: service)
        viewModel.requestDetails(summary)
        return Fixture(viewModel: viewModel, target: .details(identifier))
    }
}
