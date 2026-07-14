import AgentCLIKit
import Foundation
import SwiftData

extension ScheduledTaskHostToolService {
    func pendingResult(
        receipt: ScheduledTaskProposalReceipt
    ) -> AgentCLIKit.AgentHostToolResult {
        var structuredContent: [String: AgentCLIKit.JSONValue] = [
            "status": .string("pending_confirmation"),
            "proposal_id": .string(receipt.proposalID),
            "message": .string(receipt.message)
        ]
        if let action = receipt.action {
            structuredContent["action"] = .string(action.rawValue)
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
