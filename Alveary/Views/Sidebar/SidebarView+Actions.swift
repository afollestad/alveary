import SwiftData

extension SidebarView {
    func createThread(in project: Project) async {
        do {
            let createdThread = try await viewModel.createThread(project: project)
            guard let resolvedThread = resolveThread(id: createdThread.persistentModelID) else {
                return
            }

            expandedProjects.insert(project.path)
            appState.selectedSidebarItem = .thread(resolvedThread)
        } catch {
            viewModel.presentSidebarError(error)
        }
    }

    func archive(_ thread: AgentThread) async {
        let previousSelectedItem = appState.selectedSidebarItem
        let previousBookmark = appState.previousSelection

        if case .thread(let selectedThread) = appState.selectedSidebarItem,
           selectedThread.persistentModelID == thread.persistentModelID,
           let project = thread.project {
            appState.selectedSidebarItem = .project(project)
        }

        if case .threadId(let bookmarkedID) = appState.previousSelection,
           bookmarkedID == thread.persistentModelID,
           let project = thread.project {
            appState.previousSelection = .projectPath(project.path)
        }

        do {
            try await viewModel.archiveThread(thread)
        } catch {
            appState.selectedSidebarItem = previousSelectedItem
            appState.previousSelection = previousBookmark
            viewModel.presentSidebarError(error)
        }
    }

    func renameThread(_ thread: AgentThread, to newName: String) {
        guard let dbThread = uiModelContext.model(for: thread.persistentModelID) as? AgentThread else {
            viewModel.presentSidebarError(SidebarThreadActionError.renameTargetMissing)
            return
        }

        dbThread.name = newName
        dbThread.hasCustomName = true

        if let mainConversation = dbThread.conversations.first(where: { $0.isMain }),
           mainConversation.customTitle == nil {
            mainConversation.title = newName
        }

        do {
            try uiModelContext.save()
        } catch {
            viewModel.presentSidebarError(SidebarThreadActionError.renameFailed(error))
        }
    }

    func confirmDeleteThread(_ thread: AgentThread) async {
        pendingDeleteThread = nil

        let previousSelectedItem = appState.selectedSidebarItem
        let previousBookmark = appState.previousSelection

        if case .thread(let selectedThread) = appState.selectedSidebarItem,
           selectedThread.persistentModelID == thread.persistentModelID {
            appState.selectedSidebarItem = thread.project.map(SidebarItem.project)
        }

        if case .threadId(let bookmarkedID) = appState.previousSelection,
           bookmarkedID == thread.persistentModelID,
           let project = thread.project {
            appState.previousSelection = .projectPath(project.path)
        }

        do {
            try await viewModel.deleteThread(thread)
            appState.selectedConversationIDs.removeValue(forKey: thread.persistentModelID)
        } catch {
            appState.selectedSidebarItem = previousSelectedItem
            appState.previousSelection = previousBookmark
            viewModel.presentSidebarError(error)
        }
    }

    func confirmDeleteProject(_ project: Project) async {
        pendingDeleteProject = nil

        let previousSelectedItem = appState.selectedSidebarItem
        let previousBookmark = appState.previousSelection
        let previousConversationIDs = appState.selectedConversationIDs
        let previousDiffAction = appState.pendingDiffAction

        let threadIDs = Set(project.threads.map(\.persistentModelID))
        let conversationIDs = Set(project.threads.flatMap(\.conversations).map(\.persistentModelID))

        switch appState.selectedSidebarItem {
        case .project(let selectedProject) where selectedProject.path == project.path:
            appState.selectedSidebarItem = nil
        case .thread(let selectedThread) where threadIDs.contains(selectedThread.persistentModelID):
            appState.selectedSidebarItem = nil
        default:
            break
        }

        switch appState.previousSelection {
        case .projectPath(let projectPath) where projectPath == project.path:
            appState.previousSelection = nil
        case .threadId(let threadID) where threadIDs.contains(threadID):
            appState.previousSelection = nil
        default:
            break
        }

        for threadID in threadIDs {
            appState.selectedConversationIDs.removeValue(forKey: threadID)
        }

        if let pendingDiffAction = appState.pendingDiffAction,
           conversationIDs.contains(pendingDiffAction.conversationID) {
            appState.pendingDiffAction = nil
        }

        do {
            try await viewModel.deleteProject(project)
            expandedProjects.remove(project.path)
        } catch {
            appState.selectedSidebarItem = previousSelectedItem
            appState.previousSelection = previousBookmark
            appState.selectedConversationIDs = previousConversationIDs
            appState.pendingDiffAction = previousDiffAction
            viewModel.presentSidebarError(error)
        }
    }

    func resolveThread(id: PersistentIdentifier) -> AgentThread? {
        uiModelContext.model(for: id) as? AgentThread
    }
}
