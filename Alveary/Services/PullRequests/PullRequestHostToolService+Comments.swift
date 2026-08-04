import AgentCLIKit
import Foundation

extension PullRequestHostToolService {
    /// Attaches inline comments to the viewer's pending review, opening that draft if GitHub does
    /// not already hold one.
    ///
    /// Immediate, without confirmation, because nothing is published: GitHub shows a pending
    /// comment only to its author, and Alveary's pull request pane can delete it. Submitting the
    /// review is the step that needs the user, and `propose_pr_review` owns it.
    ///
    /// GitHub takes one comment per mutation, so a batch is a serial loop that stops at the first
    /// failure. Whatever it wrote before that stays — the draft is the user's own and deletable —
    /// and the result names each comment's fate so a follow-up call can carry only the rest.
    func addReviewComments(
        context: AgentCLIKit.AgentHostToolCallContext,
        arguments: [String: AgentCLIKit.JSONValue]
    ) async throws -> AgentCLIKit.AgentHostToolResult {
        try flushPendingChanges()
        // Source first: a caller Alveary cannot place gets the source refusal, not an argument
        // critique of a request it was never entitled to make.
        let source = try resolveSource(context: context)
        let request = try parseReviewComments(arguments: arguments)
        let identity = try callIdentity(
            context: context,
            source: source,
            canonicalPayloadHash: request.canonicalPayloadHash
        )
        if let receipt = try replayedReceipt(on: source.conversation, identity: identity) {
            return replayedBatchResult(receipt: receipt, request: request)
        }

        let written = try await writePendingComments(request)
        let status = written.isComplete ? "added" : "partial"
        let message = Self.batchMessage(request: request, written: written)
        // A receipt is kept for a partial batch too: without it, a replay would post the comments
        // that already landed a second time, which is the whole hazard the ledger exists for.
        try persistReceipt(
            makeReceipt(
                identity: identity,
                toolName: PullRequestHostToolCatalog.addReviewCommentsToolName,
                status: status,
                message: message,
                handle: .commentBatch(written.outcomes)
            ),
            on: source.conversation
        )

        let rows = zip(request.comments, written.outcomes).map { comment, outcome in
            Self.commentRow(
                comment: comment,
                status: outcome.status,
                threadNodeID: outcome.threadNodeID,
                message: outcome.message
            )
        }
        return mutationResult(
            status: status,
            message: message,
            fields: [
                "comments": .array(rows),
                "added_count": .number(Double(written.addedCount)),
                "pending_comment_count": .number(Double(written.pendingCommentCount))
            ]
        )
    }

    /// Replies to an existing thread. Published immediately — GitHub has no draft state for a
    /// reply — so the tool description says so and the model is told to ask first.
    func replyToThread(
        context: AgentCLIKit.AgentHostToolCallContext,
        arguments: [String: AgentCLIKit.JSONValue]
    ) async throws -> AgentCLIKit.AgentHostToolResult {
        try flushPendingChanges()
        let source = try resolveSource(context: context)
        let request = try parseThreadReply(arguments: arguments)
        let identity = try callIdentity(
            context: context,
            source: source,
            canonicalPayloadHash: request.canonicalPayloadHash
        )
        if let receipt = try replayedReceipt(on: source.conversation, identity: identity) {
            return replayedResult(receipt: receipt)
        }

        let path = try await postReply(request)
        let message = "Replied to the review thread on \(path) in " +
            "\(request.identifier.displayKey). The reply is published on GitHub."
        try persistReceipt(
            makeReceipt(
                identity: identity,
                toolName: PullRequestHostToolCatalog.replyToThreadToolName,
                status: "replied",
                message: message,
                handle: .thread(request.threadID)
            ),
            on: source.conversation
        )
        return mutationResult(
            status: "replied",
            message: message,
            fields: ["thread_id": .string(request.threadID)]
        )
    }

    /// Posts a top-level conversation comment. Published immediately, like a reply.
    func commentOnPullRequest(
        context: AgentCLIKit.AgentHostToolCallContext,
        arguments: [String: AgentCLIKit.JSONValue]
    ) async throws -> AgentCLIKit.AgentHostToolResult {
        try flushPendingChanges()
        let source = try resolveSource(context: context)
        let request = try parseComment(arguments: arguments)
        let identity = try callIdentity(
            context: context,
            source: source,
            canonicalPayloadHash: request.canonicalPayloadHash
        )
        if let receipt = try replayedReceipt(on: source.conversation, identity: identity) {
            return replayedResult(receipt: receipt)
        }

        do {
            try await pullRequestsService.addIssueComment(request.identifier, body: request.body)
        } catch let error as PullRequestsServiceError {
            throw Self.unavailable(error)
        }

        let message = "Commented on \(request.identifier.displayKey). The comment is published on GitHub."
        try persistReceipt(
            makeReceipt(
                identity: identity,
                toolName: PullRequestHostToolCatalog.commentToolName,
                status: "commented",
                message: message
            ),
            on: source.conversation
        )
        return mutationResult(
            status: "commented",
            message: message,
            fields: [
                "repository": .string(request.identifier.nameWithOwner),
                "number": .number(Double(request.identifier.number))
            ]
        )
    }

    /// Threads are addressed by GraphQL node id, the only handle the read tools hand out. A missing
    /// one means the model invented it or the pull request moved on, and refetching is the fix.
    static func thread(
        withID threadID: String,
        in detail: PullRequestDetail
    ) throws -> PullRequestReviewThread {
        guard let thread = detail.reviewThreads.first(where: { $0.nodeID == threadID }) else {
            throw PullRequestHostToolServiceError.reviewThreadNotFound(threadID: threadID)
        }
        return thread
    }
}

/// One outcome per requested comment, in request order, plus the draft's resulting size.
private struct PullRequestHostToolWrittenComments {
    let outcomes: [PullRequestHostToolReceiptCommentOutcome]
    let pendingCommentCount: Int

    var addedCount: Int {
        outcomes.filter { $0.status == "added" }.count
    }

    var isComplete: Bool {
        addedCount == outcomes.count
    }
}

private extension PullRequestHostToolService {
    /// Writes each comment into one draft, opened or adopted once for the whole batch. A failure
    /// stops the loop rather than retrying or pressing on: the causes are systemic (auth, network,
    /// a stale diff anchor), so the rest would fail the same way one round trip at a time.
    func writePendingComments(
        _ request: PullRequestHostToolReviewCommentsRequest
    ) async throws -> PullRequestHostToolWrittenComments {
        let detail = try await fetchDetail(request.identifier)
        let reviewNodeID = try await pendingReviewNodeID(for: request.identifier, detail: detail)
        var outcomes: [PullRequestHostToolReceiptCommentOutcome] = []
        for comment in request.comments {
            do {
                let thread = try await pullRequestsService.addPendingReviewComment(
                    reviewNodeID: reviewNodeID,
                    path: comment.path,
                    line: comment.line,
                    side: comment.side,
                    body: comment.body
                )
                outcomes.append(.init(status: "added", threadNodeID: thread.nodeID))
            } catch let error as PullRequestsServiceError {
                let failure = Self.unavailable(error)
                // Nothing written yet: an ordinary failure, with no partial state to describe.
                guard !outcomes.isEmpty else {
                    throw failure
                }
                outcomes.append(.init(status: "failed", message: failure.localizedDescription))
                let unattempted = request.comments.count - outcomes.count
                outcomes.append(
                    contentsOf: repeatElement(.init(status: "skipped"), count: unattempted)
                )
                break
            }
        }
        let added = outcomes.filter { $0.status == "added" }.count
        // The count GitHub now holds: the fetched draft plus whatever this call wrote.
        return PullRequestHostToolWrittenComments(
            outcomes: outcomes,
            pendingCommentCount: detail.pendingCommentCount + added
        )
    }

    /// Both channels carry this string, so it has to say the comments are unpublished — a model
    /// that reads them as public will tell the user their review is already visible.
    static func batchMessage(
        request: PullRequestHostToolReviewCommentsRequest,
        written: PullRequestHostToolWrittenComments
    ) -> String {
        let added = written.addedCount
        let draftNote = "The added comment(s) are part of the user's unsubmitted review draft — only they can " +
            "see them, and nothing is published until a review is submitted."
        guard written.isComplete else {
            return "Added \(added) of \(request.comments.count) pending review comments on " +
                "\(request.identifier.displayKey), then stopped. \(failureNote(request: request, written: written)) " +
                "\(draftNote) Call \(PullRequestHostToolCatalog.addReviewCommentsToolName) again with only the " +
                "comments that were not added."
        }
        let noun = added == 1 ? "pending review comment" : "pending review comments"
        return "Added \(added) \(noun) on \(request.identifier.displayKey). \(draftNote)"
    }

    /// Names the comment that failed and how many were never attempted, so the model can tell
    /// which of its comments still need a call.
    static func failureNote(
        request: PullRequestHostToolReviewCommentsRequest,
        written: PullRequestHostToolWrittenComments
    ) -> String {
        guard let index = written.outcomes.firstIndex(where: { $0.status == "failed" }) else {
            return ""
        }
        let comment = request.comments[index]
        let reason = written.outcomes[index].message ?? ""
        let skipped = written.outcomes.filter { $0.status == "skipped" }.count
        let note = "The comment on \(comment.path):\(comment.line) failed: \(reason)"
        guard skipped > 0 else {
            return note
        }
        return "\(note) The \(skipped) later comment(s) were not attempted."
    }

    /// Returns the thread's path, so the result can name where the reply landed.
    func postReply(_ request: PullRequestHostToolThreadReplyRequest) async throws -> String {
        let detail = try await fetchDetail(request.identifier)
        let thread = try Self.thread(withID: request.threadID, in: detail)
        guard let replyTarget = thread.replyTargetCommentID else {
            // GitHub accepts no reply until the review holding the thread is submitted, and a
            // pending thread is the user's own draft.
            throw thread.isPending
                ? PullRequestHostToolServiceError.reviewThreadPendingNoReplies
                : PullRequestHostToolServiceError.reviewThreadMissingReplyTarget
        }
        do {
            try await pullRequestsService.replyToReviewComment(
                request.identifier,
                commentID: replyTarget,
                body: request.body
            )
        } catch let error as PullRequestsServiceError {
            throw Self.unavailable(error)
        }
        return thread.path
    }
}
