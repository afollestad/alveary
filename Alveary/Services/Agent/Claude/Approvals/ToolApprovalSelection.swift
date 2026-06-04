/// Reusable session-approval scopes that can be offered for a tool approval.
enum ToolApprovalSessionScope: String, CaseIterable, Sendable, Equatable {
    case exact
    case group

    /// Button title while the approval is still pending.
    var pendingTitle: String {
        switch self {
        case .exact:
            return "Approve exactly"
        case .group:
            return "Approve group"
        }
    }

    /// Button title after the approval resolves.
    var resolvedTitle: String {
        switch self {
        case .exact:
            return "Approved exactly"
        case .group:
            return "Approved group"
        }
    }
}

/// User's selected approval mode for a tool approval prompt.
enum ToolApprovalSelection: String, Sendable, Equatable, Hashable {
    case once
    case sessionExact
    case sessionGroup

    /// Creates a reusable approval selection for a session scope.
    init(sessionScope: ToolApprovalSessionScope) {
        switch sessionScope {
        case .exact:
            self = .sessionExact
        case .group:
            self = .sessionGroup
        }
    }

    /// Session scope represented by this selection, or `nil` for one-shot approvals.
    var sessionScope: ToolApprovalSessionScope? {
        switch self {
        case .once:
            return nil
        case .sessionExact:
            return .exact
        case .sessionGroup:
            return .group
        }
    }

    /// Coerces the selection to the first currently available scope when needed.
    func normalized(for availableScopes: [ToolApprovalSessionScope]) -> ToolApprovalSelection {
        guard let sessionScope else {
            return .once
        }
        if availableScopes.contains(sessionScope) {
            return self
        }
        if let firstScope = availableScopes.first {
            return ToolApprovalSelection(sessionScope: firstScope)
        }
        return .once
    }
}

/// Persisted/UI state for an approval row in the transcript.
enum ToolApprovalStatus: String, Sendable, Equatable {
    case pending
    case approving
    case denying
    case approvingForSessionExact
    case approvingForSessionGroup
    case approved
    case approvedForSessionExact
    case approvedForSessionGroup
    case denied
    case superseded
}

/// Pending approval request paired with its current UI status.
struct PendingToolApproval: Sendable, Equatable {
    var request: ToolApprovalRequest
    var status: ToolApprovalStatus
}
