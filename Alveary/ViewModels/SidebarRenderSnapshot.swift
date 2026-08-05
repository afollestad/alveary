import Foundation
import SwiftData

/// One render pass's view of the sidebar's projects and unarchived threads.
///
/// `SidebarView.body` builds this exactly once from observation-backed `@Query`
/// results so rows, placeholders, counts, keyboard traversal, and drag ordering
/// share a single in-memory grouping pass instead of issuing a `FetchDescriptor`
/// per project. It is ephemeral by contract: never store one in `@State`.
@MainActor
struct SidebarRenderSnapshot {
    /// Regular projects followed by pinned projects, matching `SidebarViewModel.orderedProjects(from:)`.
    let orderedProjects: [Project]
    let regularProjects: [Project]
    let pinnedItems: [SidebarPinnedItem]
    let activeTaskThreads: [AgentThread]
    let hasAnyActiveTaskThreads: Bool

    private let activeThreadsByProjectID: [PersistentIdentifier: [AgentThread]]
    private let projectIDsWithActiveThreads: Set<PersistentIdentifier>

    init(
        viewModel: SidebarViewModel,
        projects: [Project],
        unarchivedThreads: [AgentThread]
    ) {
        let regular = viewModel.regularProjects(from: projects)
        let pinnedProjects = projects.filter(\.isPinned)
        regularProjects = regular
        orderedProjects = regular + pinnedProjects.sorted(by: viewModel.comparePinnedProjects)

        // Provisional drafts never render as rows, counts, or pinned items.
        let visibleThreads = unarchivedThreads.filter { !$0.isDraft }
        let pinnedProjectIDs = Set(pinnedProjects.map(\.persistentModelID))

        var childThreads: [PersistentIdentifier: [AgentThread]] = [:]
        var projectIDsWithThreads: Set<PersistentIdentifier> = []
        var latestChildActivity: [PersistentIdentifier: Date] = [:]
        var unpinnedTasks: [AgentThread] = []
        var hasAnyTask = false

        for thread in visibleThreads {
            if thread.effectiveMode == .task {
                hasAnyTask = true
            }
            // A Task placed in a project renders as one of its children while staying a Task; a
            // projectless Task belongs to the `Tasks` section.
            guard let projectID = thread.project?.persistentModelID else {
                if thread.effectiveMode == .task, !thread.isPinned {
                    unpinnedTasks.append(thread)
                }
                continue
            }
            projectIDsWithThreads.insert(projectID)
            if let modifiedAt = thread.modifiedAt {
                latestChildActivity[projectID] = max(latestChildActivity[projectID] ?? modifiedAt, modifiedAt)
            }
            // Pinned children render standalone unless their project is itself pinned.
            if pinnedProjectIDs.contains(projectID) || !thread.isPinned {
                childThreads[projectID, default: []].append(thread)
            }
        }

        activeThreadsByProjectID = childThreads.mapValues(AgentThreadOrdering.sorted)
        projectIDsWithActiveThreads = projectIDsWithThreads
        activeTaskThreads = AgentThreadOrdering.sorted(unpinnedTasks)
        hasAnyActiveTaskThreads = hasAnyTask

        let pinnedProjectItems = pinnedProjects.map { project in
            SidebarPinnedItem(
                project: project,
                // Activity is only a legacy fallback for projects without a manual pin order.
                activityDate: project.pinnedSortOrder == nil
                    ? latestChildActivity[project.persistentModelID]
                    : nil
            )
        }
        let pinnedThreadItems = visibleThreads
            .filter(viewModel.isVisiblePinnedSidebarThread)
            .map(SidebarPinnedItem.init(thread:))
        pinnedItems = SidebarPinnedItemOrdering.sorted(pinnedProjectItems + pinnedThreadItems)
    }

    func activeThreads(for project: Project) -> [AgentThread] {
        activeThreadsByProjectID[project.persistentModelID] ?? []
    }

    func hasAnyActiveThreads(for project: Project) -> Bool {
        projectIDsWithActiveThreads.contains(project.persistentModelID)
    }

    /// Rows currently rendered below expanded project headers, plus every visible Task row.
    ///
    /// A collapsed section contributes nothing: its rows are not mounted, so counting them would
    /// disable the thread-order animation over content nobody can see. `Pinned` never collapses.
    func expandedThreadCount(
        expandedProjects: Set<String>,
        collapsedSections: Set<SidebarCollapsibleSection> = []
    ) -> Int {
        let pinnedThreadCount = pinnedItems.reduce(0) { count, item in
            switch item.kind {
            case .thread:
                return count + 1
            case .project(let project):
                guard expandedProjects.contains(project.path) else {
                    return count
                }
                return count + activeThreads(for: project).count
            }
        }

        let projectThreadCount = collapsedSections.contains(.projects)
            ? 0
            : regularProjects.reduce(0) { count, project in
                guard expandedProjects.contains(project.path) else {
                    return count
                }
                return count + activeThreads(for: project).count
            }
        let taskThreadCount = collapsedSections.contains(.tasks) ? 0 : activeTaskThreads.count
        return pinnedThreadCount + projectThreadCount + taskThreadCount
    }
}
