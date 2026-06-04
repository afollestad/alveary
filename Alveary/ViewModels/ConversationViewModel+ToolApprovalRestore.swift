import AgentCLIKit
import Foundation
import SwiftData

struct AskUserQuestionApprovalCandidate {
    let request: ToolApprovalRequest
    let shouldCheckSessionResolution: Bool
}

extension ConversationViewModel {
    func latestUnresolvedToolApproval() -> ToolApprovalRequest? {
        let conversationID = conversation.id
        guard let approvalRecord = latestToolApprovalRecord(conversationID: conversationID) else {
            return nil
        }

        let toolUseId = approvalRecord.toolId ?? approvalRecord.id
        guard approvalRecord.toolApprovalStatus == nil else {
            return nil
        }
        guard !hasResolutionAfterApproval(conversationID: conversationID, toolUseId: toolUseId, approvalRecord: approvalRecord) else {
            return nil
        }

        return ToolApprovalRequest(
            sessionId: approvalRecord.content ?? "",
            toolUseId: toolUseId,
            toolName: approvalRecord.toolName ?? "Tool",
            toolInput: approvalRecord.toolInput ?? "{}"
        )
    }

    func latestUnresolvedAskUserQuestionApprovalCandidate(promptId: String) -> AskUserQuestionApprovalCandidate? {
        let conversationID = conversation.id
        let approvalRecords = askUserQuestionApprovalRecords(conversationID: conversationID, promptId: promptId)
        guard let approvalRecord = approvalRecords.first(where: { record in
            let toolUseId = record.toolId ?? record.id
            return record.toolApprovalStatus == nil &&
                !hasResolutionAfterApproval(conversationID: conversationID, toolUseId: toolUseId, approvalRecord: record)
        }) else {
            return nil
        }

        let toolUseId = approvalRecord.toolId ?? approvalRecord.id
        let olderApprovalRecords = approvalRecords.drop { $0.id != approvalRecord.id }.dropFirst()
        let hasOlderResolvedApproval = olderApprovalRecords.contains { $0.toolApprovalStatus != nil }

        return AskUserQuestionApprovalCandidate(
            request: ToolApprovalRequest(
                sessionId: approvalRecord.content ?? "",
                toolUseId: toolUseId,
                toolName: approvalRecord.toolName ?? "AskUserQuestion",
                toolInput: approvalRecord.toolInput ?? "{}"
            ),
            shouldCheckSessionResolution: !hasOlderResolvedApproval
        )
    }

    func resolvedToolApprovalStatusFromClaudeSession(_ approval: ToolApprovalRequest) -> ToolApprovalStatus? {
        let providerId = conversation.provider ?? settingsService.current.defaultProvider
        guard providerId == "claude",
              let workingDirectory = dbConversation()?.thread?.worktreePath ?? dbConversation()?.thread?.project?.path else {
            return nil
        }

        let transcriptReader = AgentCLIKit.ClaudeHookTranscriptReader()
        let resolution = transcriptReader.resolution(
            forToolUseId: AgentCLIKit.AgentInteractionID(rawValue: approval.toolUseId),
            sessionId: AgentCLIKit.AgentSessionID(rawValue: approval.sessionId),
            workingDirectoryPath: workingDirectory
        )
        switch resolution {
        case .some(.permissionDecision(.allow)):
            return .approved
        case .some(.permissionDecision(.deny)):
            return .denied
        case .some(.nonBlockingError):
            return .superseded
        case .some(.permissionDecision(.deferDecision)), .none:
            return nil
        }
    }

    private func askUserQuestionApprovalRecords(
        conversationID: String,
        promptId: String
    ) -> [ConversationEventRecord] {
        (try? modelContext.fetch(
            FetchDescriptor<ConversationEventRecord>(
                predicate: #Predicate {
                    $0.conversationId == conversationID &&
                        $0.type == "tool_approval" &&
                        $0.toolId == promptId &&
                        $0.toolName == "AskUserQuestion"
                },
                sortBy: [
                    SortDescriptor(\.timestamp, order: .reverse),
                    SortDescriptor(\.id, order: .reverse)
                ]
            )
        )) ?? []
    }

    private func latestToolApprovalRecord(conversationID: String) -> ConversationEventRecord? {
        try? modelContext.fetch(
            FetchDescriptor<ConversationEventRecord>(
                predicate: #Predicate {
                    $0.conversationId == conversationID &&
                        $0.type == "tool_approval" &&
                        $0.toolApprovalStatus == nil
                },
                sortBy: [
                    SortDescriptor(\.timestamp, order: .reverse),
                    SortDescriptor(\.id, order: .reverse)
                ]
            )
        ).first
    }

    private func hasResolutionAfterApproval(
        conversationID: String,
        toolUseId: String,
        approvalRecord: ConversationEventRecord
    ) -> Bool {
        let approvalTimestamp = approvalRecord.timestamp
        if hasToolResultAfterApproval(
            conversationID: conversationID,
            toolUseId: toolUseId,
            approvalTimestamp: approvalTimestamp
        ) {
            return true
        }

        return laterTokensResolveApproval(
            conversationID: conversationID,
            approvalTimestamp: approvalTimestamp
        )
    }

    private func hasToolResultAfterApproval(
        conversationID: String,
        toolUseId: String,
        approvalTimestamp: Date
    ) -> Bool {
        (try? modelContext.fetch(
            FetchDescriptor<ConversationEventRecord>(
                predicate: #Predicate {
                    $0.conversationId == conversationID &&
                        $0.type == "tool_result" &&
                        $0.toolId == toolUseId &&
                        $0.timestamp > approvalTimestamp
                }
            )
        ).isEmpty == false) ?? false
    }

    private func laterTokensResolveApproval(
        conversationID: String,
        approvalTimestamp: Date
    ) -> Bool {
        let laterTokens = (try? modelContext.fetch(
            FetchDescriptor<ConversationEventRecord>(
                predicate: #Predicate {
                    $0.conversationId == conversationID &&
                        $0.type == "tokens" &&
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
