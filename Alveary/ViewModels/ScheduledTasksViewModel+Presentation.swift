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
        let projectName = definition.project?.name
        let workspaceSummary: String
        switch definition.workspaceKind {
        case .privateWorkspace:
            let grantCount = definition.grantedRoots.count
            if grantCount == 0 {
                workspaceSummary = "Private workspace"
            } else {
                let grantLabel = grantCount == 1 ? "folder grant" : "folder grants"
                workspaceSummary = "Private workspace + \(grantCount) \(grantLabel)"
            }
        case .project:
            let strategy = definition.workspaceStrategy == .worktree ? "worktree" : "local checkout"
            workspaceSummary = "\(projectName ?? "Missing project") · \(strategy)"
        }

        return ScheduledTaskRowPresentation(
            id: definition.id,
            revision: definition.revision,
            title: definition.title,
            prompt: definition.prompt,
            state: definition.state,
            recurrence: definition.recurrence,
            timeZoneIdentifier: definition.timeZoneIdentifier,
            providerID: definition.providerID,
            workspaceSummary: workspaceSummary,
            nextOccurrenceAt: definition.nextOccurrenceAt,
            pauseReason: definition.pauseReason,
            lastError: definition.lastError,
            hasActiveRun: definition.runs.contains { !$0.hasKnownTerminalStatus },
            modifiedAt: definition.modifiedAt
        )
    }
}
