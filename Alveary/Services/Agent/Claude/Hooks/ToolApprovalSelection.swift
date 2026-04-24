enum ToolApprovalSessionScope: String, CaseIterable, Sendable, Equatable {
    case exact
    case group

    var pendingTitle: String {
        switch self {
        case .exact:
            return "Approve exactly"
        case .group:
            return "Approve group"
        }
    }

    var resolvedTitle: String {
        switch self {
        case .exact:
            return "Approved exactly"
        case .group:
            return "Approved group"
        }
    }
}

enum ToolApprovalSelection: String, Sendable, Equatable, Hashable {
    case once
    case sessionExact
    case sessionGroup

    init(sessionScope: ToolApprovalSessionScope) {
        switch sessionScope {
        case .exact:
            self = .sessionExact
        case .group:
            self = .sessionGroup
        }
    }

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

struct PendingToolApproval: Sendable, Equatable {
    var request: ToolApprovalRequest
    var status: ToolApprovalStatus
}
