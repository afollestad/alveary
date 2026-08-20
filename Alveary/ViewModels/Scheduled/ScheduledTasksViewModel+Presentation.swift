import Foundation

extension ScheduledTaskPaneTarget {
    var defaultFocusRestorationID: String {
        switch self {
        case .create:
            "scheduled-new"
        case .edit(let definitionID):
            "scheduled-edit-\(definitionID)"
        case .proposal(let sourceConversationID):
            "scheduled-proposal-\(sourceConversationID)"
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
        let providerID: String
        let destination = definition.decodedDestination
        switch destination {
        case .some(.existingThread):
            workspaceSummary = "Existing thread · \(definition.targetThread?.displayName() ?? "Unavailable thread")"
            providerID = existingThreadProviderID(for: definition)
        case .some(.reusedThread):
            // The reuse thread is a venue the definition owns, so provider and settings still
            // come from the definition — unlike an existing target, whose thread is authoritative.
            providerID = definition.providerID
            // Once a run has minted the thread, later runs post into it and take their workspace
            // from it (`ScheduledTaskReusedThreadWorkspace`), so naming it is truer than
            // repeating definition columns those runs no longer read. Before the first run — and
            // after a self-heal drops the link — the workspace is still what gets created.
            workspaceSummary = """
                Same thread each time · \
                \(reusedThreadLink(for: definition)?.name ?? workspaceDetail(for: definition))
                """
        case .some(.newThreadPerRun):
            providerID = definition.providerID
            workspaceSummary = "New thread each time · \(workspaceDetail(for: definition))"
        case nil:
            providerID = definition.providerID
            workspaceSummary = "Unrecognized destination"
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
    /// The workspace half of a new-thread card summary, shared by both new-thread destinations
    /// so their prefixes ("Same thread each time" / "New thread each time") stay aligned with
    /// the picker.
    func workspaceDetail(for definition: ScheduledTask) -> String {
        switch definition.workspaceKind {
        case .privateWorkspace:
            let grantCount = definition.grantedRoots.count
            guard grantCount > 0 else {
                return "Private workspace"
            }
            let grantLabel = grantCount == 1 ? "folder grant" : "folder grants"
            return "Private workspace + \(grantCount) \(grantLabel)"
        case .project:
            let strategy = definition.workspaceStrategy == .worktree ? "worktree" : "local"
            return "\(definition.project?.name ?? "Missing project") · \(strategy)"
        }
    }

    func existingThreadProviderID(for definition: ScheduledTask) -> String {
        let mainConversations = definition.targetThread?.conversations.filter(\.isMain) ?? []
        guard mainConversations.count == 1 else { return definition.providerID }
        return mainConversations.first?.provider ?? definition.providerID
    }
}
