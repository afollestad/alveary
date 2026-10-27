import Foundation

/// The comments a confirmed review proposal published, as its transcript card last knew them.
///
/// Display-only: GitHub stays authoritative, so every edit or delete re-reads it first, and nothing
/// here feeds a submission or a count. It rides the proposal's outcome marker, which is why the
/// card can still draw the hunks after the proposal's own preview cache is pruned. A review that
/// published no comments records none, so its card keeps the collapsed look that opens the pull request.
struct PullRequestPublishedReview: Codable, Equatable, Sendable {
    struct Comment: Codable, Equatable, Sendable {
        let nodeID: String
        let path: String
        let line: Int
        /// The wire value (`RIGHT`/`LEFT`), like the proposal envelope's.
        let side: String
        var bodyMarkdown: String
        let evidence: PullRequestReviewProposalRecord.CommentEvidence?
        var viewerCanUpdate: Bool
        var viewerCanDelete: Bool
        var isDeleted = false

        var anchor: DiffCommentAnchor {
            DiffCommentAnchor(path: path, side: DiffCommentAnchor.Side(rawValue: side) ?? .right, line: line)
        }
    }

    let identifier: PullRequestIdentifier
    let sourceConversationID: String
    let files: [DiffFile]
    let viewerLogin: String?
    let viewerAvatarURL: URL?
    let reviewers: [PullRequestReviewProposalRecord.Reviewer]
    var comments: [Comment]

    var liveComments: [Comment] {
        comments.filter { !$0.isDeleted }
    }

    /// Nil when this snapshot does not hold the comment or already reflects the change, so callers
    /// can skip a save or a re-render.
    func applying(_ change: PullRequestReviewCommentChange) -> PullRequestPublishedReview? {
        guard let index = comments.firstIndex(where: { $0.nodeID == change.commentNodeID }) else {
            return nil
        }
        var updated = self
        switch change.kind {
        case .edited(let body):
            updated.comments[index].bodyMarkdown = body
        case .deleted:
            updated.comments[index].isDeleted = true
        case .permissionsChanged(let canUpdate, let canDelete):
            updated.comments[index].viewerCanUpdate = canUpdate
            updated.comments[index].viewerCanDelete = canDelete
        }
        return updated == self ? nil : updated
    }
}

extension PullRequestPublishedReview.Comment {
    /// The viewer's published comments in one thread GitHub returned; a comment without a node id
    /// cannot be addressed again, so it is left out rather than shown with dead controls.
    static func comments(
        in thread: PullRequestReviewThread,
        where include: (PullRequestComment) -> Bool = { _ in true },
        evidence: (PullRequestComment) -> PullRequestReviewProposalRecord.CommentEvidence? = { _ in nil }
    ) -> [Self] {
        guard let line = thread.line else { return [] }
        return thread.comments.filter(include).compactMap { comment in
            comment.nodeID.map { nodeID in
                Self(
                    nodeID: nodeID, path: thread.path, line: line, side: thread.side.rawValue,
                    bodyMarkdown: comment.bodyMarkdown, evidence: evidence(comment),
                    viewerCanUpdate: comment.viewerCanUpdate, viewerCanDelete: comment.viewerCanDelete
                )
            }
        }
    }
}
