import Foundation
import SwiftData

/// Fetch shapes shared by the session-approval store.
///
/// Each `#Predicate` expands into a deeply nested generic `PredicateExpressions` tree, and the cost
/// of type-checking one grows with its number of `&&` terms. The same shapes were written at
/// several call sites, so every copy paid that cost again; declaring each one here keeps a single
/// expansion per shape. Keep them to three terms — a fourth or fifth pushes a shape past the
/// type-check budget on CI, so match any further fields in memory.
extension DefaultClaudeApprovalPersistenceStore {
    /// The stored rules a grant would duplicate.
    ///
    /// Only the session triple is a predicate; the two match fields are compared in memory. A
    /// five-term `#Predicate` took ~6s to type-check on CI — twice the budget — and one provider
    /// session holds a handful of rules, so narrowing the fetch and filtering costs nothing.
    static func sessionApprovalRules(
        matching grant: AgentSessionApprovalGrant,
        in context: ModelContext
    ) -> [AgentSessionApprovalRule] {
        let rules = (try? context.fetch(
            sessionApprovalRulesDescriptor(
                providerId: grant.providerId,
                conversationId: grant.conversationId,
                sessionId: grant.sessionId
            )
        )) ?? []
        let matchKind = grant.matchKind.rawValue
        return rules.filter { $0.matchKind == matchKind && $0.matchValue == grant.matchValue }
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
