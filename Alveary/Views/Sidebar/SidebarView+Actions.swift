import Foundation
import SwiftData

func threadDeleteConfirmationMessage(for thread: AgentThread) -> String {
    "This permanently deletes \"\(thread.displayName())\" from Alveary and removes its worktree and branch if present."
}

extension SidebarView {
    func createThread(in project: Project) async {
        do {
            let createdThread = try await viewModel.openDraftThread(project: project)
            guard let resolvedThread = uiModelContext.resolveThread(id: createdThread.persistentModelID) else {
                return
            }

            if let projectPath = resolvedThread.project?.path {
                expandedProjects.insert(projectPath)
            }
            appState.requestComposerFocus()
            appState.selectedSidebarItem = .thread(resolvedThread)
        } catch {
            viewModel.presentSidebarError(error)
        }
    }

    func forkThread(_ thread: AgentThread, mode: SidebarThreadForkMode) async {
        let sourceProjectPath = thread.project?.path

        do {
            let forkedThread: AgentThread
            switch mode {
            case .local:
                forkedThread = try await viewModel.forkThreadIntoLocal(thread)
            case .worktree:
                forkedThread = try await viewModel.forkThreadIntoWorktree(thread)
            }

            guard let resolvedThread = uiModelContext.resolveThread(id: forkedThread.persistentModelID) else {
                return
            }

            if let projectPath = resolvedThread.project?.path ?? sourceProjectPath {
                expandedProjects.insert(projectPath)
            }
            appState.requestComposerFocus()
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
        } catch let error as SidebarViewModelError where error.isPostCommitCleanupFailure {
            viewModel.presentSidebarError(error)
        } catch {
            appState.selectedSidebarItem = previousSelectedItem
            appState.previousSelection = previousBookmark
            viewModel.presentSidebarError(error)
        }
    }

    func renameThread(_ thread: AgentThread, to newName: String) {
        guard let dbThread = uiModelContext.resolveThread(id: thread.persistentModelID) else {
            viewModel.presentSidebarError(SidebarThreadActionError.renameTargetMissing)
            return
        }

        let previousDisplayName = dbThread.displayName()

        dbThread.name = newName
        dbThread.hasCustomName = true

        if let mainConversation = mainConversation(in: dbThread),
           mainConversation.shouldFollowThreadRename(previousThreadDisplayName: previousDisplayName) {
            mainConversation.title = mainConversation.persistedTitle(from: newName)
        }

        do {
            try uiModelContext.save()
        } catch {
            viewModel.presentSidebarError(SidebarThreadActionError.renameFailed(error))
        }
    }

    func setThreadPinned(_ thread: AgentThread, isPinned: Bool) {
        let threadID = thread.persistentModelID
        let sourceProjectPath = thread.project?.path
        let shouldRevealUnpinnedSelection: Bool
        if case .thread(let selectedThread) = appState.selectedSidebarItem,
           selectedThread.persistentModelID == threadID,
           !isPinned {
            shouldRevealUnpinnedSelection = true
        } else {
            shouldRevealUnpinnedSelection = false
        }

        do {
            try viewModel.setThreadPinned(thread, isPinned: isPinned)
            if shouldRevealUnpinnedSelection,
               let projectPath = uiModelContext.resolveThread(id: threadID)?.project?.path ?? sourceProjectPath {
                expandedProjects.insert(projectPath)
            }
        } catch {
            viewModel.presentSidebarError(error)
        }
    }

    func setProjectPinned(_ project: Project, isPinned: Bool) {
        let projectPath = project.path

        do {
            try viewModel.setProjectPinned(project, isPinned: isPinned)
            expandedProjects = expandedProjectsPreservingVisibleSelection(afterMovingProject: projectPath)
        } catch {
            viewModel.presentSidebarError(error)
        }
    }

    func confirmDeleteThread(_ thread: AgentThread) async {
        pendingDeleteThread = nil

        let threadID = thread.persistentModelID
        let previousSelectedItem = appState.selectedSidebarItem
        let previousBookmark = appState.previousSelection
        let replacementItem = selectionAfterDeletingThread(thread)

        if case .thread(let selectedThread) = appState.selectedSidebarItem,
           selectedThread.persistentModelID == threadID {
            appState.selectedSidebarItem = replacementItem
        }

        if case .threadId(let bookmarkedID) = appState.previousSelection,
           bookmarkedID == threadID {
            appState.previousSelection = replacementItem.flatMap(AppState.SidebarBookmark.init)
        }

        do {
            try await viewModel.deleteThread(thread)
            appState.selectedConversationIDs.removeValue(forKey: threadID)
        } catch let error as SidebarViewModelError where error.isPostCommitCleanupFailure {
            appState.selectedConversationIDs.removeValue(forKey: threadID)
            viewModel.presentSidebarError(error)
        } catch {
            appState.selectedSidebarItem = previousSelectedItem
            appState.previousSelection = previousBookmark
            viewModel.presentSidebarError(error)
        }
    }

    func confirmDeleteProject(_ project: Project) async {
        pendingDeleteProject = nil

        let projectPath = project.path
        let previousSelectedItem = appState.selectedSidebarItem
        let previousBookmark = appState.previousSelection
        let previousConversationIDs = appState.selectedConversationIDs

        let threadIDs = liveThreadIDs(in: project)

        switch appState.selectedSidebarItem {
        case .project(let selectedProject) where selectedProject.path == projectPath:
            appState.selectedSidebarItem = nil
        case .thread(let selectedThread) where threadIDs.contains(selectedThread.persistentModelID):
            appState.selectedSidebarItem = nil
        default:
            break
        }

        switch appState.previousSelection {
        case .projectPath(let selectedProjectPath) where selectedProjectPath == projectPath:
            appState.previousSelection = nil
        case .threadId(let threadID) where threadIDs.contains(threadID):
            appState.previousSelection = nil
        default:
            break
        }

        for threadID in threadIDs {
            appState.selectedConversationIDs.removeValue(forKey: threadID)
        }

        do {
            try await viewModel.deleteProject(project)
            expandedProjects.remove(projectPath)
        } catch let error as SidebarViewModelError where error.isPostCommitCleanupFailure {
            expandedProjects.remove(projectPath)
            viewModel.presentSidebarError(error)
        } catch {
            appState.selectedSidebarItem = previousSelectedItem
            appState.previousSelection = previousBookmark
            appState.selectedConversationIDs = previousConversationIDs
            viewModel.presentSidebarError(error)
        }
    }

    func selectionAfterDeletingThread(_ thread: AgentThread) -> SidebarItem? {
        if thread.isPinned && thread.project?.isPinned != true {
            let threads = pinnedThreads()
            if let deletedIndex = threads.firstIndex(where: { $0.persistentModelID == thread.persistentModelID }) {
                if deletedIndex > 0 {
                    return .thread(threads[deletedIndex - 1])
                }

                let nextIndex = deletedIndex + 1
                if threads.indices.contains(nextIndex) {
                    return .thread(threads[nextIndex])
                }
            }

            return thread.project.map(SidebarItem.project)
        }

        guard let project = thread.project else {
            return nil
        }

        let threads = activeThreads(for: project)
        guard let deletedIndex = threads.firstIndex(where: { $0.persistentModelID == thread.persistentModelID }) else {
            return .project(project)
        }

        if deletedIndex > 0 {
            return .thread(threads[deletedIndex - 1])
        }

        let nextIndex = deletedIndex + 1
        if threads.indices.contains(nextIndex) {
            return .thread(threads[nextIndex])
        }

        return .project(project)
    }

    func selectedSidebarItemBelongs(toProjectPath projectPath: String) -> Bool {
        sidebarItem(
            appState.selectedSidebarItem,
            belongsToProjectPath: projectPath,
            resolvedThreadProjectPath: { threadID in
                guard let thread = uiModelContext.resolveThread(id: threadID),
                      thread.mode == .project else {
                    return nil
                }
                return thread.project?.path
            }
        )
    }

    func expandedProjectsPreservingVisibleSelection(afterMovingProject projectPath: String) -> Set<String> {
        var nextExpandedProjects = expandedProjects
        if selectedSidebarItemBelongs(toProjectPath: projectPath) {
            nextExpandedProjects.insert(projectPath)
        }
        return nextExpandedProjects
    }

    func liveThreadIDs(in project: Project) -> Set<PersistentIdentifier> {
        let projectPath = project.path
        let descriptor = FetchDescriptor<AgentThread>(
            predicate: #Predicate { thread in
                thread.project?.path == projectPath
            }
        )
        let threads = ((try? uiModelContext.fetch(descriptor)) ?? []).filter { $0.mode == .project }
        return Set(threads.map(\.persistentModelID))
    }

    func mainConversation(in thread: AgentThread) -> Conversation? {
        let threadID = thread.persistentModelID
        let descriptor = FetchDescriptor<Conversation>(
            predicate: #Predicate { conversation in
                conversation.thread?.persistentModelID == threadID && conversation.isMain
            }
        )
        return try? uiModelContext.fetch(descriptor).first
    }
}

func sidebarItem(
    _ item: SidebarItem?,
    belongsToProjectPath projectPath: String,
    resolvedThreadProjectPath: (PersistentIdentifier) -> String?
) -> Bool {
    switch item {
    case .project(let selectedProject):
        return selectedProject.path == projectPath
    case .thread(let selectedThread):
        guard selectedThread.mode == .project else {
            return false
        }
        return selectedThread.project?.path == projectPath ||
            resolvedThreadProjectPath(selectedThread.persistentModelID) == projectPath
    default:
        return false
    }
}
