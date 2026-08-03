import AgentCLIKit
import Foundation
import SwiftData

extension ScheduledTaskHostToolService {
    func pendingResult(
        receipt: ScheduledTaskProposalReceipt
    ) -> AgentCLIKit.AgentHostToolResult {
        guard receipt.outcomeStatus != ScheduledTaskHostToolService.appliedStatus else {
            return appliedResult(receipt: receipt)
        }
        var structuredContent: [String: AgentCLIKit.JSONValue] = [
            "status": .string("pending_confirmation"),
            "proposal_id": .string(receipt.proposalID),
            "message": .string(receipt.message)
        ]
        if let action = receipt.action {
            structuredContent["action"] = .string(action.rawValue)
        }
        if let title = receipt.title {
            structuredContent["title"] = .string(title)
        }
        return AgentCLIKit.AgentHostToolResult(
            text: receipt.message,
            structuredContent: .object(structuredContent)
        )
    }

    /// Result for an action that ran without confirmation.
    func appliedResult(
        receipt: ScheduledTaskProposalReceipt
    ) -> AgentCLIKit.AgentHostToolResult {
        var structuredContent: [String: AgentCLIKit.JSONValue] = [
            "status": .string(ScheduledTaskHostToolService.appliedStatus),
            "message": .string(receipt.message)
        ]
        if let action = receipt.action {
            structuredContent["action"] = .string(action.rawValue)
        }
        if let title = receipt.title {
            structuredContent["title"] = .string(title)
        }
        return AgentCLIKit.AgentHostToolResult(
            text: receipt.message,
            structuredContent: .object(structuredContent)
        )
    }

    func makeReceipt(
        deduplicationKey: String,
        proposal: ScheduledTaskProposal,
        message: String,
        sourceProcessToken: UUID,
        createdAt: Date
    ) -> ScheduledTaskProposalReceipt {
        ScheduledTaskProposalReceipt(
            deduplicationKey: deduplicationKey,
            proposalID: proposal.id,
            action: proposal.action,
            title: proposal.targetTitleSnapshot ?? proposal.definitionDraft?.title,
            message: message,
            sourceProcessToken: sourceProcessToken.uuidString.lowercased(),
            createdAt: createdAt
        )
    }

    func persistReceiptMaintenanceIfNeeded() throws {
        guard modelContext.hasChanges else {
            return
        }
        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw ScheduledTaskHostToolServiceError.persistenceFailure
        }
    }

    func persist(
        _ proposal: ScheduledTaskProposal,
        receipt: ScheduledTaskProposalReceipt,
        on sourceConversation: Conversation
    ) throws {
        do {
            modelContext.insert(proposal)
            // The proposal is confirmed in that conversation's transcript widget, so the
            // unread badge is what leads the user back to it from elsewhere in the app.
            sourceConversation.isUnread = true
            try sourceConversation.recordScheduledTaskProposalReceipt(receipt)
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw ScheduledTaskHostToolServiceError.persistenceFailure
        }
    }

    func persist(
        _ receipt: ScheduledTaskProposalReceipt,
        on sourceConversation: Conversation
    ) throws {
        do {
            try sourceConversation.recordScheduledTaskProposalReceipt(receipt)
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw ScheduledTaskHostToolServiceError.persistenceFailure
        }
    }

    func errorResult(
        for error: Error,
        toolName: String
    ) -> AgentCLIKit.AgentHostToolResult {
        let message: String
        switch error {
        case let requestError as ScheduledTaskHostToolRequestError:
            message = requestError.localizedDescription
        case let serviceError as ScheduledTaskHostToolServiceError:
            message = serviceError.localizedDescription
        default:
            message = ScheduledTaskHostToolServiceError.persistenceFailure.localizedDescription
        }
        let structuredContent: AgentCLIKit.JSONValue? = toolName == ScheduledTaskHostToolCatalog.proposeToolName
            ? .object([
                "status": .string("error"),
                "message": .string(message)
            ])
            : nil
        return AgentCLIKit.AgentHostToolResult(text: message, structuredContent: structuredContent, isError: true)
    }
}
