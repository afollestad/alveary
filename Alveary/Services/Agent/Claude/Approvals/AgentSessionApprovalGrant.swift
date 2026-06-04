/// Supported matching modes for reusable Claude session approvals.
enum AgentSessionApprovalRuleKind: String, Sendable, Equatable, Hashable {
    /// Match a single normalized Bash command exactly.
    case bashExact
    /// Match the conservative Bash command family derived from an immediate subcommand.
    case bashCommandGroup
    /// Match a single canonical file path exactly.
    case filePathExact
}

/// Durable reusable approval grant selected by the user for one provider session.
struct AgentSessionApprovalGrant: Sendable, Equatable, Hashable {
    let providerId: String
    let conversationId: String
    let sessionId: String
    let matchKind: AgentSessionApprovalRuleKind
    let matchValue: String
}

/// Result of attempting to persist a reusable session approval.
struct SessionApprovalRecordResult: Sendable, Equatable {
    let isEffective: Bool
    let wasInserted: Bool
}
