import Foundation

/// Submitted cards' snapshots and their comment actions; every transition lives in this file.
struct PullRequestPublishedReviewState {
    /// Keyed by proposal id, seeded by confirm and by each card's first render. Authoritative while the
    /// window lives, because the transcript grouper does not re-read a rewritten marker until it rebuilds.
    var reviews: [String: PullRequestPublishedReview] = [:]
    var busyCommentIDs: Set<String> = []
    var errorMessages: [String: String] = [:]
    /// Every change this window heard, replayed onto a snapshot registered later from a grouper entry built
    /// before the change landed.
    var changes: [PullRequestReviewCommentChange] = []
}

/// A submitted card's comments are real GitHub comments: each action re-reads GitHub, then writes through
/// the same REST paths the pane uses, unretried.
extension PullRequestReviewProposalCoordinator {
    /// This window's snapshot for the card, or else the one its marker carried, registered so later
    /// changes reach it. Nil for a card that kept no comments.
    func publishedReview(
        forProposalID proposalID: String,
        registering snapshot: PullRequestPublishedReview? = nil
    ) -> PullRequestPublishedReview? {
        if let review = publishedState.reviews[proposalID] { return review }
        guard var review = snapshot else { return nil }
        for change in publishedState.changes {
            review = review.applying(change) ?? review
        }
        publishedState.reviews[proposalID] = review
        return review
    }

    var busyPublishedCommentIDs: Set<String> {
        publishedState.busyCommentIDs
    }

    func publishedErrorMessage(forProposalID proposalID: String) -> String? {
        publishedState.errorMessages[proposalID]
    }

    @discardableResult
    func editPublishedComment(proposalID: String, nodeID: String, body: String) async -> Bool {
        await performPublishedCommentAction(
            proposalID: proposalID, nodeID: nodeID, origin: "published-comment-edit", change: .edited(body)
        ) { identifier, commentID in
            try await self.service.updateReviewComment(identifier, commentID: commentID, body: body)
        }
    }

    @discardableResult
    func deletePublishedComment(proposalID: String, nodeID: String) async -> Bool {
        await performPublishedCommentAction(
            proposalID: proposalID, nodeID: nodeID, origin: "published-comment-delete", change: .deleted
        ) { identifier, commentID in
            try await self.service.deleteReviewComment(identifier, commentID: commentID)
        }
    }

    /// The one entry point for an Alveary edit or delete of a published review comment, the pane's
    /// included: it updates this window's cards, rewrites every marker holding the comment, and tells the
    /// other windows' coordinators.
    func recordPublishedCommentChange(_ change: PullRequestReviewCommentChange) {
        applyToPublishedReviews(change)
        PullRequestReviewProposalOutcomeRecorder.apply(change, in: modelContext)
        notificationCenter.post(
            name: .pullRequestReviewCommentChanged, object: self,
            userInfo: [PullRequestChangeNotificationKey.commentChange: change]
        )
    }

    func makePublishedChangeObservationTask() -> Task<Void, Never> {
        let notifications = notificationCenter.notifications(named: .pullRequestReviewCommentChanged)
        return Task { @MainActor [weak self] in
            for await notification in notifications {
                guard !Task.isCancelled else { return }
                // The poster already applied it, and the store is written once.
                guard let self, (notification.object as AnyObject?) !== self,
                      let change = notification.userInfo?[PullRequestChangeNotificationKey.commentChange]
                        as? PullRequestReviewCommentChange else { continue }
                applyToPublishedReviews(change)
            }
        }
    }

    /// What confirming just published. An adopted draft publishes with the review, so its comments join
    /// the ones written for the staged comments; evidence follows a staged comment onto the draft
    /// comment that absorbed it. The hunks are the ones submission fetched, which cover the draft's files
    /// where a cached paint does not, else the ones the card drew.
    func publishedReview(
        for presentation: PullRequestReviewProposalPresentation,
        detail: PullRequestDetail,
        written: [PullRequestPublishedReview.Comment],
        fetchedFiles: [DiffFile]?
    ) -> PullRequestPublishedReview {
        let drafted = detail.pendingReviewNodeID == nil ? [] : detail.reviewThreads.flatMap { thread in
            PullRequestPublishedReview.Comment.comments(in: thread, where: \.isPending) { comment in
                let body = comment.bodyMarkdown.trimmingCharacters(in: .whitespacesAndNewlines)
                return presentation.comments.first {
                    $0.path == thread.path && $0.side == thread.side.rawValue
                        && $0.body.trimmingCharacters(in: .whitespacesAndNewlines) == body
                }?.evidence
            }
        }
        let comments = drafted + written
        var files: [DiffFile] = []
        if let fetchedFiles {
            files = Array(ReviewProposalDiffNarrowing.narrowed(
                files: fetchedFiles,
                linesByPath: comments.reduce(into: [:]) { $0[$1.path, default: []].insert($1.line) }
            ).prefix(ReviewProposalDiffNarrowing.maximumFiles))
        } else if case .loaded(let preview)? = previews[presentation.id] {
            files = preview.files
        }
        return PullRequestPublishedReview(
            identifier: presentation.identifier, sourceConversationID: presentation.sourceConversationID,
            files: files, viewerLogin: detail.viewerLogin,
            viewerAvatarURL: detail.viewerAvatarURL, reviewers: presentation.reviewers, comments: comments
        )
    }

    static func message(for error: Error) -> String {
        guard let serviceError = error as? PullRequestsServiceError else {
            return error.localizedDescription
        }
        return serviceError.errorDescription ?? serviceError.localizedDescription
    }
}

private extension PullRequestReviewProposalCoordinator {
    enum PublishedCommentLookup {
        case found(PullRequestComment)
        case deleted
        /// GitHub's page may stop short of it, so its absence proves nothing.
        case unknown
    }

    func applyToPublishedReviews(_ change: PullRequestReviewCommentChange) {
        publishedState.changes.append(change)
        var didChange = false
        for (proposalID, review) in publishedState.reviews {
            guard let updated = review.applying(change) else { continue }
            publishedState.reviews[proposalID] = updated
            didChange = true
        }
        if didChange { notifyChanged() }
    }

    /// Failure leaves the snapshot as it was, except for what the fresh read proved: a comment gone from
    /// GitHub, a withdrawn permission, or text someone else changed, which an edit must not overwrite.
    func performPublishedCommentAction(
        proposalID: String,
        nodeID: String,
        origin: String,
        change: PullRequestReviewCommentChange.Kind,
        write: @escaping (PullRequestIdentifier, Int) async throws -> Void
    ) async -> Bool {
        guard let review = publishedState.reviews[proposalID],
              let snapshot = review.liveComments.first(where: { $0.nodeID == nodeID }),
              !publishedState.busyCommentIDs.contains(nodeID) else { return false }
        publishedState.busyCommentIDs.insert(nodeID)
        publishedState.errorMessages[proposalID] = nil
        notifyChanged()
        defer {
            publishedState.busyCommentIDs.remove(nodeID)
            notifyChanged()
        }
        do {
            let detail = try await GitHubRequestOrigin.$current.withValue(origin) {
                try await service.fetchDetail(review.identifier)
            }
            let lookup = Self.lookup(snapshot, in: detail)
            guard let commentID = verify(lookup, snapshot: snapshot, change: change, proposalID: proposalID) else {
                if case .deleted = lookup { return change == .deleted }
                return false
            }
            try await GitHubRequestOrigin.$current.withValue(origin) { try await write(review.identifier, commentID) }
        } catch {
            publishedState.errorMessages[proposalID] = Self.message(for: error)
            return false
        }
        recordPublishedCommentChange(PullRequestReviewCommentChange(commentNodeID: nodeID, kind: change))
        // An open pane refetches; a comment moves nothing in the list.
        notificationCenter.post(
            name: .pullRequestChangedOnGitHub, object: self,
            userInfo: [
                PullRequestChangeNotificationKey.announcement: PullRequestChangeAnnouncement(
                    identifier: review.identifier, affectsListRow: false
                )
            ]
        )
        return true
    }

    /// The fresh REST id to write through, or nil having recorded what the read proved and reported why.
    /// A delete of a comment already gone reports nothing: what the user asked for is already true.
    func verify(
        _ lookup: PublishedCommentLookup,
        snapshot: PullRequestPublishedReview.Comment,
        change: PullRequestReviewCommentChange.Kind,
        proposalID: String
    ) -> Int? {
        let nodeID = snapshot.nodeID
        switch lookup {
        case .unknown:
            publishedState.errorMessages[proposalID] = "Alveary could not find this comment on GitHub. Open the pull request to change it."
        case .deleted:
            recordPublishedCommentChange(PullRequestReviewCommentChange(commentNodeID: nodeID, kind: .deleted))
            if change != .deleted { publishedState.errorMessages[proposalID] = "This comment was already deleted on GitHub." }
        case .found(let comment):
            let isPermitted = change == .deleted ? comment.viewerCanDelete : comment.viewerCanUpdate
            guard isPermitted else {
                recordPublishedCommentChange(PullRequestReviewCommentChange(
                    commentNodeID: nodeID,
                    kind: .permissionsChanged(canUpdate: comment.viewerCanUpdate, canDelete: comment.viewerCanDelete)
                ))
                publishedState.errorMessages[proposalID] = change == .deleted
                    ? "GitHub no longer lets you delete this comment."
                    : "GitHub no longer lets you edit this comment."
                return nil
            }
            if change != .deleted, Self.normalized(comment.bodyMarkdown) != Self.normalized(snapshot.bodyMarkdown) {
                recordPublishedCommentChange(PullRequestReviewCommentChange(commentNodeID: nodeID, kind: .edited(comment.bodyMarkdown)))
                publishedState.errorMessages[proposalID] = "This comment changed on GitHub. Check the latest text, then save again."
                return nil
            }
            guard let commentID = comment.databaseId else {
                publishedState.errorMessages[proposalID] = "Alveary could not read this comment's GitHub ID. Try again."
                return nil
            }
            return commentID
        }
        return nil
    }

    static func lookup(_ snapshot: PullRequestPublishedReview.Comment, in detail: PullRequestDetail) -> PublishedCommentLookup {
        if let comment = detail.reviewThreads.lazy.flatMap(\.comments).first(where: { $0.nodeID == snapshot.nodeID }) {
            return .found(comment)
        }
        // Any partial thread, not just one at the snapshot's line: a push since may have moved the comment's.
        let isTruncated = detail.reviewThreads.count >= PullRequestDetail.reviewThreadPageSize
            || detail.reviewThreads.contains(where: \.hasUnfetchedComments)
        return isTruncated ? .unknown : .deleted
    }

    static func normalized(_ body: String) -> String {
        body.replacingOccurrences(of: "\r\n", with: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
