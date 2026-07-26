import Foundation
import SwiftData

/// Fetch shapes shared by the session-approval store.
///
/// Each `#Predicate` expands into a deeply nested generic `PredicateExpressions` tree, and the
/// cost of type-checking one grows with its number of `&&` terms — the five-way rule match below
/// was among the most expensive expressions in the app. The same shapes were written at several
/// call sites, so every copy paid that cost again. Declaring each one here keeps a single
/// expansion per shape.
extension DefaultClaudeApprovalPersistenceStore {
    /// Matches the one stored rule that a grant would duplicate.
    static func sessionApprovalRuleDescriptor(
        matching grant: AgentSessionApprovalGrant
    ) -> FetchDescriptor<AgentSessionApprovalRule> {
        let providerId = grant.providerId
        let conversationId = grant.conversationId
        let sessionId = grant.sessionId
        let matchKind = grant.matchKind.rawValue
        let matchValue = grant.matchValue
        return FetchDescriptor<AgentSessionApprovalRule>(
            predicate: #Predicate {
                $0.providerId == providerId &&
                    $0.conversationId == conversationId &&
                    $0.sessionId == sessionId &&
                    $0.matchKind == matchKind &&
                    $0.matchValue == matchValue
            }
        )
    }

    /// Matches every stored rule for one provider session.
    static func sessionApprovalRulesDescriptor(
        providerId: String,
        conversationId: String,
        sessionId: String
    ) -> FetchDescriptor<AgentSessionApprovalRule> {
        FetchDescriptor<AgentSessionApprovalRule>(
            predicate: #Predicate {
                $0.providerId == providerId &&
                    $0.conversationId == conversationId &&
                    $0.sessionId == sessionId
            }
        )
    }

    /// Matches every stored scope selection for one provider session.
    ///
    /// `sortBy` stays a parameter because only the read path orders by recency; the write and
    /// removal paths deliberately take the store's natural order.
    static func sessionApprovalSelectionsDescriptor(
        providerId: String,
        conversationId: String,
        sessionId: String,
        sortBy: [SortDescriptor<AgentSessionApprovalSelection>] = []
    ) -> FetchDescriptor<AgentSessionApprovalSelection> {
        FetchDescriptor<AgentSessionApprovalSelection>(
            predicate: #Predicate {
                $0.providerId == providerId &&
                    $0.conversationId == conversationId &&
                    $0.sessionId == sessionId
            },
            sortBy: sortBy
        )
    }
}
