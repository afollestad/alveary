import Foundation
import SwiftData

extension ConversationViewModel {
    /// Whether a hook failure belongs to the approval currently on screen.
    ///
    /// A failure without a `sessionId` matches on the tool use alone: the provider could not
    /// name the session, and refusing to match would leave the row pending forever.
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

    /// Marks the persisted row for a hook that died `superseded`, so restore cannot rehydrate it.
    ///
    /// `superseded` rather than `denied`: nothing was decided, and a denial would misreport the
    /// user's action in the transcript. Only never-answered rows (`toolApprovalStatus == nil`)
    /// are eligible, so this cannot overwrite a decision already made.
    func supersedeFailedToolApprovalRecord(_ failure: ToolApprovalFailure) -> Bool {
        guard let toolUseId = failure.toolUseId else {
            return false
        }

        let conversationID = conversation.id
        let sessionId = failure.sessionId
        let recordType = ConversationEventRecord.toolApprovalType
        let approvalRecords = (try? modelContext.fetch(
            FetchDescriptor<ConversationEventRecord>(
                predicate: #Predicate {
                    $0.conversationId == conversationID &&
                        $0.type == recordType &&
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
