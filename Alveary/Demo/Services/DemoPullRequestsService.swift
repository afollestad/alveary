#if DEBUG
import Foundation

/// Serves `DemoPullRequestFixtures` so the Pull Requests screen and pane populate without a
/// network round trip. Every mutation throws: demo mode must never reach GitHub.
///
/// The protocol has no extension defaults, so all twenty-six requirements are written out.
struct DemoPullRequestsService: PullRequestsService {
    private static let unavailable = PullRequestsServiceError.transport("Not available in demo mode")

    /// Narrows the fixtures the same way the real search does, so demo mode cannot show a bucket
    /// or a status the app would not return.
    func listInvolvedPullRequests(
        buckets: Set<PullRequestInvolvementBucket>,
        status: PullRequestStatus?
    ) async throws -> PullRequestListResult {
        let summariesByBucket = Dictionary(
            uniqueKeysWithValues: buckets.map { bucket in
                (bucket, DemoPullRequestFixtures.summaries.filter {
                    $0.belongs(to: bucket) && (status == nil || $0.status == status)
                })
            }
        )
        return PullRequestListResult(summariesByBucket: summariesByBucket, warnings: [])
    }

    func fetchDetail(_ id: PullRequestIdentifier) async throws -> PullRequestDetail {
        guard let detail = DemoPullRequestFixtures.detail(for: id) else {
            throw Self.unavailable
        }
        return detail
    }

    func fetchDiff(_ id: PullRequestIdentifier) async throws -> String {
        guard let diff = DemoPullRequestFixtures.diff(for: id) else {
            throw Self.unavailable
        }
        return diff
    }

    // MARK: Mutations

    func submitReview(_ id: PullRequestIdentifier, event: PullRequestReviewEvent, body: String) async throws {
        throw Self.unavailable
    }

    func createPendingReview(pullRequestNodeID: String) async throws -> String {
        throw Self.unavailable
    }

    func addPendingReviewComment(
        reviewNodeID: String,
        path: String,
        line: Int,
        side: PullRequestDiffSide,
        body: String
    ) async throws -> PullRequestReviewThread {
        throw Self.unavailable
    }

    func updatePendingReviewComment(commentNodeID: String, body: String) async throws {
        throw Self.unavailable
    }

    func deletePendingReviewComment(commentNodeID: String) async throws {
        throw Self.unavailable
    }

    func deletePendingReview(reviewNodeID: String) async throws {
        throw Self.unavailable
    }

    func submitPendingReview(
        reviewNodeID: String,
        event: PullRequestReviewEvent,
        body: String
    ) async throws {
        throw Self.unavailable
    }

    func updateReviewComment(_ id: PullRequestIdentifier, commentID: Int, body: String) async throws {
        throw Self.unavailable
    }

    func updateReview(_ id: PullRequestIdentifier, reviewID: Int, body: String) async throws {
        throw Self.unavailable
    }

    func updatePullRequestBody(_ id: PullRequestIdentifier, body: String) async throws {
        throw Self.unavailable
    }

    func setPullRequestClosed(_ id: PullRequestIdentifier, closed: Bool) async throws {
        throw Self.unavailable
    }

    func markPullRequestReadyForReview(nodeID: String) async throws {
        throw Self.unavailable
    }

    func convertPullRequestToDraft(nodeID: String) async throws {
        throw Self.unavailable
    }

    func deleteReviewComment(_ id: PullRequestIdentifier, commentID: Int) async throws {
        throw Self.unavailable
    }

    func addIssueComment(_ id: PullRequestIdentifier, body: String) async throws {
        throw Self.unavailable
    }

    func updateIssueComment(_ id: PullRequestIdentifier, commentID: Int, body: String) async throws {
        throw Self.unavailable
    }

    func deleteIssueComment(_ id: PullRequestIdentifier, commentID: Int) async throws {
        throw Self.unavailable
    }

    func addReaction(subjectID: String, content: PullRequestReactionContent) async throws {
        throw Self.unavailable
    }

    func removeReaction(subjectID: String, content: PullRequestReactionContent) async throws {
        throw Self.unavailable
    }

    func replyToReviewComment(_ id: PullRequestIdentifier, commentID: Int, body: String) async throws {
        throw Self.unavailable
    }

    func setReviewThreadResolved(threadID: String, resolved: Bool) async throws {
        throw Self.unavailable
    }

    func requestReview(_ id: PullRequestIdentifier, reviewerLogin: String) async throws {
        throw Self.unavailable
    }

    func createPullRequest(
        inDirectory directory: String,
        baseBranch: String,
        headBranch: String,
        title: String,
        body: String
    ) async throws -> PullRequestIdentifier {
        throw Self.unavailable
    }
}
#endif
