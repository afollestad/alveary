import Foundation
import XCTest

@testable import Alveary

@MainActor
func makePullRequestsViewModel(
    service: StubPullRequestsService,
    listCache: PullRequestsListCache? = nil,
    settingsService: (any SettingsService)? = nil,
    attachmentUploadService: (any GitHubAttachmentUploadService)? = nil,
    attachmentImageSeeder: (@MainActor (GitHubAttachmentUpload) async -> Void)? = nil,
    attachmentImageRepositoryRegistrar: (@MainActor (String) -> Void)? = nil,
    presentToast: @escaping @MainActor @Sendable (String) -> Void = { _ in },
    agenticThreadStarter: (
        @MainActor (PullRequestAgenticThreadRequest) async throws -> PullRequestAgenticThreadStart
    )? = nil,
    reviewProposalCoordinator: PullRequestReviewProposalCoordinator? = nil,
    // A private bus by default, so a suite cannot be disturbed by anything posting on `.default`;
    // pass a shared one to wire a coordinator or host-tool service to this view model. The delay
    // goes to zero so the debounce still coalesces without a test having to sleep through it.
    notificationCenter: NotificationCenter = NotificationCenter(),
    remoteRefreshDelay: Duration = .zero,
    // Zero commits the search synchronously, so a test can assign `searchQuery` and assert the
    // narrowed rows on the next line; pass a real duration to exercise the debounce itself.
    searchDebounce: Duration = .zero,
    now: @escaping () -> Date = Date.init
) -> PullRequestsViewModel {
    PullRequestsViewModel(
        service: service,
        avatarLoader: GitHubAvatarLoader(),
        listCache: listCache,
        settingsService: settingsService,
        attachmentUploadService: attachmentUploadService,
        attachmentImageSeeder: attachmentImageSeeder,
        attachmentImageRepositoryRegistrar: attachmentImageRepositoryRegistrar,
        presentToast: presentToast,
        agenticThreadStarter: agenticThreadStarter,
        reviewProposalCoordinator: reviewProposalCoordinator,
        notificationCenter: notificationCenter,
        remoteRefreshDelay: remoteRefreshDelay,
        searchDebounce: searchDebounce,
        now: now
    )
}

/// Builds the value a real starter answers with. `dispatch` defaults to already-succeeded work,
/// so a test that only cares about the navigation half writes nothing extra.
@MainActor
func makeAgenticThreadStart(
    conversationID: String,
    dispatch: @escaping @Sendable () async throws -> Void = {}
) -> PullRequestAgenticThreadStart {
    PullRequestAgenticThreadStart(
        conversationID: conversationID,
        dispatch: Task { try await dispatch() }
    )
}

/// Records upload calls and returns caller-supplied results so attach tests can
/// drive success and failure deterministically.
@MainActor
final class StubGitHubAttachmentUploadService: GitHubAttachmentUploadService {
    var available = true
    var result: Result<[GitHubAttachmentUpload], GitHubAttachmentUploadError> = .success([])
    private(set) var uploadCalls: [(files: [URL], repository: String)] = []
    /// Held closed until `openGate()` so a test can observe the in-flight state.
    var gate: PullRequestsServiceGate?

    func isAvailable() async -> Bool {
        available
    }

    func upload(files: [URL], repository: String) async throws -> [GitHubAttachmentUpload] {
        uploadCalls.append((files: files, repository: repository))
        await gate?.wait()
        return try result.get()
    }
}

func makePullRequestSummary(
    number: Int,
    repo: String = "octo/alpha",
    title: String = "Change something",
    author: String = "alice",
    branch: String = "feat/change",
    status: PullRequestStatus = .open,
    updatedAt: Date = Date(timeIntervalSince1970: 1_000),
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
        authorAvatarURL: nil,
        headRefName: branch,
        baseRefName: "main",
        updatedAt: updatedAt,
        additions: 10,
        deletions: 3,
        reviewDecision: nil,
        isAuthored: isAuthored,
        isReviewRequested: isReviewRequested,
        hasReviewed: hasReviewed
    )
}

func makePullRequestDetail(
    id: PullRequestIdentifier,
    title: String = "Detail title",
    status: PullRequestStatus = .open,
    headRefName: String = "feat/change",
    comments: [PullRequestComment] = [],
    reviews: [PullRequestReview] = [],
    reviewThreads: [PullRequestReviewThread] = [],
    viewerCanUpdate: Bool = false,
    headRefExists: Bool = true,
    // Non-nil by default: production always fetches it, and both draft
    // directions are gated on it.
    nodeID: String? = "PR_7",
    pendingReviewNodeID: String? = nil
) -> PullRequestDetail {
    var detail = PullRequestDetail(
        id: id,
        title: title,
        url: nil,
        status: status,
        authorLogin: "alice",
        authorAvatarURL: nil,
        headRefName: headRefName,
        baseRefName: "main",
        createdAt: Date(timeIntervalSince1970: 500),
        updatedAt: Date(timeIntervalSince1970: 1_000),
        additions: 10,
        deletions: 3,
        changedFiles: 1,
        bodyMarkdown: "Body",
        reviewDecision: nil,
        checks: [],
        comments: comments,
        reviews: reviews,
        reviewThreads: reviewThreads,
        viewerCanUpdate: viewerCanUpdate,
        headRefExists: headRefExists
    )
    detail.nodeID = nodeID
    detail.pendingReviewNodeID = pendingReviewNodeID
    return detail
}

/// Builds a syntactically valid unified diff with `fileCount` files, each containing
/// `addedLinesPerFile` added lines, for exercising file paging and auto-collapse.
func makeUnifiedDiffFixture(fileCount: Int, addedLinesPerFile: Int = 1) -> String {
    (0..<fileCount).map { index in
        let added = (0..<addedLinesPerFile).map { "+line \($0)" }.joined(separator: "\n")
        return """
        diff --git a/File\(index).swift b/File\(index).swift
        --- a/File\(index).swift
        +++ b/File\(index).swift
        @@ -1,0 +1,\(addedLinesPerFile) @@
        \(added)
        """
    }.joined(separator: "\n") + "\n"
}

/// Polls until `condition` holds, for the loads the view model spawns in a detached `Task` —
/// selecting a tab or a status filter, which have no handle to await.
@MainActor
func waitFor(
    _ condition: () -> Bool,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    for _ in 0..<2_000 {
        if condition() {
            return
        }
        await Task.yield()
    }
    XCTFail("Condition never became true", file: file, line: line)
}

/// Polls until the pane session's detail and diff loads both settle.
@MainActor
func waitForPaneContent(
    _ viewModel: PullRequestsViewModel,
    target: PullRequestPaneTarget,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    for _ in 0..<2_000 {
        if let session = viewModel.paneSessions[target],
           !session.isLoadingDetail,
           session.diffState != .loading {
            return
        }
        await Task.yield()
    }
    XCTFail("Pane content did not finish loading", file: file, line: line)
}

/// Reusable open/wait gate so tests can hold a stubbed service call in flight.
final class PullRequestsServiceGate: @unchecked Sendable {
    private let lock = NSLock()
    private var isOpen = false
    private var continuations: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        let shouldReturn: Bool = withLock { isOpen }
        if shouldReturn {
            return
        }
        await withCheckedContinuation { continuation in
            let resumeNow: Bool = withLock {
                if isOpen {
                    return true
                }
                continuations.append(continuation)
                return false
            }
            if resumeNow {
                continuation.resume()
            }
        }
    }

    func open() {
        let waiting: [CheckedContinuation<Void, Never>] = withLock {
            isOpen = true
            let pending = continuations
            continuations = []
            return pending
        }
        for continuation in waiting {
            continuation.resume()
        }
    }

    private func withLock<T>(_ body: () -> T) -> T {
        lock.lock()
        defer {
            lock.unlock()
        }
        return body()
    }
}

/// The anchor the review and pending-comment suites compose against.
let pullRequestReviewAnchor = DiffCommentAnchor(path: "Sources/Parser.swift", side: .right, line: 12)

/// A pane whose detail and diff have landed, ready for composing.
@MainActor
func makeLoadedPullRequestPane(
    service: StubPullRequestsService,
    pendingReviewNodeID: String? = nil,
    reviewThreads: [PullRequestReviewThread] = []
) async -> (viewModel: PullRequestsViewModel, summary: PullRequestSummary) {
    let summary = makePullRequestSummary(number: 7)
    service.detailResult = .success(
        makePullRequestDetail(
            id: summary.id,
            reviewThreads: reviewThreads,
            pendingReviewNodeID: pendingReviewNodeID
        )
    )
    service.diffResult = .success(makeUnifiedDiffFixture(fileCount: 1))
    let viewModel = makePullRequestsViewModel(service: service)
    viewModel.requestDetails(summary)
    await waitForPaneContent(viewModel, target: .details(summary.id))
    return (viewModel, summary)
}

/// Spins the main actor until `condition` holds, for the unstructured `Task`s the
/// optimistic comment paths dispatch.
@MainActor
func waitForPullRequestCondition(
    _ condition: @MainActor () -> Bool,
    iterations: Int = 2_000
) async {
    for _ in 0..<iterations {
        if condition() {
            return
        }
        await Task.yield()
    }
}

@MainActor
func drainMainQueue() async {
    for _ in 0..<200 {
        await Task.yield()
    }
}
