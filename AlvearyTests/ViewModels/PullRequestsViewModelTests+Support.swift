import Foundation
import XCTest

@testable import Alveary

@MainActor
func makePullRequestsViewModel(
    service: StubPullRequestsService,
    listCache: PullRequestsListCache? = nil,
    settingsService: (any SettingsService)? = nil,
    now: @escaping () -> Date = Date.init
) -> PullRequestsViewModel {
    PullRequestsViewModel(
        service: service,
        avatarLoader: GitHubAvatarLoader(),
        listCache: listCache,
        settingsService: settingsService,
        now: now
    )
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
    comments: [PullRequestComment] = [],
    reviewThreads: [PullRequestReviewThread] = []
) -> PullRequestDetail {
    PullRequestDetail(
        id: id,
        title: title,
        url: nil,
        status: .open,
        authorLogin: "alice",
        authorAvatarURL: nil,
        headRefName: "feat/change",
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
        reviews: [],
        reviewThreads: reviewThreads
    )
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

@MainActor
final class StubPullRequestsService: PullRequestsService, @unchecked Sendable {
    var listResult: Result<PullRequestListResult, PullRequestsServiceError> = .success(
        PullRequestListResult(summaries: [], warnings: [])
    )
    var listGate: PullRequestsServiceGate?
    var detailResult: Result<PullRequestDetail, PullRequestsServiceError> = .failure(.transport("unused"))
    var diffResult: Result<String, PullRequestsServiceError> = .failure(.transport("unused"))
    var submitResult: Result<Void, PullRequestsServiceError> = .failure(.transport("unused"))
    var updateCommentResult: Result<Void, PullRequestsServiceError> = .failure(.transport("unused"))
    var deleteCommentResult: Result<Void, PullRequestsServiceError> = .failure(.transport("unused"))
    var reactionResult: Result<Void, PullRequestsServiceError> = .success(())
    var replyResult: Result<Void, PullRequestsServiceError> = .success(())
    var resolveResult: Result<Void, PullRequestsServiceError> = .success(())
    var requestReviewResult: Result<Void, PullRequestsServiceError> = .success(())
    var detailGate: PullRequestsServiceGate?
    var diffGate: PullRequestsServiceGate?
    private(set) var listCallCount = 0
    private(set) var detailCallCount = 0
    private(set) var diffCallCount = 0
    struct UpdatedReviewComment: Equatable {
        let id: PullRequestIdentifier
        let commentID: Int
        let body: String
    }

    struct ReactionMutation: Equatable {
        let subjectID: String
        let content: PullRequestReactionContent
        let isAdd: Bool
    }

    struct ThreadReply: Equatable {
        let commentID: Int
        let body: String
    }

    struct ThreadResolution: Equatable {
        let threadID: String
        let resolved: Bool
    }

    private(set) var submittedReviews: [(id: PullRequestIdentifier, submission: PendingReviewSubmission)] = []
    private(set) var updatedComments: [UpdatedReviewComment] = []
    private(set) var deletedCommentIDs: [Int] = []
    private(set) var reactionMutations: [ReactionMutation] = []
    private(set) var threadReplies: [ThreadReply] = []
    private(set) var threadResolutions: [ThreadResolution] = []
    private(set) var reviewRequests: [String] = []

    func listInvolvedPullRequests() async throws -> PullRequestListResult {
        listCallCount += 1
        await listGate?.wait()
        return try listResult.get()
    }

    func fetchDetail(_ id: PullRequestIdentifier) async throws -> PullRequestDetail {
        detailCallCount += 1
        await detailGate?.wait()
        return try detailResult.get()
    }

    func fetchDiff(_ id: PullRequestIdentifier) async throws -> String {
        diffCallCount += 1
        await diffGate?.wait()
        return try diffResult.get()
    }

    func submitReview(_ id: PullRequestIdentifier, submission: PendingReviewSubmission) async throws {
        submittedReviews.append((id: id, submission: submission))
        return try submitResult.get()
    }

    func updateReviewComment(_ id: PullRequestIdentifier, commentID: Int, body: String) async throws {
        updatedComments.append(UpdatedReviewComment(id: id, commentID: commentID, body: body))
        return try updateCommentResult.get()
    }

    func deleteReviewComment(_ id: PullRequestIdentifier, commentID: Int) async throws {
        deletedCommentIDs.append(commentID)
        return try deleteCommentResult.get()
    }

    func addReaction(subjectID: String, content: PullRequestReactionContent) async throws {
        reactionMutations.append(ReactionMutation(subjectID: subjectID, content: content, isAdd: true))
        return try reactionResult.get()
    }

    func removeReaction(subjectID: String, content: PullRequestReactionContent) async throws {
        reactionMutations.append(ReactionMutation(subjectID: subjectID, content: content, isAdd: false))
        return try reactionResult.get()
    }

    func replyToReviewComment(_ id: PullRequestIdentifier, commentID: Int, body: String) async throws {
        threadReplies.append(ThreadReply(commentID: commentID, body: body))
        return try replyResult.get()
    }

    func setReviewThreadResolved(threadID: String, resolved: Bool) async throws {
        threadResolutions.append(ThreadResolution(threadID: threadID, resolved: resolved))
        return try resolveResult.get()
    }

    func requestReview(_ id: PullRequestIdentifier, reviewerLogin: String) async throws {
        reviewRequests.append(reviewerLogin)
        return try requestReviewResult.get()
    }
}
