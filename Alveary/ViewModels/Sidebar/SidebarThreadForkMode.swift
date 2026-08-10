enum SidebarThreadForkMode: Sendable, Equatable {
    case local
    case worktree

    var sessionForkMode: AgentSessionForkMode {
        switch self {
        case .local:
            return .local
        case .worktree:
            return .worktree
        }
    }
}
