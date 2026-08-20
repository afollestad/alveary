import Foundation

extension ScheduledTasksViewModel {
    func makeNewDraft() -> ScheduledTaskEditorDraft {
        let settings = settingsService.current
        let resolution = providerResolution
        let providerID = resolution.providerID ?? settings.defaultProvider
        let modelOptions = modelOptions(for: providerID)
        let storedModel = resolution.providerID == providerID ? resolution.storedThreadModel : nil
        let modelSelection = AgentModelOptionSelection.pickerValue(in: modelOptions, matching: storedModel)
        let effort = AgentModelOptionSelection.normalizedEffort(
            resolution.effort,
            options: modelOptions,
            selectedModel: storedModel
        )
        let permissionModes = permissionModeOptions(for: providerID)
        let permissionMode = permissionModes.contains(where: { $0.value == resolution.permissionMode })
            ? resolution.permissionMode
            : permissionModes.first?.value ?? settings.permissionMode
        let actionDate = now()
        let suggestedOccurrence = actionDate.addingTimeInterval(60 * 60)
        var calendar = Calendar(identifier: .gregorian)
        let timeZone = currentTimeZone()
        calendar.timeZone = timeZone

        return ScheduledTaskEditorDraft(
            id: UUID(),
            definitionID: nil,
            expectedRevision: nil,
            title: "",
            prompt: "",
            destination: .reusedThread,
            reusedThread: nil,
            targetConversationID: nil,
            sectionID: nil,
            recurrenceKind: .daily,
            onceOccurrenceAt: suggestedOccurrence,
            intervalAnchorAt: startOfMinute(actionDate),
            intervalMinutes: 60,
            wallClockHour: calendar.component(.hour, from: suggestedOccurrence),
            wallClockMinute: calendar.component(.minute, from: suggestedOccurrence),
            selectedWeekdays: Set(ScheduledTaskRecurrence.standardWeekdays),
            weeklyWeekday: calendar.component(.weekday, from: suggestedOccurrence),
            monthlyDay: calendar.component(.day, from: suggestedOccurrence),
            timeZoneIdentifier: timeZone.identifier,
            providerID: providerID,
            modelSelection: modelSelection,
            effort: effort,
            permissionMode: permissionMode,
            workspaceKind: .privateWorkspace,
            workspaceStrategy: .worktree,
            projectPath: nil,
            grantedRoots: []
        )
    }

    func makeEditDraft(definitionID: String) -> ScheduledTaskEditorDraft? {
        guard let definition = modelContext.resolveScheduledTask(id: definitionID) else {
            errorMessage = ScheduledTaskMutationError.definitionNotFound.localizedDescription
            reload()
            return nil
        }
        let (destination, unresolvedDestinationRawValue) = editorDestinationSeed(for: definition)

        let recurrence = definition.recurrence
        let modelOptions = modelOptions(for: definition.providerID)
        let actionDate = now()
        let fallbackDate = actionDate.addingTimeInterval(60 * 60)
        let fallbackIntervalAnchor = startOfMinute(actionDate)
        let recurrenceFields = recurrence.map {
            ProposalDraftRecurrenceFields(
                recurrence: $0,
                fallbackOnceOccurrence: fallbackDate,
                fallbackIntervalAnchor: fallbackIntervalAnchor
            )
        }
        return ScheduledTaskEditorDraft(
            id: UUID(),
            definitionID: definition.id,
            expectedRevision: definition.revision,
            title: definition.title,
            prompt: definition.prompt,
            destination: destination,
            unresolvedDestinationRawValue: unresolvedDestinationRawValue,
            reusedThread: reusedThreadLink(for: definition),
            targetConversationID: definition.targetThread?.conversations.first(where: \.isMain)?.id,
            // Nullify already degraded a removed section, so the picker shows `Tasks` with no
            // fallback logic here.
            sectionID: definition.threadSection?.id,
            recurrenceKind: recurrence?.kind ?? .once,
            onceOccurrenceAt: recurrenceFields?.onceOccurrenceAt ?? fallbackDate,
            intervalAnchorAt: recurrenceFields?.intervalAnchorAt ?? fallbackIntervalAnchor,
            intervalMinutes: definition.intervalMinutes ?? 60,
            wallClockHour: definition.wallClockHour ?? 9,
            wallClockMinute: definition.wallClockMinute ?? 0,
            selectedWeekdays: Set(recurrence?.selectedWeekdays ?? ScheduledTaskRecurrence.standardWeekdays),
            weeklyWeekday: definition.weeklyWeekday ?? 2,
            monthlyDay: definition.monthlyDay ?? 1,
            timeZoneIdentifier: currentTimeZone().identifier,
            providerID: definition.providerID,
            modelSelection: AgentModelOptionSelection.pickerValue(in: modelOptions, matching: definition.model),
            effort: definition.effort,
            permissionMode: definition.permissionMode,
            workspaceKind: definition.workspaceKind,
            workspaceStrategy: definition.workspaceStrategy,
            projectPath: definition.project?.path,
            grantedRoots: definition.grantedRoots
        )
    }

    func makeProposalDraft(
        _ definitionDraft: ScheduledTaskProposalDefinitionDraft,
        definitionID: String?,
        expectedRevision: Int?
    ) -> ScheduledTaskEditorDraft {
        let modelOptions = modelOptions(for: definitionDraft.providerID)
        let recurrence = definitionDraft.recurrence
        let actionDate = now()
        let recurrenceFields = ProposalDraftRecurrenceFields(
            recurrence: recurrence,
            fallbackOnceOccurrence: actionDate.addingTimeInterval(60 * 60),
            fallbackIntervalAnchor: startOfMinute(actionDate)
        )
        return ScheduledTaskEditorDraft(
            id: UUID(),
            definitionID: definitionID,
            expectedRevision: expectedRevision,
            title: definitionDraft.title,
            prompt: definitionDraft.prompt,
            destination: definitionDraft.destination,
            // The payload cannot carry a reuse link — it is service-owned — so an edit target
            // reads it off the live definition and a create proposal has none yet.
            reusedThread: definitionID
                .flatMap { modelContext.resolveScheduledTask(id: $0) }
                .flatMap(reusedThreadLink(for:)),
            targetConversationID: definitionDraft.targetConversationID,
            // The proposal payload carries no section field, and absence must mean *preserve*:
            // confirming an unrelated "make it weekly" edit proposal must not silently reset the
            // schedule's section, so an edit target seeds from the live definition.
            sectionID: definitionID.flatMap { modelContext.resolveScheduledTask(id: $0)?.threadSection?.id },
            recurrenceKind: recurrence.kind,
            onceOccurrenceAt: recurrenceFields.onceOccurrenceAt,
            intervalAnchorAt: recurrenceFields.intervalAnchorAt,
            intervalMinutes: recurrenceFields.intervalMinutes,
            wallClockHour: recurrenceFields.wallClockHour,
            wallClockMinute: recurrenceFields.wallClockMinute,
            selectedWeekdays: recurrenceFields.selectedWeekdays,
            weeklyWeekday: recurrenceFields.weeklyWeekday,
            monthlyDay: recurrenceFields.monthlyDay,
            timeZoneIdentifier: currentTimeZone().identifier,
            providerID: definitionDraft.providerID,
            modelSelection: AgentModelOptionSelection.pickerValue(
                in: modelOptions,
                matching: definitionDraft.model
            ),
            effort: definitionDraft.effort,
            permissionMode: definitionDraft.permissionMode,
            workspaceKind: definitionDraft.workspaceKind,
            workspaceStrategy: definitionDraft.workspaceStrategy,
            projectPath: definitionDraft.projectPath,
            grantedRoots: definitionDraft.grantedRoots
        )
    }
}

extension ScheduledTasksViewModel {
    /// Interval anchors are minute-granular, so a schedule started mid-minute would
    /// otherwise fire at that offset forever. Shared with the suggestion drafts in
    /// `ScheduledTasksViewModel+Suggestions.swift`.
    func startOfMinute(_ date: Date) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = currentTimeZone()
        return calendar.dateInterval(of: .minute, for: date)?.start ?? date
    }
}

private extension ScheduledTasksViewModel {
    /// The destination an edit draft starts from, plus the persisted raw value when it did not
    /// decode.
    ///
    /// An undecodable destination seeds the editor rather than refusing to open it: refusing left
    /// the row with no surface at all — no pane, and Run now and Resume already fenced off — so
    /// deleting it was the only way out. Returned as a pair so the fallback and the flag marking
    /// it *as* a fallback cannot disagree; that flag is what makes
    /// `ScheduledTasksViewModel.makeDefinitionEdit` refuse the save until the user picks a
    /// destination, keeping the repair explicit.
    func editorDestinationSeed(for definition: ScheduledTask) -> (ScheduledTaskDestination, String?) {
        guard let destination = definition.decodedDestination else {
            return (.reusedThread, definition.destinationRawValue)
        }
        return (destination, nil)
    }
}
