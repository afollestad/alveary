enum AgentSessionApprovalRuleKind: String, Sendable, Equatable, Hashable {
    case bashExact
    case bashCommandGroup
    case filePathExact
}

struct AgentSessionApprovalGrant: Sendable, Equatable, Hashable {
    let providerId: String
    let conversationId: String
    let sessionId: String
    let matchKind: AgentSessionApprovalRuleKind
    let matchValue: String
}

struct SessionApprovalRecordResult: Sendable, Equatable {
    let isEffective: Bool
    let wasInserted: Bool
}
