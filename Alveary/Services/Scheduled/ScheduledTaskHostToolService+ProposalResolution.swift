import AgentCLIKit

extension ScheduledTaskHostToolService {
    func resolveProposal(
        _ request: ScheduledTaskProposalRequest,
        sourceThread: AgentThread,
        sourceProviderID: String
    ) throws -> ScheduledTaskHostToolProposalResolution {
        switch request {
        case let .create(title, prompt, schedule, placement):
            return try resolveCreateProposal(
                title: title,
                prompt: prompt,
                schedule: schedule,
                placement: placement,
                source: ScheduledTaskHostToolCreateSource(
                    thread: sourceThread,
                    settings: ScheduledTaskProposalAgentSettings(
                        sourceThread: sourceThread,
                        providerID: sourceProviderID
                    )
                )
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
        placement: ScheduledTaskProposalPlacement?,
        source: ScheduledTaskHostToolCreateSource
    ) throws -> ScheduledTaskHostToolProposalResolution {
        // An existing-thread schedule posts into a thread that owns its own workspace, so the
        // source thread's is never consulted — it may not even be resolvable.
        if case .existingThread(let targetConversationID) = placement {
            let target = try resolveTargetThread(conversationID: targetConversationID)
            return ScheduledTaskHostToolProposalResolution(
                definitionDraft: existingThreadDraft(
                    title: title,
                    prompt: prompt,
                    recurrence: schedule.recurrence,
                    targetConversationID: target.conversationID,
                    settings: source.settings
                ),
                project: nil,
                placementSummary: Self.placementSummary(
                    for: placement,
                    targetThread: target.thread,
                    project: nil,
                    grantedRoots: []
                )
            )
        }

        let inherited = try sourceWorkspace(for: source.thread)
        let workspace = try resolvedWorkspace(
            requested: placement?.requestedWorkspace,
            inheritedKind: inherited.kind,
            inheritedProject: inherited.project,
            inheritedGrantedRoots: inherited.grantedRoots
        )
        let draft = ScheduledTaskProposalDefinitionDraft(
            title: title,
            prompt: prompt,
            recurrence: schedule.recurrence,
            timeZoneIdentifier: currentTimeZone().identifier,
            providerID: source.settings.providerID,
            model: source.settings.model,
            effort: source.settings.effort,
            permissionMode: source.settings.permissionMode,
            workspaceKind: workspace.kind,
            workspaceStrategy: inherited.strategy,
            grantedRoots: workspace.grantedRoots,
            projectPath: workspace.project?.path
        )
        return ScheduledTaskHostToolProposalResolution(
            definitionDraft: draft,
            project: workspace.project,
            placementSummary: Self.placementSummary(
                for: placement,
                targetThread: nil,
                project: workspace.project,
                grantedRoots: workspace.grantedRoots
            )
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
        return targetResolution(
            definition,
            edited: try editedDraft(definition: definition, changes: changes)
        )
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
        guard let destination = definition.decodedDestination else {
            throw ScheduledTaskHostToolServiceError.invalidStoredSchedule
        }
        if definition.workspaceKind == .project, definition.project == nil {
            if destination == .existingThread {
                return targetResolution(definition)
            }
            throw ScheduledTaskHostToolServiceError.workspaceUnavailable
        }
        return targetResolution(definition)
    }

    func resolveRunNowProposal(
        definitionID: String,
        expectedRevision: Int
    ) throws -> ScheduledTaskHostToolProposalResolution {
        let definition = try resolveTargetDefinition(id: definitionID, expectedRevision: expectedRevision)
        guard definition.decodedDestination != nil else {
            throw ScheduledTaskHostToolServiceError.invalidStoredSchedule
        }
        guard !definition.runs.contains(where: { !$0.hasKnownTerminalStatus }) else {
            throw ScheduledTaskHostToolServiceError.runNowBlockedByActiveRun
        }
        guard definition.targetWaitStartedAt == nil else {
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
    ) throws -> ScheduledTaskHostToolEditedDraft {
        guard let destination = definition.decodedDestination else {
            throw ScheduledTaskHostToolServiceError.invalidStoredSchedule
        }
        let timeZoneIdentifier = currentTimeZone().identifier
        let recurrence = try editedRecurrence(
            of: definition,
            changes: changes,
            timeZoneIdentifier: timeZoneIdentifier
        )
        let context = ScheduledTaskHostToolEditContext(
            definition: definition,
            changes: changes,
            storedDestination: destination,
            recurrence: recurrence,
            timeZoneIdentifier: timeZoneIdentifier,
            settings: ScheduledTaskProposalAgentSettings(definition: definition)
        )
        if case .existingThread(let targetConversationID) = changes.placement {
            return try editedExistingThreadDraft(context, targetConversationID: targetConversationID)
        }
        return try editedNewThreadDraft(context)
    }

    func editedExistingThreadDraft(
        _ context: ScheduledTaskHostToolEditContext,
        targetConversationID: String
    ) throws -> ScheduledTaskHostToolEditedDraft {
        let target = try resolveTargetThread(conversationID: targetConversationID)
        return ScheduledTaskHostToolEditedDraft(
            draft: existingThreadDraft(
                title: context.title,
                prompt: context.prompt,
                recurrence: context.recurrence,
                targetConversationID: target.conversationID,
                settings: context.settings
            ),
            // The target thread owns its workspace, so the definition keeps no Project.
            project: nil,
            placementSummary: Self.placementSummary(
                for: context.changes.placement,
                targetThread: target.thread,
                project: nil,
                grantedRoots: []
            )
        )
    }

    func editedNewThreadDraft(
        _ context: ScheduledTaskHostToolEditContext
    ) throws -> ScheduledTaskHostToolEditedDraft {
        let definition = context.definition
        let placement = context.changes.placement
        // A placement that names a workspace is asking for a new-thread run; without one the
        // definition keeps whatever destination it already had.
        let destination: ScheduledTaskDestination = placement == nil ? context.storedDestination : .newThread
        let workspace = try resolvedWorkspace(
            requested: placement?.requestedWorkspace,
            inheritedKind: definition.workspaceKind,
            inheritedProject: try inheritedProject(of: definition, for: destination),
            inheritedGrantedRoots: try ScheduledTaskHostToolSupport.validatedStoredGrantedRoots(definition.grantedRoots)
        )
        let draft = ScheduledTaskProposalDefinitionDraft(
            title: context.title,
            prompt: context.prompt,
            destination: destination,
            targetConversationID: destination == .existingThread
                ? definition.targetThread?.soleMainConversation?.id
                : nil,
            recurrence: context.recurrence,
            timeZoneIdentifier: context.timeZoneIdentifier,
            providerID: context.settings.providerID,
            model: context.settings.model,
            effort: context.settings.effort,
            permissionMode: context.settings.permissionMode,
            workspaceKind: workspace.kind,
            workspaceStrategy: definition.workspaceStrategy,
            grantedRoots: workspace.grantedRoots,
            projectPath: workspace.project?.path
        )
        return ScheduledTaskHostToolEditedDraft(
            draft: draft,
            project: workspace.project,
            placementSummary: Self.placementSummary(
                for: placement,
                targetThread: nil,
                project: workspace.project,
                grantedRoots: workspace.grantedRoots
            )
        )
    }

    /// The requested recurrence, or the stored one, revalidated against the current time zone.
    func editedRecurrence(
        of definition: ScheduledTask,
        changes: ScheduledTaskProposalEditChanges,
        timeZoneIdentifier: String
    ) throws -> ScheduledTaskRecurrence {
        guard let storedRecurrence = definition.recurrence else {
            throw ScheduledTaskHostToolServiceError.invalidStoredSchedule
        }
        let recurrence = changes.schedule?.recurrence ?? storedRecurrence
        do {
            try recurrenceCalculator.validate(recurrence, timeZoneIdentifier: timeZoneIdentifier)
        } catch {
            throw ScheduledTaskHostToolServiceError.invalidStoredSchedule
        }
        return recurrence
    }

    /// The definition's own Project, revalidated, when the edited destination still uses one.
    func inheritedProject(
        of definition: ScheduledTask,
        for destination: ScheduledTaskDestination
    ) throws -> Project? {
        guard destination == .newThread, definition.workspaceKind == .project else {
            return nil
        }
        guard let project = definition.project else {
            throw ScheduledTaskHostToolServiceError.workspaceUnavailable
        }
        try ScheduledTaskHostToolSupport.validateStoredCanonicalPath(project.path)
        return project
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
        edited: ScheduledTaskHostToolEditedDraft? = nil
    ) -> ScheduledTaskHostToolProposalResolution {
        // An action without a draft leaves the definition's Project alone; a drafted edit may have
        // named a different one, and the proposal must trust the Project its draft actually names.
        let project = edited == nil ? definition.project : edited?.project
        return ScheduledTaskHostToolProposalResolution(
            targetDefinitionID: definition.id,
            expectedDefinitionRevision: definition.revision,
            targetTitleSnapshot: definition.title,
            targetScheduleSummarySnapshot: ScheduledTaskHostToolSupport.scheduleSummary(
                for: definition,
                timeZoneIdentifier: currentTimeZone().identifier
            ),
            definitionDraft: edited?.draft,
            project: project,
            placementSummary: edited?.placementSummary
        )
    }

    /// Scheduling's source check: the shared host-tool resolution, plus the automated-run
    /// gating that only scheduling needs.
    func resolveSource(
        context: AgentCLIKit.AgentHostToolCallContext
    ) throws -> ScheduledTaskHostToolSource {
        let source: HostToolCallSource
        do {
            source = try HostToolSourceResolver.resolveSource(context: context, in: modelContext)
        } catch HostToolSourceError.sourceProviderMismatch {
            throw ScheduledTaskHostToolServiceError.sourceProviderMismatch
        } catch {
            throw ScheduledTaskHostToolServiceError.sourceConversationUnavailable
        }
        if let scheduledRun = source.thread.scheduledTaskRun,
           !scheduledRun.hasKnownTerminalStatus {
            throw ScheduledTaskHostToolServiceError.automatedRunCannotSchedule
        }
        if source.thread.hasBlockingScheduledTaskRunAttachment {
            throw ScheduledTaskHostToolServiceError.automatedRunCannotSchedule
        }
        return source
    }
}
