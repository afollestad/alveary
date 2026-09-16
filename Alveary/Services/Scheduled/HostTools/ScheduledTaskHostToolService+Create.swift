import AgentCLIKit
import Foundation

extension ScheduledTaskHostToolService {
    /// The definition and its retry receipt commit together, before the scheduler is notified.
    /// A lost result or failed save can therefore never create a second callback on exact retry.
    func createImmediately(
        resolution: ScheduledTaskHostToolProposalResolution,
        source: ScheduledTaskHostToolSource,
        identity: ScheduledTaskHostToolProposalIdentity,
        context: AgentCLIKit.AgentHostToolCallContext,
        at acceptanceDate: Date
    ) throws -> AgentCLIKit.AgentHostToolResult {
        guard let draft = resolution.definitionDraft,
              case .once(let occurrence) = draft.recurrence,
              occurrence > acceptanceDate else {
            throw HostToolRequestError.invalidArguments("A one-off scheduled task must have a future execution time.")
        }
        let target = try draft.targetConversationID.map {
            try resolveTargetThread(conversationID: $0, exact: draft.exactTargetConversationID != nil).thread
        }
        let edit = ScheduledTaskDefinitionEdit(
            title: draft.title, prompt: draft.prompt, destination: draft.destination,
            recurrence: draft.recurrence, timeZoneIdentifier: draft.timeZoneIdentifier,
            harnessID: draft.harnessID, model: draft.model, effort: draft.effort, permissionMode: draft.permissionMode,
            workspaceKind: draft.workspaceKind, workspaceStrategy: draft.workspaceStrategy,
            grantedRoots: draft.grantedRoots, project: resolution.project, targetThread: target,
            exactTargetConversationID: draft.exactTargetConversationID,
            threadSection: draft.sectionID.flatMap { modelContext.resolveSidebarSection(id: $0) },
            workspaceSnapshot: draft.workspaceSnapshot
        )
        var committedReceipt: ScheduledTaskProposalReceipt?
        let definition = try mutationService.create(edit: edit, at: acceptanceDate, prepareCommit: { definition in
            let receipt = self.creationReceipt(
                definition: definition, identity: identity, context: context,
                occurrence: occurrence, placementSummary: resolution.placementSummary
            )
            try source.conversation.recordScheduledTaskProposalReceipt(receipt)
            committedReceipt = receipt
        }, save: saveChanges)
        guard let receipt = committedReceipt else { throw ScheduledTaskHostToolServiceError.persistenceFailure }
        ScheduledTaskProposalOutcomeRecorder.record(
            ScheduledTaskProposalOutcomeTarget(
                proposalID: definition.id, sourceConversationID: source.conversation.id, title: definition.title
            ),
            outcome: .confirmed, definitionID: definition.id, requiresKeyMatch: true, in: modelContext, at: acceptanceDate
        )
        return appliedResult(receipt: receipt)
    }

    private func creationReceipt(
        definition: ScheduledTask,
        identity: ScheduledTaskHostToolProposalIdentity,
        context: AgentCLIKit.AgentHostToolCallContext,
        occurrence: Date,
        placementSummary: String?
    ) -> ScheduledTaskProposalReceipt {
        let destination: String
        switch definition.destination {
        case .existingThread: destination = definition.exactTargetConversationID == nil ? "existing_thread" : "current_thread"
        case .newThreadPerRun: destination = "new_thread"
        case .reusedThread: destination = "reused_thread"
        }
        let timestamp = ScheduledTaskHostToolTimestamp.string(occurrence)
        // Stable tokens carry identity and the accepted time through plain-text-only harnesses.
        var message = "Created one-time scheduled task (id: \(definition.id)) (at: \(timestamp)). "
        message += "\"\(definition.title)\" is scheduled for \(occurrence.formatted(date: .abbreviated, time: .standard)). "
        message += "Destination: \(destination)."
        if let placementSummary { message += " \(placementSummary)" }
        return ScheduledTaskProposalReceipt(
            deduplicationKey: identity.deduplicationKey, proposalID: identity.deduplicationKey,
            action: .create, title: definition.title, outcomeStatus: Self.appliedStatus, message: message,
            sourceProcessToken: context.processToken.uuidString.lowercased(), createdAt: identity.createdAt,
            workspaceSnapshot: definition.workspaceSnapshot, projectID: definition.project?.id,
            definitionID: definition.id, scheduledAt: timestamp, destination: destination
        )
    }
}
