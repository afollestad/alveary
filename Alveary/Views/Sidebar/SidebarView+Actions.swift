import Foundation
import SwiftData

func threadDeleteConfirmationMessage(for thread: AgentThread) -> String {
    if thread.effectiveMode == .task {
        return "This permanently deletes \"\(thread.displayName())\" and removes its Alveary-owned workspace or worktree. "
            + "Granted folders are never deleted."
    }
    return "This permanently deletes \"\(thread.displayName())\" from Alveary and removes its worktree and branch if present."
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
        let isTask = thread.effectiveMode == .task
        let replacementItem = isTask ? selectionAfterDeletingThread(thread) : thread.project.map(SidebarItem.project)
        let routing = beginThreadRemovalRouting(thread, replacementItem: replacementItem)

        do {
            try await viewModel.archiveThread(thread) { [self] in
                self.completeThreadRemovalRouting(routing)
            }
            completeThreadRemovalRouting(routing)
        } catch let error as SidebarViewModelError where error.isPostCommitCleanupFailure {
            completeThreadRemovalRouting(routing)
            viewModel.presentSidebarError(error)
        } catch {
            switch viewModel.threadLifecyclePersistenceState(id: routing.threadID) {
            case .active:
                restoreThreadRemovalRoutingIfUnchanged(routing)
            case .archived, .missing:
                completeThreadRemovalRouting(routing)
            }
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
           thread.effectiveMode == .project,
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

        let routing = beginThreadRemovalRouting(
            thread,
            replacementItem: selectionAfterDeletingThread(thread),
            clearsConversationSelection: true
        )

        // Let SwiftUI unmount the selected conversation while its SwiftData models are
        // still live. A later observable-state mutation can otherwise re-evaluate the
        // stale view after the deletion commit and trap on a persisted-property read.
        if routing.selectionWasTarget {
            await Task.yield()
        }

        do {
            try await viewModel.deleteThread(thread) { [self] in
                self.completeThreadRemovalRouting(routing)
            }
            completeThreadRemovalRouting(routing)
        } catch let error as SidebarViewModelError where error.isPostCommitCleanupFailure {
            completeThreadRemovalRouting(routing)
            viewModel.presentSidebarError(error)
        } catch {
            switch viewModel.threadLifecyclePersistenceState(id: routing.threadID) {
            case .active, .archived:
                restoreThreadRemovalRoutingIfUnchanged(routing)
            case .missing:
                completeThreadRemovalRouting(routing)
            }
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
        if thread.effectiveMode == .task {
            return selectionAfterDeletingTask(thread)
        }

        if thread.isPinned && thread.project?.isPinned != true {
            let threads = pinnedThreads().filter { $0.effectiveMode == .project }
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

    func selectionAfterDeletingTask(_ task: AgentThread) -> SidebarItem? {
        let tasks = visibleTaskThreadsForSelectionFallback()
        guard let deletedIndex = tasks.firstIndex(where: { $0.persistentModelID == task.persistentModelID }) else {
            return nil
        }

        let nextIndex = deletedIndex + 1
        if tasks.indices.contains(nextIndex) {
            return .thread(tasks[nextIndex])
        }
        if deletedIndex > 0 {
            return .thread(tasks[deletedIndex - 1])
        }
        return nil
    }

    func visibleTaskThreadsForSelectionFallback() -> [AgentThread] {
        let pinnedTasks = pinnedItems().compactMap { item -> AgentThread? in
            guard case .thread(let thread) = item.kind, thread.effectiveMode == .task else {
                return nil
            }
            return thread
        }
        return pinnedTasks + activeTaskThreads()
    }

    func completeTaskRemovalFallbackIfNeeded(_ shouldComplete: Bool) {
        guard shouldComplete,
              appState.selectedSidebarItem == nil,
              appState.pendingCommand == nil else {
            return
        }
        if let task = visibleTaskThreadsForSelectionFallback().first {
            appState.selectedSidebarItem = .thread(task)
            appState.previousSelection = .threadId(task.persistentModelID)
        } else {
            appState.startNewThreadFlow(mode: .task)
        }
    }

    private func beginThreadRemovalRouting(
        _ thread: AgentThread,
        replacementItem: SidebarItem?,
        clearsConversationSelection: Bool = false
    ) -> ThreadRemovalRoutingContext {
        let threadID = thread.persistentModelID
        let previousSelectedItem = appState.selectedSidebarItem
        let previousBookmark = appState.previousSelection
        let previousSelectedConversationID = appState.selectedConversationIDs[threadID]
        let selectionWasTarget = sidebarSelectionToken(previousSelectedItem) == .thread(threadID)
        let bookmarkWasTarget = previousBookmark == .threadId(threadID)
        if selectionWasTarget {
            appState.selectedSidebarItem = replacementItem
        }
        if bookmarkWasTarget {
            appState.previousSelection = replacementItem.flatMap(AppState.SidebarBookmark.init)
        }
        if clearsConversationSelection {
            appState.selectedConversationIDs.removeValue(forKey: threadID)
        }
        return ThreadRemovalRoutingContext(
            threadID: threadID,
            isTask: thread.effectiveMode == .task,
            previousSelectedItem: previousSelectedItem,
            previousBookmark: previousBookmark,
            previousSelectedConversationID: previousSelectedConversationID,
            replacementItem: replacementItem,
            selectionWasTarget: selectionWasTarget,
            bookmarkWasTarget: bookmarkWasTarget,
            clearsConversationSelection: clearsConversationSelection,
            optimisticSelectionToken: sidebarSelectionToken(appState.selectedSidebarItem),
            optimisticBookmark: appState.previousSelection,
            optimisticPendingCommand: appState.pendingCommand
        )
    }

    private func completeThreadRemovalRouting(_ routing: ThreadRemovalRoutingContext) {
        let selectionReturnedToTarget = sidebarSelectionToken(appState.selectedSidebarItem) == .thread(routing.threadID)
        if selectionReturnedToTarget {
            appState.selectedSidebarItem = routing.replacementItem
        }
        if appState.previousSelection == .threadId(routing.threadID) {
            appState.previousSelection = routing.replacementItem.flatMap(AppState.SidebarBookmark.init)
        }
        completeTaskRemovalFallbackIfNeeded(
            routing.isTask &&
                routing.replacementItem == nil &&
                (routing.selectionWasTarget || selectionReturnedToTarget)
        )
    }

    private func restoreThreadRemovalRoutingIfUnchanged(_ routing: ThreadRemovalRoutingContext) {
        guard appState.pendingCommand == routing.optimisticPendingCommand else {
            return
        }
        let selectionRoutingIsUnchanged = sidebarSelectionToken(appState.selectedSidebarItem) == routing.optimisticSelectionToken
        if routing.selectionWasTarget, selectionRoutingIsUnchanged {
            appState.selectedSidebarItem = routing.previousSelectedItem
        }
        if routing.bookmarkWasTarget,
           selectionRoutingIsUnchanged,
           appState.previousSelection == routing.optimisticBookmark {
            appState.previousSelection = routing.previousBookmark
        }
        if routing.clearsConversationSelection,
           appState.selectedConversationIDs[routing.threadID] == nil,
           let previousSelectedConversationID = routing.previousSelectedConversationID {
            appState.selectedConversationIDs[routing.threadID] = previousSelectedConversationID
        }
    }

    func selectedSidebarItemBelongs(toProjectPath projectPath: String) -> Bool {
        sidebarItem(
            appState.selectedSidebarItem,
            belongsToProjectPath: projectPath,
            resolvedThreadProjectPath: { threadID in
                guard let thread = uiModelContext.resolveThread(id: threadID),
                      thread.effectiveMode == .project else {
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
        let threads = ((try? uiModelContext.fetch(descriptor)) ?? []).filter { $0.effectiveMode == .project }
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
        guard selectedThread.effectiveMode == .project else {
            return false
        }
        return selectedThread.project?.path == projectPath ||
            resolvedThreadProjectPath(selectedThread.persistentModelID) == projectPath
    default:
        return false
    }
}

enum SidebarSelectionToken: Equatable {
    case none
    case skills
    case mcp
    case project(PersistentIdentifier)
    case thread(PersistentIdentifier)
    case settings
}

private struct ThreadRemovalRoutingContext {
    let threadID: PersistentIdentifier
    let isTask: Bool
    let previousSelectedItem: SidebarItem?
    let previousBookmark: AppState.SidebarBookmark?
    let previousSelectedConversationID: PersistentIdentifier?
    let replacementItem: SidebarItem?
    let selectionWasTarget: Bool
    let bookmarkWasTarget: Bool
    let clearsConversationSelection: Bool
    let optimisticSelectionToken: SidebarSelectionToken
    let optimisticBookmark: AppState.SidebarBookmark?
    let optimisticPendingCommand: AppState.CommandRequest?
}

func sidebarSelectionToken(_ item: SidebarItem?) -> SidebarSelectionToken {
    switch item {
    case nil:
        .none
    case .skills:
        .skills
    case .mcp:
        .mcp
    case .project(let project):
        .project(project.persistentModelID)
    case .thread(let thread):
        .thread(thread.persistentModelID)
    case .settings:
        .settings
    }
}
