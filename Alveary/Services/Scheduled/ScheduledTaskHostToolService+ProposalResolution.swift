import AgentCLIKit

extension ScheduledTaskHostToolService {
    func resolveProposal(
        _ request: ScheduledTaskProposalRequest,
        sourceThread: AgentThread,
        sourceProviderID: String
    ) throws -> ScheduledTaskHostToolProposalResolution {
        switch request {
        case let .create(title, prompt, schedule):
            return try resolveCreateProposal(
                title: title,
                prompt: prompt,
                schedule: schedule,
                sourceThread: sourceThread,
                sourceProviderID: sourceProviderID
            )
        case let .edit(definitionID, expectedRevision, changes):
            return try resolveEditProposal(
                definitionID: definitionID,
                expectedRevision: expectedRevision,
                changes: changes
            )
        case let .pause(definitionID, expectedRevision):
            return try resolvePauseProposal(definitionID: definitionID, expectedRevision: expectedRevision)
        case let .resume(definitionID, expectedRevision):
            return try resolveResumeProposal(definitionID: definitionID, expectedRevision: expectedRevision)
        case let .delete(definitionID, expectedRevision):
            let definition = try resolveTargetDefinition(
                id: definitionID,
                expectedRevision: expectedRevision
            )
            return targetResolution(definition)
        case let .runNow(definitionID, expectedRevision):
            return try resolveRunNowProposal(definitionID: definitionID, expectedRevision: expectedRevision)
        }
    }

    func resolveCreateProposal(
        title: String,
        prompt: String,
        schedule: ScheduledTaskProposalSchedule,
        sourceThread: AgentThread,
        sourceProviderID: String
    ) throws -> ScheduledTaskHostToolProposalResolution {
        let workspace = try sourceWorkspace(for: sourceThread)
        let draft = ScheduledTaskProposalDefinitionDraft(
            title: title,
            prompt: prompt,
            recurrence: schedule.recurrence,
            timeZoneIdentifier: schedule.timeZoneIdentifier,
            providerID: sourceProviderID,
            model: sourceThread.model,
            effort: sourceThread.effort,
            permissionMode: sourceThread.permissionMode,
            workspaceKind: workspace.kind,
            workspaceStrategy: workspace.strategy,
            grantedRoots: workspace.grantedRoots,
            projectPath: workspace.project?.path
        )
        return ScheduledTaskHostToolProposalResolution(
            definitionDraft: draft,
            project: workspace.project
        )
    }

    func resolveEditProposal(
        definitionID: String,
        expectedRevision: Int,
        changes: ScheduledTaskProposalEditChanges
    ) throws -> ScheduledTaskHostToolProposalResolution {
        let definition = try resolveTargetDefinition(
            id: definitionID,
            expectedRevision: expectedRevision
        )
        let draft = try editedDraft(definition: definition, changes: changes)
        return targetResolution(definition, definitionDraft: draft)
    }

    func resolvePauseProposal(
        definitionID: String,
        expectedRevision: Int
    ) throws -> ScheduledTaskHostToolProposalResolution {
        let definition = try resolveTargetDefinition(id: definitionID, expectedRevision: expectedRevision)
        guard definition.state == .active else {
            throw ScheduledTaskHostToolServiceError.pauseRequiresActiveDefinition
        }
        return targetResolution(definition)
    }

    func resolveResumeProposal(
        definitionID: String,
        expectedRevision: Int
    ) throws -> ScheduledTaskHostToolProposalResolution {
        let definition = try resolveTargetDefinition(id: definitionID, expectedRevision: expectedRevision)
        guard definition.state == .paused else {
            throw ScheduledTaskHostToolServiceError.resumeRequiresPausedDefinition
        }
        if definition.workspaceKind == .project, definition.project == nil {
            throw ScheduledTaskHostToolServiceError.workspaceUnavailable
        }
        return targetResolution(definition)
    }

    func resolveRunNowProposal(
        definitionID: String,
        expectedRevision: Int
    ) throws -> ScheduledTaskHostToolProposalResolution {
        let definition = try resolveTargetDefinition(id: definitionID, expectedRevision: expectedRevision)
        guard !definition.runs.contains(where: { !$0.hasKnownTerminalStatus }) else {
            throw ScheduledTaskHostToolServiceError.runNowBlockedByActiveRun
        }
        return targetResolution(definition)
    }

    func resolveTargetDefinition(
        id: String,
        expectedRevision: Int
    ) throws -> ScheduledTask {
        guard let definition = modelContext.resolveScheduledTask(id: id) else {
            throw ScheduledTaskHostToolServiceError.definitionNotFound
        }
        guard definition.revision == expectedRevision else {
            throw ScheduledTaskHostToolServiceError.revisionConflict(
                expected: expectedRevision,
                actual: definition.revision
            )
        }
        return definition
    }

    func editedDraft(
        definition: ScheduledTask,
        changes: ScheduledTaskProposalEditChanges
    ) throws -> ScheduledTaskProposalDefinitionDraft {
        guard let storedRecurrence = definition.recurrence else {
            throw ScheduledTaskHostToolServiceError.invalidStoredSchedule
        }
        let recurrence = changes.schedule?.recurrence ?? storedRecurrence
        let timeZoneIdentifier = changes.schedule?.timeZoneIdentifier ?? definition.timeZoneIdentifier
        do {
            try recurrenceCalculator.validate(
                recurrence,
                timeZoneIdentifier: timeZoneIdentifier
            )
        } catch {
            throw ScheduledTaskHostToolServiceError.invalidStoredSchedule
        }

        let grantedRoots = try ScheduledTaskHostToolSupport.validatedStoredGrantedRoots(definition.grantedRoots)
        let project: Project?
        if definition.workspaceKind == .project {
            guard let resolvedProject = definition.project else {
                throw ScheduledTaskHostToolServiceError.workspaceUnavailable
            }
            try ScheduledTaskHostToolSupport.validateStoredCanonicalPath(resolvedProject.path)
            project = resolvedProject
        } else {
            project = nil
        }
        return ScheduledTaskProposalDefinitionDraft(
            title: changes.title ?? definition.title,
            prompt: changes.prompt ?? definition.prompt,
            recurrence: recurrence,
            timeZoneIdentifier: timeZoneIdentifier,
            providerID: definition.providerID,
            model: definition.model,
            effort: definition.effort,
            permissionMode: definition.permissionMode,
            workspaceKind: definition.workspaceKind,
            workspaceStrategy: definition.workspaceStrategy,
            grantedRoots: grantedRoots,
            projectPath: project?.path
        )
    }

    func sourceWorkspace(for thread: AgentThread) throws -> ScheduledTaskHostToolSourceWorkspace {
        switch thread.effectiveMode {
        case .project:
            guard let project = thread.project else {
                throw ScheduledTaskHostToolServiceError.workspaceUnavailable
            }
            try ScheduledTaskHostToolSupport.validateStoredCanonicalPath(project.path)
            return ScheduledTaskHostToolSourceWorkspace(
                kind: .project,
                strategy: .worktree,
                grantedRoots: [],
                project: project
            )
        case .task:
            guard let descriptor = thread.taskWorkspaceDescriptor else {
                throw ScheduledTaskHostToolServiceError.workspaceUnavailable
            }
            let grantedRoots = try ScheduledTaskHostToolSupport.validatedStoredGrantedRoots(descriptor.grantedRoots)
            guard let sourceProjectPath = descriptor.sourceProjectPath else {
                return ScheduledTaskHostToolSourceWorkspace(
                    kind: .privateWorkspace,
                    strategy: .worktree,
                    grantedRoots: grantedRoots,
                    project: nil
                )
            }
            try ScheduledTaskHostToolSupport.validateStoredCanonicalPath(sourceProjectPath)
            guard let project = modelContext.resolveProject(path: sourceProjectPath) else {
                return ScheduledTaskHostToolSourceWorkspace(
                    kind: .privateWorkspace,
                    strategy: .worktree,
                    grantedRoots: grantedRoots,
                    project: nil
                )
            }
            try ScheduledTaskHostToolSupport.validateStoredCanonicalPath(project.path)
            return ScheduledTaskHostToolSourceWorkspace(
                kind: .project,
                strategy: .worktree,
                grantedRoots: grantedRoots,
                project: project
            )
        }
    }

    func targetResolution(
        _ definition: ScheduledTask,
        definitionDraft: ScheduledTaskProposalDefinitionDraft? = nil
    ) -> ScheduledTaskHostToolProposalResolution {
        ScheduledTaskHostToolProposalResolution(
            targetDefinitionID: definition.id,
            expectedDefinitionRevision: definition.revision,
            targetTitleSnapshot: definition.title,
            targetScheduleSummarySnapshot: ScheduledTaskHostToolSupport.scheduleSummary(for: definition),
            definitionDraft: definitionDraft,
            project: definition.project
        )
    }

    func resolveSource(
        context: AgentCLIKit.AgentHostToolCallContext
    ) throws -> ScheduledTaskHostToolSource {
        guard let conversation = modelContext.resolveConversation(
            conversationID: context.conversationId.rawValue
        ), let thread = conversation.thread,
           !thread.isDraft,
           thread.archivedAt == nil else {
            throw ScheduledTaskHostToolServiceError.sourceConversationUnavailable
        }
        if let storedProviderID = conversation.provider,
           storedProviderID != context.providerId.rawValue {
            throw ScheduledTaskHostToolServiceError.sourceProviderMismatch
        }
        if let scheduledRun = thread.scheduledTaskRun,
           !scheduledRun.hasKnownTerminalStatus {
            throw ScheduledTaskHostToolServiceError.automatedRunCannotSchedule
        }
        return ScheduledTaskHostToolSource(
            conversation: conversation,
            thread: thread
        )
    }
}
