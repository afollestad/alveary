import Foundation

extension ScheduledTaskPaneTarget {
    var defaultFocusRestorationID: String {
        switch self {
        case .create:
            "scheduled-new"
        case .edit(let definitionID):
            "scheduled-edit-\(definitionID)"
        }
    }
}

extension ScheduledTasksViewModel {
    var activePaneSession: ScheduledTaskPaneSession? {
        activePaneTarget.flatMap { paneSessions[$0] }
    }

    var pendingEditorDraft: ScheduledTaskEditorDraft? {
        activePaneSession?.draft
    }

    var editorErrorMessage: String? {
        activePaneSession?.errorMessage
    }

    func loadForScreen() async {
        await load()
        normalizeActiveProviderDependentFields()
    }

    func makeRowPresentation(_ definition: ScheduledTask) -> ScheduledTaskRowPresentation {
        let workspaceSummary: String
        let targetThreadName: String?
        let providerID: String
        let destination = definition.decodedDestination
        switch destination {
        case .some(.existingThread):
            targetThreadName = definition.targetThread?.displayName()
            workspaceSummary = "Existing thread · \(targetThreadName ?? "Unavailable thread")"
            providerID = existingThreadProviderID(for: definition)
        case .some(.newThread):
            targetThreadName = nil
            providerID = definition.providerID
            switch definition.workspaceKind {
            case .privateWorkspace:
                let grantCount = definition.grantedRoots.count
                if grantCount == 0 {
                    workspaceSummary = "New Task · Private workspace"
                } else {
                    let grantLabel = grantCount == 1 ? "folder grant" : "folder grants"
                    workspaceSummary = "New Task · Private workspace + \(grantCount) \(grantLabel)"
                }
            case .project:
                let strategy = definition.workspaceStrategy == .worktree ? "worktree" : "local"
                workspaceSummary = "New thread · \(definition.project?.name ?? "Missing project") · \(strategy)"
            }
        case nil:
            targetThreadName = nil
            providerID = definition.providerID
            workspaceSummary = "Invalid destination"
        }

        return ScheduledTaskRowPresentation(
            id: definition.id,
            revision: definition.revision,
            title: definition.title,
            prompt: definition.prompt,
            state: definition.state,
            recurrence: definition.recurrence,
            timeZoneIdentifier: currentTimeZone().identifier,
            providerID: providerID,
            workspaceSummary: workspaceSummary,
            destination: destination,
            targetThreadName: targetThreadName,
            isWaitingForTarget: definition.targetWaitStartedAt != nil,
            nextOccurrenceAt: definition.nextOccurrenceAt,
            pauseReason: definition.pauseReason,
            lastError: definition.lastError,
            hasActiveRun: definition.runs.contains { !$0.hasKnownTerminalStatus },
            modifiedAt: definition.modifiedAt
        )
    }
}

private extension ScheduledTasksViewModel {
    func existingThreadProviderID(for definition: ScheduledTask) -> String {
        let mainConversations = definition.targetThread?.conversations.filter(\.isMain) ?? []
        guard mainConversations.count == 1 else { return definition.providerID }
        return mainConversations.first?.provider ?? definition.providerID
    }
}
