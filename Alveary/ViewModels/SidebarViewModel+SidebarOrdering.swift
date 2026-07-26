import Foundation
import SwiftData
import SwiftUI

extension SidebarViewModel {
    func orderedProjects(from projects: [Project]) -> [Project] {
        regularProjects(from: projects) + projects.filter(\.isPinned).sorted(by: comparePinnedProjects)
    }

    func regularProjects(from projects: [Project]) -> [Project] {
        projects
            .filter { !$0.isPinned }
            .sorted(by: compareRegularProjects)
    }

    func ensureSidebarOrderingInitialized() throws {
        try flushPendingChangesBeforeSidebarOrdering()
        do {
            let didChange = try normalizeSidebarOrdering()
            guard didChange else {
                return
            }
            try persistSidebarOrdering()
            refreshThreadOrder(animated: false)
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    func currentRegularProjectAppendOrder() throws -> Int {
        try currentRegularProjectCount()
    }

    @discardableResult
    func initializeSidebarOrderingForMutation() throws -> Bool {
        try normalizeSidebarOrdering()
    }

    @discardableResult
    func normalizeSidebarOrderingForLifecycle(
        excludingProjectIDs: Set<PersistentIdentifier> = [],
        excludingThreadIDs: Set<PersistentIdentifier> = []
    ) throws -> Bool {
        try normalizeSidebarOrdering(
            excludingProjectIDs: excludingProjectIDs,
            excludingThreadIDs: excludingThreadIDs
        )
    }

    func commitSidebarDrop(dragItem: SidebarDragItem, target: SidebarDropTarget) throws -> Bool {
        // Moving a Task into a project is async, so it routes through
        // `SidebarViewModel.moveTaskIntoProject` from the drag finalizer instead.
        guard target.placement != .into else {
            return false
        }
        if target.section == .tasks {
            return try commitSidebarDropToTasks(dragItem: dragItem)
        }
        guard sidebarDropRequestIsValid(dragItem: dragItem, target: target) else {
            return false
        }

        try flushPendingChangesBeforeSidebarOrdering()
        do {
            let didNormalize = try normalizeSidebarOrdering()
            guard sidebarDropRequestIsValid(dragItem: dragItem, target: target) else {
                modelContext.rollback()
                return false
            }

            var order = try sidebarDragOrder()
            try removeChildrenAbsorbedByPinnedProject(
                dragItem: dragItem,
                target: target,
                from: &order
            )
            guard let nextOrder = sidebarOrder(afterMoving: dragItem, to: target, in: order) else {
                modelContext.rollback()
                return false
            }

            guard nextOrder != order else {
                try saveSidebarNormalizationIfNeeded(didNormalize)
                return false
            }

            try applySidebarDragOrder(nextOrder)
            _ = try normalizeSidebarOrdering()
            try persistSidebarOrdering()
            refreshThreadOrder(animated: true)
            return true
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    func unarchivedThreadsForOrdering(projectPath: String) throws -> [AgentThread] {
        let descriptor = FetchDescriptor<AgentThread>(
            predicate: #Predicate { thread in
                thread.archivedAt == nil && thread.isDraft == false && thread.project?.path == projectPath
            }
        )
        // Mode-agnostic: a Task placed in this project is one of its children for pin purposes.
        return try modelContext.fetch(descriptor)
    }

    func currentRegularProjectCount() throws -> Int {
        try allProjects().filter { !$0.isPinned }.count
    }

    func currentPinnedItemCount() throws -> Int {
        let projects = try allProjects()
        let threads = try allThreads()
        return sidebarPinnedItems(projects: projects, threads: threads).count
    }

    @discardableResult
    func normalizeSidebarOrdering(
        excludingProjectIDs: Set<PersistentIdentifier> = [],
        excludingThreadIDs: Set<PersistentIdentifier> = []
    ) throws -> Bool {
        let projects = try allProjects().filter { !excludingProjectIDs.contains($0.persistentModelID) }
        let threads = try allThreads().filter { !excludingThreadIDs.contains($0.persistentModelID) }
        var didChange = clearInvalidProjectOrders(projects)
        didChange = clearInvalidPinnedThreadOrders(threads) || didChange
        didChange = renumberRegularProjects(projects) || didChange
        didChange = renumberPinnedItems(projects: projects, threads: threads) || didChange
        return didChange
    }

    func refreshThreadOrder(animated: Bool) {
        guard animated else {
            threadOrderVersion += 1
            NotificationCenter.default.post(name: .threadPresentationChanged, object: self)
            return
        }

        withAnimation(.easeInOut(duration: 0.15)) {
            threadOrderVersion += 1
        }
        NotificationCenter.default.post(name: .threadPresentationChanged, object: self)
    }
}

private extension SidebarViewModel {
    func allProjects() throws -> [Project] {
        try modelContext.fetch(FetchDescriptor<Project>())
    }

    func allThreads() throws -> [AgentThread] {
        try modelContext.fetch(FetchDescriptor<AgentThread>())
    }

    func clearInvalidProjectOrders(_ projects: [Project]) -> Bool {
        var didChange = false
        for project in projects {
            if project.isPinned {
                if project.sidebarSortOrder != nil {
                    project.sidebarSortOrder = nil
                    didChange = true
                }
                if let pinnedSortOrder = project.pinnedSortOrder, pinnedSortOrder < 0 {
                    project.pinnedSortOrder = nil
                    didChange = true
                }
            } else {
                if project.pinnedSortOrder != nil {
                    project.pinnedSortOrder = nil
                    didChange = true
                }
                if let sidebarSortOrder = project.sidebarSortOrder, sidebarSortOrder < 0 {
                    project.sidebarSortOrder = nil
                    didChange = true
                }
            }
        }
        return didChange
    }

    func clearInvalidPinnedThreadOrders(_ threads: [AgentThread]) -> Bool {
        var didChange = false
        for thread in threads {
            if isVisiblePinnedSidebarThread(thread) {
                if let pinnedSortOrder = thread.pinnedSortOrder, pinnedSortOrder < 0 {
                    thread.pinnedSortOrder = nil
                    didChange = true
                }
            } else if thread.pinnedSortOrder != nil {
                thread.pinnedSortOrder = nil
                didChange = true
            }
        }
        return didChange
    }

    func renumberRegularProjects(_ projects: [Project]) -> Bool {
        var didChange = false
        for (index, project) in regularProjects(from: projects).enumerated() where project.sidebarSortOrder != index {
            project.sidebarSortOrder = index
            didChange = true
        }
        return didChange
    }

    func renumberPinnedItems(projects: [Project], threads: [AgentThread]) -> Bool {
        var didChange = false
        let items = sidebarPinnedItems(projects: projects, threads: threads)
        for (index, item) in SidebarPinnedItemOrdering.sorted(items).enumerated() {
            didChange = assignPinnedSortOrder(index, to: item) || didChange
        }
        return didChange
    }

    func assignPinnedSortOrder(_ index: Int, to item: SidebarPinnedItem) -> Bool {
        switch item.kind {
        case .project(let project) where project.pinnedSortOrder != index:
            project.pinnedSortOrder = index
            return true
        case .thread(let thread) where thread.pinnedSortOrder != index:
            thread.pinnedSortOrder = index
            return true
        default:
            return false
        }
    }

    func sidebarPinnedItems(projects: [Project], threads: [AgentThread]) -> [SidebarPinnedItem] {
        let projectItems = projects
            .filter(\.isPinned)
            .map { project in
                SidebarPinnedItem(
                    project: project,
                    activityDate: latestUnarchivedThreadModifiedAt(for: project, threads: threads)
                )
            }
        let threadItems = threads
            .filter(isVisiblePinnedSidebarThread)
            .map(SidebarPinnedItem.init(thread:))
        return projectItems + threadItems
    }

    func latestUnarchivedThreadModifiedAt(for project: Project, threads: [AgentThread]) -> Date? {
        // Mode-agnostic, matching `SidebarRenderSnapshot`: any thread in the project is a child.
        threads
            .filter { $0.archivedAt == nil && !$0.isDraft && $0.project?.path == project.path }
            .compactMap(\.modifiedAt)
            .max()
    }

    func sidebarDragOrder() throws -> SidebarDragOrder {
        let projects = try allProjects()
        let threads = try allThreads()
        return SidebarDragOrder(
            pinnedItems: SidebarPinnedItemOrdering
                .sorted(sidebarPinnedItems(projects: projects, threads: threads))
                .map(\.dragItem),
            regularProjects: regularProjects(from: projects).map { .project($0.persistentModelID) }
        )
    }

    /// A Tasks-section drop is an unpin, not a reorder: the Tasks list is activity-sorted,
    /// so the drop delegates to `setThreadPinned`, which owns the scheduled-attachment guard.
    func commitSidebarDropToTasks(dragItem: SidebarDragItem) throws -> Bool {
        guard case .pinnedTask(let id) = dragItem,
              let thread = modelContext.resolveThread(id: id),
              thread.effectiveMode == .task,
              isVisiblePinnedSidebarThread(thread) else {
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
        case .unpinnedTask:
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

    func flushPendingChangesBeforeSidebarOrdering() throws {
        guard modelContext.hasChanges else {
            return
        }
        try persistPendingSidebarChanges()
    }

    func saveSidebarNormalizationIfNeeded(_ didNormalize: Bool) throws {
        guard didNormalize else {
            return
        }
        try persistSidebarOrdering()
        refreshThreadOrder(animated: false)
    }
}
