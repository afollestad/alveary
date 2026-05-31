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
              let workingDirectory = dbConversation()?.thread?.worktreePath ?? dbConversation()?.thread?.project?.path,
              let sessionFilePath = ClaudeAdapter().sessionFilePath(
                  sessionId: approval.sessionId,
                  cwd: workingDirectory
              ),
              let contents = try? String(contentsOfFile: sessionFilePath, encoding: .utf8) else {
            return nil
        }

        for line in contents.split(whereSeparator: \.isNewline) {
            guard let data = String(line).data(using: .utf8),
                  let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  event["type"] as? String == "attachment",
                  let attachment = event["attachment"] as? [String: Any],
                  attachmentToolUseId(from: attachment) == approval.toolUseId,
                  let attachmentType = attachment["type"] as? String else {
                continue
            }

            if attachmentType == "hook_non_blocking_error" {
                return .superseded
            }

            guard attachmentType == "hook_success",
                  let decision = hookPermissionDecision(from: attachment["stdout"] as? String) else {
                continue
            }

            switch decision {
            case ClaudeHookResponseDecision.allow.rawValue:
                return .approved
            case ClaudeHookResponseDecision.deny.rawValue:
                return .denied
            default:
                break
            }
        }

        return nil
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

    private func hookPermissionDecision(from stdout: String?) -> String? {
        guard let stdout,
              let data = stdout.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let output = object["hookSpecificOutput"] as? [String: Any] else {
            return nil
        }
        return output["permissionDecision"] as? String
    }

    private func attachmentToolUseId(from attachment: [String: Any]) -> String? {
        (attachment["toolUseID"] as? String) ?? (attachment["tool_use_id"] as? String)
    }
}
