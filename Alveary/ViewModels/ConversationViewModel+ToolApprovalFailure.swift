import Foundation
import SwiftData

extension ConversationViewModel {
    func toolApprovalFailure(
        _ failure: ToolApprovalFailure,
        matches request: ToolApprovalRequest
    ) -> Bool {
        guard failure.toolUseId == request.toolUseId else {
            return false
        }
        guard failure.sessionId == nil || failure.sessionId == request.sessionId else {
            return false
        }
        return true
    }

    func supersedeFailedToolApprovalRecord(_ failure: ToolApprovalFailure) -> Bool {
        guard let toolUseId = failure.toolUseId else {
            return false
        }

        let conversationID = conversation.id
        let sessionId = failure.sessionId
        let approvalRecords = (try? modelContext.fetch(
            FetchDescriptor<ConversationEventRecord>(
                predicate: #Predicate {
                    $0.conversationId == conversationID &&
                        $0.type == "tool_approval" &&
                        $0.toolId == toolUseId &&
                        $0.toolApprovalStatus == nil
                },
                sortBy: [
                    SortDescriptor(\.timestamp, order: .reverse),
                    SortDescriptor(\.id, order: .reverse)
                ]
            )
        )) ?? []

        guard let approvalRecord = approvalRecords.first(where: { record in
            sessionId == nil || record.content == sessionId
        }) else {
            return false
        }

        approvalRecord.toolApprovalStatus = ToolApprovalStatus.superseded.rawValue
        do {
            try modelContext.save()
            return true
        } catch {
            // Best-effort: the persisted hook error still explains why the approval is dead.
            return false
        }
    }
}
