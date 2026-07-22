import AgentCLIKit
import Foundation

@MainActor
enum ScheduledTaskExistingTargetReadiness {
    static func hasBlockingPersistedInteraction(in conversation: Conversation) -> Bool {
        let records = conversation.events
        if records.contains(where: isUnansweredPrompt) {
            return true
        }
        return records.contains { record in
            isUnresolvedApproval(record, among: records)
        }
    }

    private static func isUnansweredPrompt(_ record: ConversationEventRecord) -> Bool {
        record.type == "tool_call" &&
            record.toolName == "AskUserQuestion" &&
            record.content?.isEmpty != false
    }

    private static func isUnresolvedApproval(
        _ approval: ConversationEventRecord,
        among records: [ConversationEventRecord]
    ) -> Bool {
        guard approval.type == "tool_approval",
              approval.toolApprovalStatus == nil else {
            return false
        }
        let approvalTimestamp = approval.timestamp
        let laterRecords = records.filter { $0.timestamp > approvalTimestamp }
        if approval.toolName == "ExitPlanMode",
           laterRecords.contains(where: isImplementationToolCall) {
            return false
        }
        let toolUseID = approval.toolId ?? approval.id
        if laterRecords.contains(where: {
            $0.type == "tool_result" && $0.toolId == toolUseID
        }) {
            return false
        }
        return !laterRecords.contains(where: isTerminalTokenRecord)
    }

    private static func isImplementationToolCall(_ record: ConversationEventRecord) -> Bool {
        record.type == "tool_call" &&
            record.toolName != nil &&
            record.toolName != "ExitPlanMode"
    }

    private static func isTerminalTokenRecord(_ record: ConversationEventRecord) -> Bool {
        guard record.type == "tokens",
              let stopReason = record.stopReason else {
            return false
        }
        return stopReason != "tool_deferred" &&
            stopReason != ConversationEvent.interimUsageStopReason
    }
}
