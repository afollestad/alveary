import Foundation

// Local, optimistic mutations of fetched pull-request models: the view model
// applies these immediately and reverts them when the network mutation fails.

extension [PullRequestCommentReaction] {
    /// The viewer's add/remove applied locally, for optimistic UI: counts adjust,
    /// empty groups drop, and new groups insert in GitHub's palette order.
    /// Idempotent — applying an add the viewer already has (or a remove they do
    /// not) returns the array unchanged.
    func togglingViewerReaction(_ content: PullRequestReactionContent, add: Bool) -> [PullRequestCommentReaction] {
        var groups = self
        if let index = groups.firstIndex(where: { $0.content == content }) {
            let group = groups[index]
            guard group.viewerHasReacted != add else {
                return groups
            }
            let count = group.count + (add ? 1 : -1)
            if count <= 0 {
                groups.remove(at: index)
            } else {
                groups[index] = PullRequestCommentReaction(content: content, count: count, viewerHasReacted: add)
            }
            return groups
        }
        guard add else {
            return groups
        }
        let paletteIndex = PullRequestReactionContent.allCases.firstIndex(of: content) ?? 0
        let insertion = groups.firstIndex { group in
            (PullRequestReactionContent.allCases.firstIndex(of: group.content) ?? 0) > paletteIndex
        } ?? groups.endIndex
        groups.insert(
            PullRequestCommentReaction(content: content, count: 1, viewerHasReacted: true),
            at: insertion
        )
        return groups
    }
}

extension PullRequestDetail {
    /// Applies the viewer's reaction toggle to whichever subject carries
    /// `subjectID` — the pull request body, an issue comment, a review, or a
    /// review-thread comment.
    mutating func applyViewerReaction(subjectID: String, content: PullRequestReactionContent, add: Bool) {
        if nodeID == subjectID {
            reactions = reactions.togglingViewerReaction(content, add: add)
        }
        for index in comments.indices where comments[index].nodeID == subjectID {
            comments[index].reactions = comments[index].reactions.togglingViewerReaction(content, add: add)
        }
        for index in reviews.indices where reviews[index].nodeID == subjectID {
            reviews[index].reactions = reviews[index].reactions.togglingViewerReaction(content, add: add)
        }
        for threadIndex in reviewThreads.indices {
            for index in reviewThreads[threadIndex].comments.indices
            where reviewThreads[threadIndex].comments[index].nodeID == subjectID {
                reviewThreads[threadIndex].comments[index].reactions = reviewThreads[threadIndex]
                    .comments[index].reactions.togglingViewerReaction(content, add: add)
            }
        }
    }
}

extension PullRequestDetail {
    /// Optimistic thread resolution: flips the flag locally; the caller reverts by
    /// flipping back if the mutation fails.
    mutating func setThreadResolved(threadID: String, resolved: Bool) {
        for index in reviewThreads.indices where reviewThreads[index].nodeID == threadID {
            reviewThreads[index].isResolved = resolved
        }
    }

    /// Optimistic reply: appends to the thread whose root comment carries
    /// `rootCommentID`. The placeholder has no node/REST id until a refetch
    /// replaces it with the server copy.
    mutating func appendThreadReply(rootCommentID: Int, comment: PullRequestComment) {
        for index in reviewThreads.indices
        where reviewThreads[index].comments.contains(where: { $0.databaseId == rootCommentID }) {
            reviewThreads[index].comments.append(comment)
            return
        }
    }

    /// Reverts `appendThreadReply` after a failed post: removes the last id-less
    /// comment with the given body from the matching thread.
    mutating func removeOptimisticReply(rootCommentID: Int, body: String) {
        for index in reviewThreads.indices
        where reviewThreads[index].comments.contains(where: { $0.databaseId == rootCommentID }) {
            if let last = reviewThreads[index].comments.lastIndex(where: {
                $0.nodeID == nil && $0.databaseId == nil && $0.bodyMarkdown == body
            }) {
                reviewThreads[index].comments.remove(at: last)
            }
            return
        }
    }

    /// Optimistic remote edit: rewrites the thread comment's body locally and
    /// returns the previous body so a failed PATCH can restore it.
    @discardableResult
    mutating func updateThreadCommentBody(commentID: Int, body: String) -> String? {
        for threadIndex in reviewThreads.indices {
            guard let index = reviewThreads[threadIndex].comments
                .firstIndex(where: { $0.databaseId == commentID }) else {
                continue
            }
            let previous = reviewThreads[threadIndex].comments[index].bodyMarkdown
            reviewThreads[threadIndex].comments[index].bodyMarkdown = body
            return previous
        }
        return nil
    }

    /// What a failed optimistic deletion needs to reinsert the comment — including
    /// the whole thread when removing its last comment removed the thread too.
    struct RemovedThreadComment: Equatable, Sendable {
        let threadIndex: Int
        let threadNodeID: String?
        let commentIndex: Int
        let comment: PullRequestComment
        /// The pre-removal thread, set only when the removal emptied it.
        let thread: PullRequestReviewThread?
    }

    /// Optimistic remote delete: removes the comment locally; a thread emptied by
    /// the removal disappears with it, matching GitHub.
    mutating func removeThreadComment(commentID: Int) -> RemovedThreadComment? {
        for threadIndex in reviewThreads.indices {
            guard let index = reviewThreads[threadIndex].comments
                .firstIndex(where: { $0.databaseId == commentID }) else {
                continue
            }
            let comment = reviewThreads[threadIndex].comments[index]
            let nodeID = reviewThreads[threadIndex].nodeID
            if reviewThreads[threadIndex].comments.count == 1 {
                let thread = reviewThreads.remove(at: threadIndex)
                return RemovedThreadComment(
                    threadIndex: threadIndex,
                    threadNodeID: nodeID,
                    commentIndex: index,
                    comment: comment,
                    thread: thread
                )
            }
            reviewThreads[threadIndex].comments.remove(at: index)
            return RemovedThreadComment(
                threadIndex: threadIndex,
                threadNodeID: nodeID,
                commentIndex: index,
                comment: comment,
                thread: nil
            )
        }
        return nil
    }

    /// Reverts `removeThreadComment` after a failed DELETE. Matches the thread by
    /// node id first so an interleaved refetch cannot misplace the reinsertion.
    mutating func restoreThreadComment(_ removed: RemovedThreadComment) {
        if let thread = removed.thread {
            let index = Swift.min(removed.threadIndex, reviewThreads.endIndex)
            reviewThreads.insert(thread, at: index)
            return
        }
        let threadIndex = reviewThreads.firstIndex { $0.nodeID != nil && $0.nodeID == removed.threadNodeID }
            ?? (reviewThreads.indices.contains(removed.threadIndex) ? removed.threadIndex : nil)
        guard let threadIndex else {
            return
        }
        let index = Swift.min(removed.commentIndex, reviewThreads[threadIndex].comments.endIndex)
        reviewThreads[threadIndex].comments.insert(removed.comment, at: index)
    }
}
