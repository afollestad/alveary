import AgentCLIKit
import Foundation

extension PullRequestHostToolService {
    /// Resolves or unresolves a review thread. One handler for both tools: which way it flips is
    /// the tool's name, never an argument, so neither can be steered into the other.
    ///
    /// No receipt ledger — resolution is idempotent, and the thread's own state is the record. A
    /// thread already in the requested state reports it as a success, like `pin_thread` does.
    func setThreadResolved(
        context: AgentCLIKit.AgentHostToolCallContext,
        arguments: [String: AgentCLIKit.JSONValue],
        resolved: Bool
    ) async throws -> AgentCLIKit.AgentHostToolResult {
        try flushPendingChanges()
        _ = try resolveSource(context: context)
        let request = try parseThreadResolution(arguments: arguments)

        let detail = try await fetchDetail(request.identifier)
        let thread = try Self.thread(withID: request.threadID, in: detail)
        guard thread.isResolved != resolved else {
            let status = resolved ? "already_resolved" : "already_unresolved"
            return mutationResult(
                status: status,
                message: "That review thread on \(thread.path) in \(request.identifier.displayKey) was already " +
                    "\(resolved ? "resolved" : "unresolved"). Nothing changed.",
                fields: ["thread_id": .string(request.threadID)]
            )
        }
        guard let nodeID = thread.nodeID else {
            throw PullRequestHostToolServiceError.reviewThreadMissingResolutionHandle
        }

        do {
            try await pullRequestsService.setReviewThreadResolved(threadID: nodeID, resolved: resolved)
        } catch let error as PullRequestsServiceError {
            throw Self.unavailable(error)
        }

        let status = resolved ? "resolved" : "unresolved"
        return mutationResult(
            status: status,
            message: "Marked the review thread on \(thread.path) in \(request.identifier.displayKey) " +
                "\(status) on GitHub.",
            fields: ["thread_id": .string(request.threadID)]
        )
    }
}
