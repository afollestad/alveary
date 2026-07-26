import SwiftData
import SwiftUI

extension SidebarView {
    func selectionAfterDeletingThread(_ thread: AgentThread) -> SidebarItem? {
        // Fallback follows placement, not mode: a Task placed in a project prefers its project
        // siblings, and only a projectless Task falls back within the `Tasks` section.
        if thread.effectiveMode == .task, thread.project == nil {
            return selectionAfterDeletingTask(thread)
        }

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
}
