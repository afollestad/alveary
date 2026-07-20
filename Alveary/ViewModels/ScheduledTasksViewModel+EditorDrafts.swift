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
        let calendar = Calendar.current

        return ScheduledTaskEditorDraft(
            id: UUID(),
            definitionID: nil,
            expectedRevision: nil,
            title: "",
            prompt: "",
            recurrenceKind: .daily,
            onceOccurrenceAt: suggestedOccurrence,
            intervalAnchorAt: startOfMinute(actionDate),
            intervalMinutes: 60,
            wallClockHour: calendar.component(.hour, from: suggestedOccurrence),
            wallClockMinute: calendar.component(.minute, from: suggestedOccurrence),
            selectedWeekdays: Set(ScheduledTaskRecurrence.standardWeekdays),
            weeklyWeekday: calendar.component(.weekday, from: suggestedOccurrence),
            monthlyDay: calendar.component(.day, from: suggestedOccurrence),
            timeZoneIdentifier: TimeZone.current.identifier,
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
            recurrenceKind: recurrence?.kind ?? .once,
            onceOccurrenceAt: recurrenceFields?.onceOccurrenceAt ?? fallbackDate,
            intervalAnchorAt: recurrenceFields?.intervalAnchorAt ?? fallbackIntervalAnchor,
            intervalMinutes: definition.intervalMinutes ?? 60,
            wallClockHour: definition.wallClockHour ?? 9,
            wallClockMinute: definition.wallClockMinute ?? 0,
            selectedWeekdays: Set(recurrence?.selectedWeekdays ?? ScheduledTaskRecurrence.standardWeekdays),
            weeklyWeekday: definition.weeklyWeekday ?? 2,
            monthlyDay: definition.monthlyDay ?? 1,
            timeZoneIdentifier: definition.timeZoneIdentifier,
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
            recurrenceKind: recurrence.kind,
            onceOccurrenceAt: recurrenceFields.onceOccurrenceAt,
            intervalAnchorAt: recurrenceFields.intervalAnchorAt,
            intervalMinutes: recurrenceFields.intervalMinutes,
            wallClockHour: recurrenceFields.wallClockHour,
            wallClockMinute: recurrenceFields.wallClockMinute,
            selectedWeekdays: recurrenceFields.selectedWeekdays,
            weeklyWeekday: recurrenceFields.weeklyWeekday,
            monthlyDay: recurrenceFields.monthlyDay,
            timeZoneIdentifier: definitionDraft.timeZoneIdentifier,
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

private func startOfMinute(_ date: Date) -> Date {
    Calendar.current.dateInterval(of: .minute, for: date)?.start ?? date
}
