import Foundation
import XCTest

@testable import Alveary

// The `PullRequestsService` stub the view-model suites drive: per-method
// `Result` knobs, recorded calls for assertions, and gates for holding a call
// in flight. Fixtures and wait helpers live in the `+Support` companion.
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
    var updateIssueCommentResult: Result<Void, PullRequestsServiceError> = .failure(.transport("unused"))
    var deleteIssueCommentResult: Result<Void, PullRequestsServiceError> = .failure(.transport("unused"))
    var updateReviewResult: Result<Void, PullRequestsServiceError> = .failure(.transport("unused"))
    var updatePullRequestBodyResult: Result<Void, PullRequestsServiceError> = .success(())
    var setClosedResult: Result<Void, PullRequestsServiceError> = .success(())
    var readyForReviewResult: Result<Void, PullRequestsServiceError> = .success(())
    var convertToDraftResult: Result<Void, PullRequestsServiceError> = .success(())
    var reactionResult: Result<Void, PullRequestsServiceError> = .success(())
    var replyResult: Result<Void, PullRequestsServiceError> = .success(())
    var resolveResult: Result<Void, PullRequestsServiceError> = .success(())
    var requestReviewResult: Result<Void, PullRequestsServiceError> = .success(())
    var createPullRequestResult: Result<PullRequestIdentifier, PullRequestsServiceError> = .failure(.transport("unused"))
    var createPendingReviewResult: Result<String, PullRequestsServiceError> = .success("PENDING_REVIEW")
    var addPendingCommentResult: Result<PullRequestReviewThread, PullRequestsServiceError>?
    var updatePendingCommentResult: Result<Void, PullRequestsServiceError> = .success(())
    var deletePendingCommentResult: Result<Void, PullRequestsServiceError> = .success(())
    var deletePendingReviewResult: Result<Void, PullRequestsServiceError> = .success(())
    var submitPendingReviewResult: Result<Void, PullRequestsServiceError> = .success(())
    var detailGate: PullRequestsServiceGate?
    var diffGate: PullRequestsServiceGate?
    /// Holds `createPendingReview` open so a concurrency test can fire a second
    /// comment while the first one's review is still being opened.
    var createPendingReviewGate: PullRequestsServiceGate?
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

    struct CreatedPullRequest: Equatable {
        let directory: String
        let baseBranch: String
        let headBranch: String
        let title: String
        let body: String
    }

    struct ThreadResolution: Equatable {
        let threadID: String
        let resolved: Bool
    }

    struct AddedPendingComment: Equatable {
        let reviewNodeID: String
        let path: String
        let line: Int
        let side: PullRequestDiffSide
        let body: String
    }

    struct UpdatedPendingComment: Equatable {
        let commentNodeID: String
        let body: String
    }

    struct SubmittedReview: Equatable {
        let id: PullRequestIdentifier
        let event: PullRequestReviewEvent
        let body: String
    }

    struct SubmittedPendingReview: Equatable {
        let reviewNodeID: String
        let event: PullRequestReviewEvent
        let body: String
    }

    private(set) var submittedReviews: [SubmittedReview] = []
    private(set) var updatedComments: [UpdatedReviewComment] = []
    private(set) var deletedCommentIDs: [Int] = []
    private(set) var updatedIssueComments: [UpdatedReviewComment] = []
    private(set) var deletedIssueCommentIDs: [Int] = []
    private(set) var updatedReviews: [UpdatedReviewComment] = []
    private(set) var updatedDescriptions: [String] = []
    private(set) var reactionMutations: [ReactionMutation] = []
    private(set) var threadReplies: [ThreadReply] = []
    private(set) var threadResolutions: [ThreadResolution] = []
    private(set) var reviewRequests: [String] = []
    private(set) var createdPullRequests: [CreatedPullRequest] = []
    private(set) var stateChanges: [Bool] = []
    private(set) var readyForReviewNodeIDs: [String] = []
    private(set) var convertToDraftNodeIDs: [String] = []
    private(set) var createdPendingReviewNodeIDs: [String] = []
    private(set) var addedPendingComments: [AddedPendingComment] = []
    private(set) var updatedPendingComments: [UpdatedPendingComment] = []
    private(set) var deletedPendingCommentNodeIDs: [String] = []
    private(set) var deletedPendingReviewNodeIDs: [String] = []
    private(set) var submittedPendingReviews: [SubmittedPendingReview] = []

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

    func submitReview(_ id: PullRequestIdentifier, event: PullRequestReviewEvent, body: String) async throws {
        submittedReviews.append(SubmittedReview(id: id, event: event, body: body))
        return try submitResult.get()
    }

    func createPendingReview(pullRequestNodeID: String) async throws -> String {
        createdPendingReviewNodeIDs.append(pullRequestNodeID)
        await createPendingReviewGate?.wait()
        return try createPendingReviewResult.get()
    }

    func addPendingReviewComment(
        reviewNodeID: String,
        path: String,
        line: Int,
        side: PullRequestDiffSide,
        body: String
    ) async throws -> PullRequestReviewThread {
        addedPendingComments.append(
            AddedPendingComment(reviewNodeID: reviewNodeID, path: path, line: line, side: side, body: body)
        )
        // Default: echo back a thread shaped like GitHub's, with ids derived from
        // the body so a test can assert which comment it is.
        guard let addPendingCommentResult else {
            return Self.makePendingThread(path: path, line: line, side: side, body: body)
        }
        return try addPendingCommentResult.get()
    }

    func updatePendingReviewComment(commentNodeID: String, body: String) async throws {
        updatedPendingComments.append(UpdatedPendingComment(commentNodeID: commentNodeID, body: body))
        return try updatePendingCommentResult.get()
    }

    func deletePendingReviewComment(commentNodeID: String) async throws {
        deletedPendingCommentNodeIDs.append(commentNodeID)
        return try deletePendingCommentResult.get()
    }

    func deletePendingReview(reviewNodeID: String) async throws {
        deletedPendingReviewNodeIDs.append(reviewNodeID)
        return try deletePendingReviewResult.get()
    }

    func submitPendingReview(
        reviewNodeID: String,
        event: PullRequestReviewEvent,
        body: String
    ) async throws {
        submittedPendingReviews.append(
            SubmittedPendingReview(reviewNodeID: reviewNodeID, event: event, body: body)
        )
        return try submitPendingReviewResult.get()
    }

    /// The server's copy of a freshly added pending comment: real ids, so the UI
    /// unlocks its edit and delete actions once the swap lands.
    static func makePendingThread(
        path: String,
        line: Int,
        side: PullRequestDiffSide,
        body: String
    ) -> PullRequestReviewThread {
        PullRequestReviewThread(
            path: path,
            line: line,
            side: side,
            isResolved: false,
            isOutdated: false,
            comments: [
                PullRequestComment(
                    authorLogin: "viewer",
                    authorAvatarURL: nil,
                    bodyMarkdown: body,
                    createdAt: Date(timeIntervalSince1970: 1_700_000_000),
                    databaseId: 9001,
                    nodeID: "PENDING_COMMENT_\(body)",
                    viewerCanUpdate: true,
                    viewerCanDelete: true,
                    isPending: true
                )
            ],
            nodeID: "PENDING_THREAD_\(body)",
            reviewNodeID: "PENDING_REVIEW"
        )
    }

    func updateReviewComment(_ id: PullRequestIdentifier, commentID: Int, body: String) async throws {
        updatedComments.append(UpdatedReviewComment(id: id, commentID: commentID, body: body))
        return try updateCommentResult.get()
    }

    func deleteReviewComment(_ id: PullRequestIdentifier, commentID: Int) async throws {
        deletedCommentIDs.append(commentID)
        return try deleteCommentResult.get()
    }

    func updateIssueComment(_ id: PullRequestIdentifier, commentID: Int, body: String) async throws {
        updatedIssueComments.append(UpdatedReviewComment(id: id, commentID: commentID, body: body))
        return try updateIssueCommentResult.get()
    }

    func deleteIssueComment(_ id: PullRequestIdentifier, commentID: Int) async throws {
        deletedIssueCommentIDs.append(commentID)
        return try deleteIssueCommentResult.get()
    }

    func updatePullRequestBody(_ id: PullRequestIdentifier, body: String) async throws {
        updatedDescriptions.append(body)
        return try updatePullRequestBodyResult.get()
    }

    func setPullRequestClosed(_ id: PullRequestIdentifier, closed: Bool) async throws {
        stateChanges.append(closed)
        return try setClosedResult.get()
    }

    func markPullRequestReadyForReview(nodeID: String) async throws {
        readyForReviewNodeIDs.append(nodeID)
        return try readyForReviewResult.get()
    }

    func convertPullRequestToDraft(nodeID: String) async throws {
        convertToDraftNodeIDs.append(nodeID)
        return try convertToDraftResult.get()
    }

    func updateReview(_ id: PullRequestIdentifier, reviewID: Int, body: String) async throws {
        updatedReviews.append(UpdatedReviewComment(id: id, commentID: reviewID, body: body))
        return try updateReviewResult.get()
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

    func createPullRequest(
        inDirectory directory: String,
        baseBranch: String,
        headBranch: String,
        title: String,
        body: String
    ) async throws -> PullRequestIdentifier {
        createdPullRequests.append(
            CreatedPullRequest(
                directory: directory,
                baseBranch: baseBranch,
                headBranch: headBranch,
                title: title,
                body: body
            )
        )
        return try createPullRequestResult.get()
    }
}
