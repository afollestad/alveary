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
        return try modelContext.fetch(descriptor).filter { $0.mode == .project }
    }

    func compareRegularProjects(_ lhs: Project, _ rhs: Project) -> Bool {
        compareOptionalOrder(
            lhs.sidebarSortOrder,
            rhs.sidebarSortOrder,
            fallback: { compareProjectFallback(lhs, rhs) }
        )
    }

    func comparePinnedProjects(_ lhs: Project, _ rhs: Project) -> Bool {
        compareOptionalOrder(
            lhs.pinnedSortOrder,
            rhs.pinnedSortOrder,
            fallback: { compareProjectFallback(lhs, rhs) }
        )
    }

    func compareProjectFallback(_ lhs: Project, _ rhs: Project) -> Bool {
        let nameComparison = lhs.name.localizedCaseInsensitiveCompare(rhs.name)
        if nameComparison != .orderedSame {
            return nameComparison == .orderedAscending
        }
        return lhs.path < rhs.path
    }

    func comparePinnedThreads(_ lhs: AgentThread, _ rhs: AgentThread) -> Bool {
        compareOptionalOrder(
            lhs.pinnedSortOrder,
            rhs.pinnedSortOrder,
            fallback: {
                switch (lhs.modifiedAt, rhs.modifiedAt) {
                case (.some(let lhsActivity), .some(let rhsActivity)) where lhsActivity != rhsActivity:
                    return lhsActivity > rhsActivity
                case (.some, .none):
                    return true
                case (.none, .some):
                    return false
                default:
                    break
                }
                let nameComparison = lhs.displayName().localizedCaseInsensitiveCompare(rhs.displayName())
                if nameComparison != .orderedSame {
                    return nameComparison == .orderedAscending
                }
                return String(describing: lhs.persistentModelID) < String(describing: rhs.persistentModelID)
            }
        )
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
            return
        }

        withAnimation(.easeInOut(duration: 0.15)) {
            threadOrderVersion += 1
        }
    }
}

private extension SidebarViewModel {
    func allProjects() throws -> [Project] {
        try modelContext.fetch(FetchDescriptor<Project>())
    }

    func allThreads() throws -> [AgentThread] {
        try modelContext.fetch(FetchDescriptor<AgentThread>())
    }

    func compareOptionalOrder(
        _ lhsOrder: Int?,
        _ rhsOrder: Int?,
        fallback: () -> Bool
    ) -> Bool {
        switch (lhsOrder, rhsOrder) {
        case (.some(let lhs), .some(let rhs)) where lhs != rhs:
            return lhs < rhs
        case (.some, .none):
            return true
        case (.none, .some):
            return false
        default:
            return fallback()
        }
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
            if isVisibleStandalonePinnedThread(thread) {
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
            .filter(isVisibleStandalonePinnedThread)
            .map(SidebarPinnedItem.init(thread:))
        return projectItems + threadItems
    }

    func latestUnarchivedThreadModifiedAt(for project: Project, threads: [AgentThread]) -> Date? {
        threads
            .filter { $0.mode == .project && $0.archivedAt == nil && !$0.isDraft && $0.project?.path == project.path }
            .compactMap(\.modifiedAt)
            .max()
    }

    func isVisibleStandalonePinnedThread(_ thread: AgentThread) -> Bool {
        thread.archivedAt == nil &&
            !thread.isDraft &&
            thread.isPinned &&
            thread.mode == .project &&
            thread.project != nil &&
            thread.project?.isPinned != true
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

    func sidebarDropRequestIsValid(dragItem: SidebarDragItem, target: SidebarDropTarget) -> Bool {
        guard sidebarDragSourceExists(dragItem) else {
            return false
        }
        if case .pinnedThread = dragItem, target.section != .pinned {
            return false
        }

        guard let targetItem = target.item else {
            return true
        }
        if case .project = dragItem, case .pinnedThread = targetItem {
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
            return isVisibleStandalonePinnedThread(thread)
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
            return isVisibleStandalonePinnedThread(thread)
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
                let thread = try resolvePinnedThreadForOrdering(id)
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

    func resolvePinnedThreadForOrdering(_ id: PersistentIdentifier) throws -> AgentThread {
        guard let thread = modelContext.resolveThread(id: id),
              isVisibleStandalonePinnedThread(thread) else {
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
