import Foundation
import SwiftData

/// Drop validation and the pin/order application that `commitSidebarDrop` runs once a
/// target is chosen.
extension SidebarViewModel {
    /// A Tasks-section drop is an unpin, not a reorder: the Tasks list is activity-sorted,
    /// so the drop delegates to `setThreadPinned`, which owns the scheduled-attachment guard.
    func commitSidebarDropToTasks(dragItem: SidebarDragItem) throws -> Bool {
        switch dragItem {
        case .pinnedTask(let id):
            guard let thread = modelContext.resolveThread(id: id),
                  thread.effectiveMode == .task,
                  isVisiblePinnedSidebarThread(thread) else {
                return false
            }
            try setThreadPinned(thread, isPinned: false)
            // A pinned Task can still belong to a project; unpinning alone would drop it straight
            // back into that project rather than into `Tasks`, which is where it was dropped.
            _ = try detachTaskFromProject(id)
            return true
        case .unpinnedTask(let id):
            return try detachTaskFromProject(id)
        case .project, .pinnedThread, .projectThread:
            return false
        }
    }

    /// An `.into` drop on the dragged thread's own project is an unpin, not a reparent: the thread
    /// already belongs there, so the drop delegates to `setThreadPinned` — which owns the
    /// scheduled-attachment guard — and leaves the project relationship untouched. Every other
    /// `.into` drop is the async access-grant flow and returns `false` here.
    func commitSidebarDropToOwningProject(dragItem: SidebarDragItem, target: SidebarDropTarget) throws -> Bool {
        guard case .project(let projectID) = target.item else {
            return false
        }
        let mode: AgentThreadMode
        let threadID: PersistentIdentifier
        switch dragItem {
        case .pinnedThread(let id):
            (mode, threadID) = (.project, id)
        case .pinnedTask(let id):
            (mode, threadID) = (.task, id)
        case .project, .unpinnedTask, .projectThread:
            return false
        }
        guard let thread = modelContext.resolveThread(id: threadID),
              thread.effectiveMode == mode,
              isVisiblePinnedSidebarThread(thread),
              thread.project?.persistentModelID == projectID else {
            return false
        }
        try setThreadPinned(thread, isPinned: false)
        return true
    }

    func sidebarDropRequestIsValid(dragItem: SidebarDragItem, target: SidebarDropTarget) -> Bool {
        guard sidebarDragSourceExists(dragItem) else {
            return false
        }
        if dragItem.isConversation, target.section != .pinned {
            return false
        }

        // A thread nested under a pinned project cannot hold a standalone pin: the pinned project
        // absorbs its children, so normalization would clear it in the same commit.
        switch dragItem {
        case .unpinnedTask(let id), .projectThread(let id):
            if target.section == .pinned,
               modelContext.resolveThread(id: id)?.project?.isPinned == true {
                return false
            }
        case .project, .pinnedThread, .pinnedTask:
            break
        }

        guard let targetItem = target.item else {
            return true
        }
        if case .project = dragItem, targetItem.isConversation {
            return false
        }
        return sidebarTargetExists(targetItem, in: target.section)
    }

    func sidebarDragSourceExists(_ item: SidebarDragItem) -> Bool {
        switch item {
        case .project(let id):
            return modelContext.resolveProject(id: id) != nil
        case .pinnedThread(let id):
            guard let thread = modelContext.resolveThread(id: id) else {
                return false
            }
            return thread.effectiveMode == .project && isVisiblePinnedSidebarThread(thread)
        case .pinnedTask(let id):
            guard let thread = modelContext.resolveThread(id: id) else {
                return false
            }
            return thread.effectiveMode == .task && isVisiblePinnedSidebarThread(thread)
        case .unpinnedTask(let id):
            guard let thread = modelContext.resolveThread(id: id) else {
                return false
            }
            return thread.effectiveMode == .task && !thread.isPinned && !thread.isDraft && thread.archivedAt == nil
        case .projectThread(let id):
            guard let thread = modelContext.resolveThread(id: id) else {
                return false
            }
            return thread.effectiveMode == .project && !thread.isPinned && !thread.isDraft && thread.archivedAt == nil
        }
    }

    func sidebarTargetExists(_ item: SidebarDragItem, in section: SidebarDropSection) -> Bool {
        switch item {
        case .project(let id):
            guard let project = modelContext.resolveProject(id: id) else {
                return false
            }
            return project.isPinned == (section == .pinned)
        case .pinnedThread(let id):
            guard section == .pinned,
                  let thread = modelContext.resolveThread(id: id) else {
                return false
            }
            return thread.effectiveMode == .project && isVisiblePinnedSidebarThread(thread)
        case .pinnedTask(let id):
            guard section == .pinned,
                  let thread = modelContext.resolveThread(id: id) else {
                return false
            }
            return thread.effectiveMode == .task && isVisiblePinnedSidebarThread(thread)
        case .unpinnedTask, .projectThread:
            return false
        }
    }

    func removeChildrenAbsorbedByPinnedProject(
        dragItem: SidebarDragItem,
        target: SidebarDropTarget,
        from order: inout SidebarDragOrder
    ) throws {
        guard target.section == .pinned,
              case .project(let projectID) = dragItem,
              let project = modelContext.resolveProject(id: projectID) else {
            return
        }
        let childIDs = Set(
            try unarchivedThreadsForOrdering(projectPath: project.path)
                .filter { $0.isPinned && $0.project?.isPinned != true }
                .map(\.persistentModelID)
        )
        order.pinnedItems.removeAll { item in
            guard case .pinnedThread(let threadID) = item else {
                return false
            }
            return childIDs.contains(threadID)
        }
    }

    func applySidebarDragOrder(_ order: SidebarDragOrder) throws {
        let pinnedProjectIDs = projectIDs(in: order.pinnedItems)
        let regularProjectIDs = projectIDs(in: order.regularProjects)
        let projects = try allProjects()
        let allProjectIDs = Set(projects.map(\.persistentModelID))
        guard pinnedProjectIDs.isDisjoint(with: regularProjectIDs),
              pinnedProjectIDs.union(regularProjectIDs) == allProjectIDs else {
            throw SidebarViewModelError.projectMissing
        }

        for project in projects where project.isPinned != pinnedProjectIDs.contains(project.persistentModelID) {
            try clearUnarchivedChildPins(project)
        }
        try applyPinnedDragItems(order.pinnedItems)
        try applyRegularDragProjects(order.regularProjects)
    }

    func projectIDs(in items: [SidebarDragItem]) -> Set<PersistentIdentifier> {
        Set(items.compactMap { item in
            guard case .project(let id) = item else {
                return nil
            }
            return id
        })
    }

    func applyPinnedDragItems(_ items: [SidebarDragItem]) throws {
        for (index, item) in items.enumerated() {
            switch item {
            case .project(let id):
                let project = try resolveProjectForOrdering(id)
                project.isPinned = true
                project.sidebarSortOrder = nil
                project.pinnedSortOrder = index
            case .pinnedThread(let id):
                let thread = try resolvePinnedThreadForOrdering(id, mode: .project)
                thread.isPinned = true
                thread.pinnedSortOrder = index
            case .pinnedTask(let id):
                let thread = try resolvePinnedThreadForOrdering(id, mode: .task)
                thread.isPinned = true
                thread.pinnedSortOrder = index
            case .unpinnedTask(let id):
                let thread = try resolveUnpinnedTaskForOrdering(id)
                thread.isPinned = true
                thread.pinnedSortOrder = index
            case .projectThread(let id):
                let thread = try resolveUnpinnedProjectThreadForOrdering(id)
                thread.isPinned = true
                thread.pinnedSortOrder = index
            }
        }
    }

    func applyRegularDragProjects(_ items: [SidebarDragItem]) throws {
        for (index, item) in items.enumerated() {
            guard case .project(let id) = item else {
                throw SidebarViewModelError.projectMissing
            }
            let project = try resolveProjectForOrdering(id)
            project.isPinned = false
            project.pinnedSortOrder = nil
            project.sidebarSortOrder = index
        }
    }

    func clearUnarchivedChildPins(_ project: Project) throws {
        for child in try unarchivedThreadsForOrdering(projectPath: project.path)
        where child.isPinned || child.pinnedSortOrder != nil {
            try requireNoScheduledTaskAttachment(child)
            child.isPinned = false
            child.pinnedSortOrder = nil
        }
    }

    func resolveProjectForOrdering(_ id: PersistentIdentifier) throws -> Project {
        guard let project = modelContext.resolveProject(id: id) else {
            throw SidebarViewModelError.projectMissing
        }
        return project
    }

    func resolvePinnedThreadForOrdering(_ id: PersistentIdentifier, mode: AgentThreadMode) throws -> AgentThread {
        guard let thread = modelContext.resolveThread(id: id),
              thread.effectiveMode == mode,
              isVisiblePinnedSidebarThread(thread) else {
            throw SidebarViewModelError.threadMissing
        }
        return thread
    }

    func resolveUnpinnedTaskForOrdering(_ id: PersistentIdentifier) throws -> AgentThread {
        guard let thread = modelContext.resolveThread(id: id),
              thread.effectiveMode == .task,
              !thread.isPinned,
              !thread.isDraft,
              thread.archivedAt == nil else {
            throw SidebarViewModelError.threadMissing
        }
        return thread
    }

    func resolveUnpinnedProjectThreadForOrdering(_ id: PersistentIdentifier) throws -> AgentThread {
        guard let thread = modelContext.resolveThread(id: id),
              thread.effectiveMode == .project,
              !thread.isPinned,
              !thread.isDraft,
              thread.archivedAt == nil,
              // A pinned parent absorbs its children, so the standalone pin being created here
              // would be invisible and normalization would clear it in the same commit.
              thread.project?.isPinned != true else {
            throw SidebarViewModelError.threadMissing
        }
        return thread
    }
}
