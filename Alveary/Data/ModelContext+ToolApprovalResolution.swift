import Foundation
import SwiftData

/// Whether a `tool_approval` row with no `toolApprovalStatus` is still actionable.
///
/// A `nil` status means nobody ever answered the prompt, but it does not prove the prompt is
/// still open: the provider can run the tool anyway, or end the turn, without Alveary stamping
/// the row. Both the transcript restore path and the sidebar's waiting dot have to tell those
/// apart, so the fetch shapes live here rather than being copied per caller — see the
/// **Fetch Predicates** section in this folder's `AGENTS.md` for why a predicate gets one home.
extension ModelContext {
    /// `toolUseId` is the caller's `toolId ?? id` fallback; approval rows recorded before tool
    /// ids were persisted key off their own record id.
    func hasToolApprovalResolution(
        conversationID: String,
        toolUseId: String,
        approvalTimestamp: Date
    ) -> Bool {
        if hasToolResultAfterApproval(
            conversationID: conversationID,
            toolUseId: toolUseId,
            approvalTimestamp: approvalTimestamp
        ) {
            return true
        }

        return laterTokensResolveToolApproval(
            conversationID: conversationID,
            approvalTimestamp: approvalTimestamp
        )
    }

    private func hasToolResultAfterApproval(
        conversationID: String,
        toolUseId: String,
        approvalTimestamp: Date
    ) -> Bool {
        let recordType = ConversationEventRecord.toolResultType
        return (try? fetch(
            FetchDescriptor<ConversationEventRecord>(
                predicate: #Predicate {
                    $0.conversationId == conversationID &&
                        $0.type == recordType &&
                        $0.toolId == toolUseId &&
                        $0.timestamp > approvalTimestamp
                }
            )
        ).isEmpty == false) ?? false
    }

    /// A `tool_deferred` stop is the turn parking on this very approval, and interim usage rows
    /// are not turn boundaries; any other later stop reason means the turn moved on without it.
    private func laterTokensResolveToolApproval(
        conversationID: String,
        approvalTimestamp: Date
    ) -> Bool {
        let recordType = ConversationEventRecord.tokensType
        let laterTokens = (try? fetch(
            FetchDescriptor<ConversationEventRecord>(
                predicate: #Predicate {
                    $0.conversationId == conversationID &&
                        $0.type == recordType &&
                        $0.timestamp > approvalTimestamp
                }
            )
        )) ?? []
        return laterTokens.contains { token in
            guard let stopReason = token.stopReason else {
                return false
            }
            return stopReason != "tool_deferred" &&
                stopReason != ConversationEvent.interimUsageStopReason
        }
    }
}
