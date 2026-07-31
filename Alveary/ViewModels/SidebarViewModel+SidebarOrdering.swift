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
        // The one synchronous `.into` drop is a pinned thread unpinning onto its own project.
        // Moving a Task into another project is async, so it routes through
        // `SidebarViewModel.moveTaskIntoProject` from the drag finalizer instead.
        guard target.placement != .into else {
            return try commitSidebarDropToOwningProject(dragItem: dragItem, target: target)
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

    // Shared with `SidebarViewModel+SidebarOrderingCommit.swift`.
    func allProjects() throws -> [Project] {
        try modelContext.fetch(FetchDescriptor<Project>())
    }

    func allThreads() throws -> [AgentThread] {
        try modelContext.fetch(FetchDescriptor<AgentThread>())
    }
}

private extension SidebarViewModel {
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
