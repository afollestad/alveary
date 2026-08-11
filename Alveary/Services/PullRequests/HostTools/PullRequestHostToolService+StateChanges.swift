import AgentCLIKit
import Foundation

/// The state-change tools: close, reopen, and both draft directions. Immediate, like resolve and
/// unresolve — close is undone by reopen while the head branch survives, each draft direction undoes
/// the other, and the state itself is the record, so a replay lands on an `already_*` success rather
/// than acting twice. No receipt ledger.
///
/// The preconditions mirror `PullRequestStateAction.available(for:)`, the pane's own policy, so a
/// refusal here is one the footer would have shown as a missing or disabled button.
extension PullRequestHostToolService {
    func closePullRequest(
        context: AgentCLIKit.AgentHostToolCallContext,
        arguments: [String: AgentCLIKit.JSONValue]
    ) async throws -> AgentCLIKit.AgentHostToolResult {
        // Caller eligibility before any target critique, mirroring the permission-first gate below.
        try refuseAutomatedScheduledRunClose(context: context)
        let (identifier, detail) = try await stateChangeTarget(context: context, arguments: arguments)
        guard detail.status != .closed else {
            return stateChangeResult(
                status: "already_closed",
                identifier: identifier,
                message: "\(identifier.displayKey) was already closed. Nothing changed."
            )
        }
        do {
            try await pullRequestsService.setPullRequestClosed(identifier, closed: true)
        } catch let error as PullRequestsServiceError {
            throw Self.unavailable(error)
        }
        return stateChangeResult(
            status: "closed",
            identifier: identifier,
            message: "Closed \(identifier.displayKey) on GitHub without merging it. reopen_pr undoes " +
                "this while its branch still exists."
        )
    }

    func reopenPullRequest(
        context: AgentCLIKit.AgentHostToolCallContext,
        arguments: [String: AgentCLIKit.JSONValue]
    ) async throws -> AgentCLIKit.AgentHostToolResult {
        let (identifier, detail) = try await stateChangeTarget(context: context, arguments: arguments)
        guard detail.status == .closed else {
            return stateChangeResult(
                status: "already_open",
                identifier: identifier,
                message: "\(identifier.displayKey) is not closed. Nothing changed."
            )
        }
        // GitHub answers 422 once the head branch is gone; refusing up front names the branch
        // instead of surfacing a bare HTTP failure.
        guard detail.headRefExists else {
            throw PullRequestHostToolServiceError.cannotReopenWithoutHeadBranch(branch: detail.headRefName)
        }
        do {
            try await pullRequestsService.setPullRequestClosed(identifier, closed: false)
        } catch let error as PullRequestsServiceError {
            throw Self.unavailable(error)
        }
        return stateChangeResult(
            status: "reopened",
            identifier: identifier,
            message: "Reopened \(identifier.displayKey) on GitHub."
        )
    }

    func markPullRequestReady(
        context: AgentCLIKit.AgentHostToolCallContext,
        arguments: [String: AgentCLIKit.JSONValue]
    ) async throws -> AgentCLIKit.AgentHostToolResult {
        let (identifier, detail) = try await stateChangeTarget(context: context, arguments: arguments)
        switch detail.status {
        case .open:
            return stateChangeResult(
                status: "already_ready",
                identifier: identifier,
                message: "\(identifier.displayKey) is not a draft. Nothing changed."
            )
        case .closed, .merged:
            throw PullRequestHostToolServiceError
                .cannotMarkClosedPullRequestReady(status: detail.status.rawValue)
        case .draft:
            break
        }
        let nodeID = try draftMutationNodeID(detail)
        do {
            try await pullRequestsService.markPullRequestReadyForReview(nodeID: nodeID)
        } catch let error as PullRequestsServiceError {
            throw Self.unavailable(error)
        }
        return stateChangeResult(
            status: "marked_ready",
            identifier: identifier,
            message: "Marked \(identifier.displayKey) ready for review on GitHub. Its requested " +
                "reviewers are notified."
        )
    }

    func convertPullRequestToDraft(
        context: AgentCLIKit.AgentHostToolCallContext,
        arguments: [String: AgentCLIKit.JSONValue]
    ) async throws -> AgentCLIKit.AgentHostToolResult {
        let (identifier, detail) = try await stateChangeTarget(context: context, arguments: arguments)
        switch detail.status {
        case .draft:
            return stateChangeResult(
                status: "already_draft",
                identifier: identifier,
                message: "\(identifier.displayKey) is already a draft. Nothing changed."
            )
        case .closed, .merged:
            throw PullRequestHostToolServiceError
                .cannotConvertPullRequestToDraft(status: detail.status.rawValue)
        case .open:
            break
        }
        let nodeID = try draftMutationNodeID(detail)
        do {
            try await pullRequestsService.convertPullRequestToDraft(nodeID: nodeID)
        } catch let error as PullRequestsServiceError {
            throw Self.unavailable(error)
        }
        return stateChangeResult(
            status: "marked_draft",
            identifier: identifier,
            message: "Returned \(identifier.displayKey) to draft on GitHub. mark_pr_ready undoes this."
        )
    }
}

private extension PullRequestHostToolService {
    /// The shared prologue: source, arguments, fresh detail, and the permission and merged gates
    /// every state change shares.
    func stateChangeTarget(
        context: AgentCLIKit.AgentHostToolCallContext,
        arguments: [String: AgentCLIKit.JSONValue]
    ) async throws -> (PullRequestIdentifier, PullRequestDetail) {
        try flushPendingChanges()
        _ = try resolveSource(context: context)
        let identifier = try parseIdentifier(arguments: arguments)
        let detail = try await fetchDetail(identifier)
        // Permission first: a caller without write access gets that refusal, not a state critique
        // of a change it was never entitled to make.
        guard detail.viewerCanUpdate else {
            throw PullRequestHostToolServiceError.stateChangeNotPermitted
        }
        guard detail.status != .merged else {
            throw PullRequestHostToolServiceError.cannotChangeMergedPullRequest
        }
        return (identifier, detail)
    }

    /// The draft mutations are GraphQL-only, addressed by node id; without one there is nothing to
    /// call and a refetch is the only way forward.
    func draftMutationNodeID(_ detail: PullRequestDetail) throws -> String {
        guard let nodeID = detail.nodeID else {
            throw PullRequestHostToolServiceError.pullRequestUnavailable(
                "Alveary could not read that pull request's GitHub node ID."
            )
        }
        return nodeID
    }

    func stateChangeResult(
        status: String,
        identifier: PullRequestIdentifier,
        message: String
    ) -> AgentCLIKit.AgentHostToolResult {
        mutationResult(
            status: status,
            message: message,
            fields: [
                "repository": .string(identifier.nameWithOwner),
                "number": .number(Double(identifier.number))
            ]
        )
    }
}
