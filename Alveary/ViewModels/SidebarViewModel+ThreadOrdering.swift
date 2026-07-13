import Foundation
import SwiftData

struct SidebarPinnedItem: Identifiable {
    enum Kind {
        case project(Project)
        case thread(AgentThread)
    }

    let kind: Kind
    let legacyActivityDate: Date?

    init(project: Project, activityDate: Date? = nil) {
        kind = .project(project)
        legacyActivityDate = activityDate
    }

    init(thread: AgentThread) {
        kind = .thread(thread)
        legacyActivityDate = thread.modifiedAt
    }

    var id: String {
        switch kind {
        case .project(let project):
            "project:\(project.path)"
        case .thread(let thread):
            "thread:\(String(describing: thread.persistentModelID))"
        }
    }

    var sidebarItem: SidebarItem {
        switch kind {
        case .project(let project):
            .project(project)
        case .thread(let thread):
            .thread(thread)
        }
    }

    var dragItem: SidebarDragItem {
        switch kind {
        case .project(let project):
            .project(project.persistentModelID)
        case .thread(let thread):
            .pinnedThread(thread.persistentModelID)
        }
    }

    var pinnedSortOrder: Int? {
        switch kind {
        case .project(let project):
            project.pinnedSortOrder
        case .thread(let thread):
            thread.pinnedSortOrder
        }
    }

    var displayName: String {
        switch kind {
        case .project(let project):
            project.name
        case .thread(let thread):
            thread.displayName()
        }
    }

    var stableID: String {
        switch kind {
        case .project(let project):
            project.path
        case .thread(let thread):
            String(describing: thread.persistentModelID)
        }
    }
}

enum SidebarPinnedItemOrdering {
    @MainActor
    static func sorted(_ items: [SidebarPinnedItem]) -> [SidebarPinnedItem] {
        items.sorted(by: compare)
    }

    @MainActor
    static func compare(_ lhs: SidebarPinnedItem, _ rhs: SidebarPinnedItem) -> Bool {
        switch (lhs.pinnedSortOrder, rhs.pinnedSortOrder) {
        case (.some(let lhsOrder), .some(let rhsOrder)) where lhsOrder != rhsOrder:
            return lhsOrder < rhsOrder
        case (.some, .none):
            return true
        case (.none, .some):
            return false
        default:
            break
        }

        if lhs.pinnedSortOrder == nil, rhs.pinnedSortOrder == nil {
            return legacyCompare(lhs, rhs)
        }
        return fallbackCompare(lhs, rhs)
    }

    @MainActor
    static func legacySorted(_ items: [SidebarPinnedItem]) -> [SidebarPinnedItem] {
        items.sorted(by: legacyCompare)
    }

    @MainActor
    private static func legacyCompare(_ lhs: SidebarPinnedItem, _ rhs: SidebarPinnedItem) -> Bool {
        switch (lhs.legacyActivityDate, rhs.legacyActivityDate) {
        case (.some(let lhsActivity), .some(let rhsActivity)) where lhsActivity != rhsActivity:
            return lhsActivity > rhsActivity
        case (.some, .none):
            return true
        case (.none, .some):
            return false
        default:
            return fallbackCompare(lhs, rhs)
        }
    }

    @MainActor
    private static func fallbackCompare(_ lhs: SidebarPinnedItem, _ rhs: SidebarPinnedItem) -> Bool {
        let nameComparison = lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName)
        if nameComparison != .orderedSame {
            return nameComparison == .orderedAscending
        }
        return lhs.stableID < rhs.stableID
    }
}

extension SidebarViewModel {
    func installThreadActivityObserver() {
        threadActivityObserver = NotificationCenter.default.addObserver(
            forName: .threadActivityChanged,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            if notification.userInfo?[ThreadActivityNotificationKey.isBackfill] as? Bool == true {
                Task { @MainActor [weak self] in
                    self?.statusVersion += 1
                }
                return
            }
            guard notification.userInfo?[ThreadActivityNotificationKey.didChangeOrder] as? Bool == true else {
                return
            }
            Task { @MainActor [weak self] in
                self?.refreshThreadOrder(animated: true)
            }
        }
    }

    func pinnedThreads() -> [AgentThread] {
        fetchedVisiblePinnedThreads()
            .filter { $0.mode == .project && $0.project != nil && $0.project?.isPinned != true }
            .sorted(by: comparePinnedThreads)
    }

    func pinnedItems(projects: [Project]) -> [SidebarPinnedItem] {
        let pinnedProjects = projects.filter(\.isPinned)
        let legacyActivityThreads = pinnedProjects.contains { $0.pinnedSortOrder == nil }
            ? fetchedVisibleThreadsForLegacyActivity()
            : []
        let projectItems = pinnedProjects
            .map { project in
                SidebarPinnedItem(
                    project: project,
                    activityDate: project.pinnedSortOrder == nil
                        ? latestVisibleThreadModifiedAt(for: project, threads: legacyActivityThreads)
                        : nil
                )
            }
        let threadItems = fetchedVisiblePinnedThreads()
            .filter { $0.mode == .project && $0.project != nil && $0.project?.isPinned != true }
            .map(SidebarPinnedItem.init(thread:))
        return SidebarPinnedItemOrdering.sorted(projectItems + threadItems)
    }

    func activeThreads(for project: Project) -> [AgentThread] {
        let projectPath = project.path
        let descriptor = FetchDescriptor<AgentThread>(
            predicate: #Predicate { thread in
                thread.archivedAt == nil && thread.isDraft == false && thread.project?.path == projectPath
            }
        )

        let threads = ((try? modelContext.fetch(descriptor)) ?? []).filter { $0.mode == .project }
        return AgentThreadOrdering.sorted(threads.filter { project.isPinned || !$0.isPinned })
    }

    func hasAnyActiveThreads(for project: Project) -> Bool {
        let projectPath = project.path
        let descriptor = FetchDescriptor<AgentThread>(
            predicate: #Predicate { thread in
                thread.archivedAt == nil && thread.isDraft == false && thread.project?.path == projectPath
            }
        )
        return ((try? modelContext.fetch(descriptor)) ?? []).contains { $0.mode == .project }
    }

    func setProjectPinned(_ project: Project, isPinned: Bool) throws {
        guard modelContext.resolveProject(id: project.persistentModelID) != nil else {
            throw SidebarViewModelError.projectMissing
        }
        try flushPendingSidebarPinChanges()

        do {
            var didChange = try normalizeSidebarOrdering()
            let dbProject = try resolveProjectForPinning(project.persistentModelID)
            let wasPinned = dbProject.isPinned
            let projectPath = dbProject.path

            if isPinned, !wasPinned {
                for child in try unarchivedThreadsForOrdering(projectPath: projectPath)
                where child.isPinned || child.pinnedSortOrder != nil {
                    child.isPinned = false
                    child.pinnedSortOrder = nil
                    didChange = true
                }
                didChange = try normalizeSidebarOrdering() || didChange
                let appendOrder = try currentPinnedItemCount()
                dbProject.isPinned = true
                dbProject.sidebarSortOrder = nil
                dbProject.pinnedSortOrder = appendOrder
                didChange = true
            } else if !isPinned, wasPinned {
                let appendOrder = try currentRegularProjectCount()
                dbProject.isPinned = false
                dbProject.pinnedSortOrder = nil
                dbProject.sidebarSortOrder = appendOrder
                didChange = true
            }

            if wasPinned || isPinned {
                for child in try unarchivedThreadsForOrdering(projectPath: projectPath)
                where child.isPinned || child.pinnedSortOrder != nil {
                    child.isPinned = false
                    child.pinnedSortOrder = nil
                    didChange = true
                }
            }

            didChange = try normalizeSidebarOrdering() || didChange
            guard didChange else {
                return
            }
            try persistSidebarOrdering()
            refreshThreadOrder(animated: true)
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    func setThreadPinned(_ thread: AgentThread, isPinned: Bool) throws {
        guard let currentThread = modelContext.resolveThread(id: thread.persistentModelID),
              currentThread.archivedAt == nil,
              !currentThread.isDraft else {
            throw SidebarViewModelError.threadMissing
        }
        if isPinned, currentThread.project?.isPinned == true {
            return
        }
        try flushPendingSidebarPinChanges()

        do {
            var didChange = try normalizeSidebarOrdering()
            guard let dbThread = modelContext.resolveThread(id: thread.persistentModelID),
                  dbThread.archivedAt == nil,
                  !dbThread.isDraft else {
                throw SidebarViewModelError.threadMissing
            }
            let wasPinned = dbThread.isPinned
            if isPinned, !wasPinned {
                let appendOrder = try currentPinnedItemCount()
                dbThread.isPinned = true
                dbThread.pinnedSortOrder = appendOrder
                didChange = true
            } else if !isPinned, wasPinned {
                dbThread.isPinned = false
                dbThread.pinnedSortOrder = nil
                didChange = true
            }

            didChange = try normalizeSidebarOrdering() || didChange
            guard didChange else {
                return
            }
            try persistSidebarOrdering()
            refreshThreadOrder(animated: true)
        } catch {
            modelContext.rollback()
            throw error
        }
    }
}

private extension SidebarViewModel {
    func latestVisibleThreadModifiedAt(for project: Project, threads: [AgentThread]) -> Date? {
        threads
            .filter { $0.mode == .project && $0.project?.path == project.path }
            .compactMap(\.modifiedAt)
            .max()
    }

    func fetchedVisiblePinnedThreads() -> [AgentThread] {
        let descriptor = FetchDescriptor<AgentThread>(
            predicate: #Predicate { thread in
                thread.archivedAt == nil && thread.isPinned == true && thread.isDraft == false
            }
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    func fetchedVisibleThreadsForLegacyActivity() -> [AgentThread] {
        let descriptor = FetchDescriptor<AgentThread>(
            predicate: #Predicate { thread in
                thread.archivedAt == nil && thread.isDraft == false
            }
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    func flushPendingSidebarPinChanges() throws {
        guard modelContext.hasChanges else {
            return
        }
        try persistPendingSidebarChanges()
    }

    func resolveProjectForPinning(_ id: PersistentIdentifier) throws -> Project {
        guard let project = modelContext.resolveProject(id: id) else {
            throw SidebarViewModelError.projectMissing
        }
        return project
    }
}
