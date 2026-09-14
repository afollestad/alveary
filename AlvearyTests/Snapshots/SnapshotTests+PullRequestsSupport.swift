import SwiftData
import SwiftUI

@testable import Alveary

@MainActor
final class PullRequestsSnapshotFixture {
    static let referenceDate = Date(timeIntervalSince1970: 1_800_000_000)

    let container: ModelContainer
    let viewModel: PullRequestsViewModel
    let service: SnapshotPullRequestsService

    var screen: some View {
        PullRequestsScreen(viewModel: viewModel, onOpenGitSettings: {})
    }

    init(
        summaries: [PullRequestSummary]? = nil,
        warnings: [String] = [],
        failure: PullRequestsServiceError? = nil,
        hasNextPage: Bool = false,
        loadInitially: Bool = true,
        includeLinkedThreads: Bool = false
    ) async throws {
        container = try ModelContainer(
            for: Project.self,
            AgentThread.self,
            Conversation.self,
            ConversationEventRecord.self,
            ScheduledTask.self,
            ScheduledTaskRun.self,
            ScheduledTaskProposal.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        if includeLinkedThreads { try Self.seedLinkedThreads(in: container.mainContext) }
        let service = SnapshotPullRequestsService()
        self.service = service
        if let failure {
            service.listResult = .failure(failure)
        } else {
            service.listResult = .success(PullRequestListResult(
                summaries: summaries ?? Self.defaultSummaries,
                warnings: warnings,
                // Nothing more to page by default, so every existing baseline renders without the
                // "Load more" footer exactly as it did before pagination.
                pageInfoByBucket: hasNextPage
                    ? Dictionary(uniqueKeysWithValues: PullRequestInvolvementBucket.allCases.map {
                        ($0, PullRequestListPageInfo(endCursor: "page-1", hasNextPage: true, rowCursors: []))
                    })
                    : [:]
            ))
        }
        // Seed the broad status filter without selectStatusFilter spawning an unowned load.
        var settings = AppSettings()
        settings.pullRequestsStatusFilter = .all
        viewModel = PullRequestsViewModel(
            service: service,
            avatarLoader: GitHubAvatarLoader(),
            settingsService: InMemorySettingsService(current: settings),
            // Zero so a baseline that sets `searchQuery` renders the narrowed list in the same
            // turn, with no debounce to wait out before the snapshot is taken.
            searchDebounce: .zero,
            now: { Self.referenceDate }
        )
        if loadInitially { await viewModel.refresh() }
    }

    /// Default fixtures leave the store empty. This variant mixes active links with excluded
    /// owners, including an active thread linked to a draft PR: only the thread's draft state matters.
    private static func seedLinkedThreads(in context: ModelContext) throws {
        let links = defaultSummaries.map { LinkedPullRequest(summary: $0, linkedAt: referenceDate) }
        let activeThread = AgentThread(name: "Active linked work")
        activeThread.linkedPullRequests = Array(links.prefix(2))
        context.insert(activeThread)
        let duplicateThread = AgentThread(name: "More work on the same pull request")
        duplicateThread.linkedPullRequests = [links[0]]
        context.insert(duplicateThread)
        let archivedThread = AgentThread(name: "Archived work", archivedAt: referenceDate)
        archivedThread.linkedPullRequests = [links[2]]
        context.insert(archivedThread)
        let draftThread = AgentThread(name: "Unsent work", isDraft: true)
        draftThread.linkedPullRequests = [links[3]]
        context.insert(draftThread)
        let project = Project(path: "/tmp/pr-list-fixture", name: "Project-only link")
        project.linkedPullRequests = [links[4]]
        context.insert(project)
        try context.save()
    }

    static let defaultSummaries: [PullRequestSummary] = [
        makeSummary(
            number: 41,
            repo: "octo/alveary",
            title: "Add pull request browsing to the sidebar",
            author: "afollestad",
            branch: "af/pull-requests",
            status: .open,
            ageMinutes: 25,
            additions: 482,
            deletions: 37,
            isAuthored: true
        ),
        makeSummary(
            number: 128,
            repo: "octo/knit",
            title: "Use swiftlang SwiftSyntax repository",
            author: "kanna",
            branch: "swift-syntax-migration",
            status: .draft,
            ageMinutes: 60 * 5,
            additions: 3,
            deletions: 3,
            isReviewRequested: true
        ),
        makeSummary(
            number: 566,
            repo: "octo/paraphrase",
            title: "Localize plural rules for release notes",
            author: "miguel",
            branch: "plural-rules",
            status: .open,
            ageMinutes: 60 * 24 * 2,
            additions: 120,
            deletions: 44,
            isReviewRequested: true
        ),
        makeSummary(
            number: 9,
            repo: "octo/alveary",
            title: "Drop macOS floor to 15",
            author: "afollestad",
            branch: "af/macos-15",
            status: .merged,
            ageMinutes: 60 * 24 * 33,
            additions: 2,
            deletions: 2,
            isAuthored: true,
            hasReviewed: false
        ),
        makeSummary(
            number: 87,
            repo: "octo/knit",
            title: "Reject cyclic assembly graphs with a diagnostic",
            author: "priya",
            branch: "cycle-diagnostics",
            status: .closed,
            ageMinutes: 60 * 24 * 400,
            additions: 58,
            deletions: 12,
            hasReviewed: true
        )
    ]

    private static func makeSummary(
        number: Int,
        repo: String,
        title: String,
        author: String = "alice",
        branch: String,
        status: PullRequestStatus = .open,
        ageMinutes: Double,
        additions: Int = 10,
        deletions: Int = 3,
        isAuthored: Bool = false,
        isReviewRequested: Bool = false,
        hasReviewed: Bool = false
    ) -> PullRequestSummary {
        let parts = repo.split(separator: "/")
        return PullRequestSummary(
            id: PullRequestIdentifier(owner: String(parts[0]), repo: String(parts[1]), number: number),
            title: title,
            url: nil,
            status: status,
            authorLogin: author,
            // Avatar URLs stay nil so snapshots render the deterministic letter placeholder.
            authorAvatarURL: nil,
            headRefName: branch,
            baseRefName: "main",
            updatedAt: referenceDate.addingTimeInterval(-ageMinutes * 60),
            additions: additions,
            deletions: deletions,
            isAuthored: isAuthored,
            isReviewRequested: isReviewRequested,
            hasReviewed: hasReviewed
        )
    }
}

@MainActor
final class SnapshotPullRequestsService: PullRequestsService, @unchecked Sendable {
    private(set) var completedBuckets: Set<PullRequestInvolvementBucket> = []
    var listResult: Result<PullRequestListResult, PullRequestsServiceError> = .success(
        PullRequestListResult(summaries: [], warnings: [])
    )

    func listInvolvedPullRequests(
        buckets: Set<PullRequestInvolvementBucket>,
        status: PullRequestStatus?,
        options: PullRequestListOptions
    ) async throws -> PullRequestListResult {
        defer { completedBuckets.formUnion(buckets) }
        let result = try listResult.get()
        // Answer only what was asked for, like the real service and `StubPullRequestsService`.
        // The view model fetches one bucket per request and indexes the reply by bucket, so
        // returning the whole fixture happens to work — but a fake that ignores its arguments
        // stops the next change from being caught here.
        return PullRequestListResult(
            summariesByBucket: result.summariesByBucket.filter { buckets.contains($0.key) },
            warnings: result.warnings,
            pageInfoByBucket: result.pageInfoByBucket.filter { buckets.contains($0.key) }
        )
    }

    func fetchDetail(_ id: PullRequestIdentifier) async throws -> PullRequestDetail {
        throw PullRequestsServiceError.transport("unused")
    }

    func fetchDiff(_ id: PullRequestIdentifier) async throws -> String {
        throw PullRequestsServiceError.transport("unused")
    }

    func submitReview(_ id: PullRequestIdentifier, event: PullRequestReviewEvent, body: String) async throws {
        throw PullRequestsServiceError.transport("unused")
    }

    func createPendingReview(pullRequestNodeID: String) async throws -> String {
        throw PullRequestsServiceError.transport("unused")
    }

    func addPendingReviewComment(
        reviewNodeID: String,
        path: String,
        line: Int,
        side: PullRequestDiffSide,
        body: String
    ) async throws -> PullRequestReviewThread {
        throw PullRequestsServiceError.transport("unused")
    }

    func updatePendingReviewComment(commentNodeID: String, body: String) async throws {
        throw PullRequestsServiceError.transport("unused")
    }

    func deletePendingReviewComment(commentNodeID: String) async throws {
        throw PullRequestsServiceError.transport("unused")
    }

    func deletePendingReview(reviewNodeID: String) async throws {
        throw PullRequestsServiceError.transport("unused")
    }

    func submitPendingReview(
        reviewNodeID: String,
        event: PullRequestReviewEvent,
        body: String
    ) async throws {
        throw PullRequestsServiceError.transport("unused")
    }

    func updateReviewComment(_ id: PullRequestIdentifier, commentID: Int, body: String) async throws {
        throw PullRequestsServiceError.transport("unused")
    }

    func deleteReviewComment(_ id: PullRequestIdentifier, commentID: Int) async throws {
        throw PullRequestsServiceError.transport("unused")
    }

    func addIssueComment(_ id: PullRequestIdentifier, body: String) async throws {
        throw PullRequestsServiceError.transport("unused")
    }

    func updateIssueComment(_ id: PullRequestIdentifier, commentID: Int, body: String) async throws {
        throw PullRequestsServiceError.transport("unused")
    }

    func deleteIssueComment(_ id: PullRequestIdentifier, commentID: Int) async throws {
        throw PullRequestsServiceError.transport("unused")
    }

    func updateReview(_ id: PullRequestIdentifier, reviewID: Int, body: String) async throws {
        throw PullRequestsServiceError.transport("unused")
    }

    func updatePullRequestBody(_ id: PullRequestIdentifier, body: String) async throws {
        throw PullRequestsServiceError.transport("unused")
    }

    func setPullRequestClosed(_ id: PullRequestIdentifier, closed: Bool) async throws {
        throw PullRequestsServiceError.transport("unused")
    }

    func markPullRequestReadyForReview(nodeID: String) async throws {
        throw PullRequestsServiceError.transport("unused")
    }

    func convertPullRequestToDraft(nodeID: String) async throws {
        throw PullRequestsServiceError.transport("unused")
    }

    func addReaction(subjectID: String, content: PullRequestReactionContent) async throws {
        throw PullRequestsServiceError.transport("unused")
    }

    func removeReaction(subjectID: String, content: PullRequestReactionContent) async throws {
        throw PullRequestsServiceError.transport("unused")
    }

    func replyToReviewComment(_ id: PullRequestIdentifier, commentID: Int, body: String) async throws {
        throw PullRequestsServiceError.transport("unused")
    }

    func setReviewThreadResolved(threadID: String, resolved: Bool) async throws {
        throw PullRequestsServiceError.transport("unused")
    }

    func requestReview(_ id: PullRequestIdentifier, reviewerLogin: String) async throws {
        throw PullRequestsServiceError.transport("unused")
    }

    func createPullRequest(
        inDirectory directory: String,
        baseBranch: String,
        headBranch: String,
        title: String,
        body: String
    ) async throws -> PullRequestIdentifier {
        throw PullRequestsServiceError.transport("unused")
    }
}
