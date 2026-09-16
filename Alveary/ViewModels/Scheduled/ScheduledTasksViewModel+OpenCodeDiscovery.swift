import AgentCLIKit
import Foundation

/// Editor catalogs follow the execution directory without changing global defaults or a draft's saved selections.
extension ScheduledTasksViewModel {
    func openCodeDiscoveryDirectory(for draft: ScheduledTaskEditorDraft) -> String? {
        if draft.destination == .existingThread, let id = draft.targetConversationID {
            return modelContext.resolveConversation(conversationID: id)?.thread?.primaryWorkingDirectory
        }
        if draft.destination == .reusedThread,
           let id = draft.definitionID, let definition = modelContext.resolveScheduledTask(id: id),
           let thread = definition.reusedThread, thread.isHealthyReusedScheduledTaskTarget,
           draft.harnessID == definition.harnessID,
           draft.workspaceKind == definition.workspaceKind,
           draft.workspaceStrategy == definition.workspaceStrategy,
           draft.projectID == definition.project?.id,
           draft.workspaceSnapshot == definition.workspaceSnapshot,
           draft.projectPath == definition.workspaceSnapshot?.primarySource?.path,
           draft.grantedRoots == definition.workspaceSnapshot?.grants.map(\.path) {
            return thread.primaryWorkingDirectory
        }
        // Before a worktree or private workspace is materialized, only its source directory is known.
        guard draft.workspaceKind == .project else { return nil }
        return draft.workspaceSnapshot?.primarySource?.path ?? draft.projectPath
    }

    func refreshOpenCodeEditorCatalog(directory: String?) async {
        guard let directory, let harnessDiscovery else { return }
        let generation = UUID()
        openCodeEditorCatalogs[directory] = .loading(generation)
        let statuses = await harnessDiscovery.harnessStatuses(projectURL: URL(fileURLWithPath: directory, isDirectory: true))
        guard !Task.isCancelled, case .loading(let latest) = openCodeEditorCatalogs[directory], latest == generation else { return }
        openCodeEditorCatalogs[directory] = .loaded(statuses[.opencode])
    }

    func isOpenCodeEditorCatalogPending(for draft: ScheduledTaskEditorDraft) -> Bool {
        guard harnessDiscovery != nil, let directory = openCodeDiscoveryDirectory(for: draft) else { return isLoadingHarnesses }
        if case .loaded = openCodeEditorCatalogs[directory] { return false }
        return true
    }

    func editorHarnessIDs(for draft: ScheduledTaskEditorDraft) -> [String] {
        guard harnessDiscovery != nil, let directory = openCodeDiscoveryDirectory(for: draft) else {
            return harnessIDs(including: draft.harnessID)
        }
        var values = availableHarnessIDs.filter { $0 != "opencode" }
        if case .loaded(let status) = openCodeEditorCatalogs[directory], let status,
           ThreadDefaultResolver.isReadyHarness(harnessID: "opencode", settings: settingsService.current, status: status) {
            values.append("opencode")
        }
        if !draft.harnessID.isEmpty, !values.contains(draft.harnessID) { values.append(draft.harnessID) }
        return values
    }
}

/// Each directory owns its response generation, so switching projects or reopening an editor cannot publish another catalog over it.
enum ScheduledTaskOpenCodeCatalog {
    case loading(UUID)
    case loaded(AgentHarnessStatus?)
}
