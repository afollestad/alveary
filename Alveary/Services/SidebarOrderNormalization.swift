import Foundation
import SwiftData

/// Sidebar ordering rules expressed over a `ModelContext` instead of a view model.
///
/// `SidebarViewModel` is per-window, but thread lifecycle mutations also run app-scoped —
/// `ThreadLifecycleService` archives threads for surfaces with no sidebar at all — and those
/// mutations must renumber the same pinned/regular orders inside the same save. Keeping the rules
/// here means both callers share one implementation; `SidebarViewModel` delegates.
@MainActor
enum SidebarOrderNormalization {
    /// Clears orders that no longer apply and renumbers the rest densely, reporting whether
    /// anything changed. Excluded IDs are rows the caller is about to remove, so their orders
    /// must not influence the renumbering.
    @discardableResult
    static func normalize(
        in modelContext: ModelContext,
        excludingProjectIDs: Set<PersistentIdentifier> = [],
        excludingThreadIDs: Set<PersistentIdentifier> = []
    ) throws -> Bool {
        let projects = try allProjects(in: modelContext).filter { !excludingProjectIDs.contains($0.persistentModelID) }
        let threads = try allThreads(in: modelContext).filter { !excludingThreadIDs.contains($0.persistentModelID) }
        var didChange = clearInvalidProjectOrders(projects)
        didChange = clearInvalidPinnedThreadOrders(threads) || didChange
        didChange = renumberRegularProjects(projects) || didChange
        didChange = renumberPinnedItems(projects: projects, threads: threads) || didChange
        return didChange
    }

    static func allProjects(in modelContext: ModelContext) throws -> [Project] {
        try modelContext.fetch(FetchDescriptor<Project>())
    }

    static func allThreads(in modelContext: ModelContext) throws -> [AgentThread] {
        try modelContext.fetch(FetchDescriptor<AgentThread>())
    }

    static func regularProjects(from projects: [Project]) -> [Project] {
        projects
            .filter { !$0.isPinned }
            .sorted(by: compareRegularProjects)
    }

    static func sidebarPinnedItems(projects: [Project], threads: [AgentThread]) -> [SidebarPinnedItem] {
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

    static func isVisiblePinnedSidebarThread(_ thread: AgentThread) -> Bool {
        guard thread.archivedAt == nil,
              !thread.isDraft,
              thread.isPinned else {
            return false
        }
        // A pinned thread is absorbed by a pinned project regardless of mode; a projectless Task
        // has nothing to be absorbed by.
        switch thread.effectiveMode {
        case .project:
            return thread.project != nil && thread.project?.isPinned != true
        case .task:
            return thread.project?.isPinned != true
        }
    }

    static func compareRegularProjects(_ lhs: Project, _ rhs: Project) -> Bool {
        compareOptionalOrder(
            lhs.sidebarSortOrder,
            rhs.sidebarSortOrder,
            fallback: { compareProjectFallback(lhs, rhs) }
        )
    }

    static func comparePinnedProjects(_ lhs: Project, _ rhs: Project) -> Bool {
        compareOptionalOrder(
            lhs.pinnedSortOrder,
            rhs.pinnedSortOrder,
            fallback: { compareProjectFallback(lhs, rhs) }
        )
    }

    static func compareProjectFallback(_ lhs: Project, _ rhs: Project) -> Bool {
        let nameComparison = lhs.name.localizedCaseInsensitiveCompare(rhs.name)
        if nameComparison != .orderedSame {
            return nameComparison == .orderedAscending
        }
        return lhs.path < rhs.path
    }

    static func comparePinnedThreads(_ lhs: AgentThread, _ rhs: AgentThread) -> Bool {
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

    private static func compareOptionalOrder(
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

    private static func clearInvalidProjectOrders(_ projects: [Project]) -> Bool {
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

    private static func clearInvalidPinnedThreadOrders(_ threads: [AgentThread]) -> Bool {
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

    private static func renumberRegularProjects(_ projects: [Project]) -> Bool {
        var didChange = false
        for (index, project) in regularProjects(from: projects).enumerated() where project.sidebarSortOrder != index {
            project.sidebarSortOrder = index
            didChange = true
        }
        return didChange
    }

    private static func renumberPinnedItems(projects: [Project], threads: [AgentThread]) -> Bool {
        var didChange = false
        let items = sidebarPinnedItems(projects: projects, threads: threads)
        for (index, item) in SidebarPinnedItemOrdering.sorted(items).enumerated() {
            didChange = assignPinnedSortOrder(index, to: item) || didChange
        }
        return didChange
    }

    private static func assignPinnedSortOrder(_ index: Int, to item: SidebarPinnedItem) -> Bool {
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

    private static func latestUnarchivedThreadModifiedAt(for project: Project, threads: [AgentThread]) -> Date? {
        // Mode-agnostic, matching `SidebarRenderSnapshot`: any thread in the project is a child.
        threads
            .filter { $0.archivedAt == nil && !$0.isDraft && $0.project?.path == project.path }
            .compactMap(\.modifiedAt)
            .max()
    }
}
