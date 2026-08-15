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
        let threads = try orderingThreads(in: modelContext).filter { !excludingThreadIDs.contains($0.persistentModelID) }
        var didChange = clearInvalidProjectOrders(projects)
        didChange = clearInvalidPinnedThreadOrders(threads) || didChange
        didChange = clearInvalidCustomSectionMemberships(threads) || didChange
        didChange = renumberRegularProjects(projects) || didChange
        didChange = renumberPinnedItems(projects: projects, threads: threads) || didChange
        return didChange
    }

    static func allProjects(in modelContext: ModelContext) throws -> [Project] {
        try modelContext.fetch(FetchDescriptor<Project>())
    }

    /// Every thread sidebar ordering can read or rewrite: the unarchived population that pinned
    /// items and activity fallbacks are built from, plus any thread still carrying a
    /// `pinnedSortOrder` or a custom-section membership — archived included, so a stale order or
    /// membership is cleared wherever it hides. An unfiltered fetch here instead made every
    /// delete's synchronous commit scale with archived history.
    static func orderingThreads(in modelContext: ModelContext) throws -> [AgentThread] {
        try modelContext.fetch(FetchDescriptor<AgentThread>(predicate: #Predicate { thread in
            thread.archivedAt == nil || thread.pinnedSortOrder != nil || thread.customSection != nil
        }))
    }

    static func regularProjects(from projects: [Project]) -> [Project] {
        projects
            .filter { !$0.isPinned }
            .sorted(by: compareRegularProjects)
    }

    static func sidebarPinnedItems(projects: [Project], threads: [AgentThread]) -> [SidebarPinnedItem] {
        // One pass over the threads, and only when some pinned project still needs the legacy
        // activity fallback — matching `SidebarRenderSnapshot`, which skips the date once a manual
        // `pinnedSortOrder` exists because the comparator discards it. The per-project filter this
        // replaces walked every thread per pinned project, with a `project` fault per element.
        let needsActivityFallback = projects.contains { $0.isPinned && $0.pinnedSortOrder == nil }
        var latestActivityByProjectPath: [String: Date] = [:]
        if needsActivityFallback {
            for thread in threads where thread.archivedAt == nil && !thread.isDraft {
                guard let path = thread.project?.path, let modifiedAt = thread.modifiedAt else {
                    continue
                }
                latestActivityByProjectPath[path] = max(latestActivityByProjectPath[path] ?? modifiedAt, modifiedAt)
            }
        }
        let projectItems = projects
            .filter(\.isPinned)
            .map { project in
                SidebarPinnedItem(
                    project: project,
                    activityDate: project.pinnedSortOrder == nil ? latestActivityByProjectPath[project.path] : nil
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

    /// Custom-section membership is an overlay on the `Tasks` population, so a thread that is
    /// project-placed or Project-mode cannot carry it; archived threads keep theirs so a restore
    /// returns them to their section. Deliberately no seeding here — inserting rows would change
    /// what existing lifecycle call sites commit.
    private static func clearInvalidCustomSectionMemberships(_ threads: [AgentThread]) -> Bool {
        var didChange = false
        for thread in threads where thread.customSection != nil {
            if thread.project != nil || thread.effectiveMode == .project {
                thread.customSection = nil
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

}
