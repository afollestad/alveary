import AgentCLIKit
import Foundation

extension PullRequestHostToolService {
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

private extension PullRequestHostToolService {
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
