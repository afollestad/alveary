import Foundation
import SwiftData
import SwiftUI

extension SidebarViewModel {
    func orderedProjects(from projects: [Project]) -> [Project] {
        regularProjects(from: projects) + projects.filter(\.isPinned).sorted(by: comparePinnedProjects)
    }

    func regularProjects(from projects: [Project]) -> [Project] {
        SidebarOrderNormalization.regularProjects(from: projects)
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
        try SidebarOrderNormalization.normalize(
            in: modelContext,
            excludingProjectIDs: excludingProjectIDs,
            excludingThreadIDs: excludingThreadIDs
        )
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
        try SidebarOrderNormalization.allProjects(in: modelContext)
    }

    func allThreads() throws -> [AgentThread] {
        try SidebarOrderNormalization.allThreads(in: modelContext)
    }
}

private extension SidebarViewModel {
    func sidebarPinnedItems(projects: [Project], threads: [AgentThread]) -> [SidebarPinnedItem] {
        SidebarOrderNormalization.sidebarPinnedItems(projects: projects, threads: threads)
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
