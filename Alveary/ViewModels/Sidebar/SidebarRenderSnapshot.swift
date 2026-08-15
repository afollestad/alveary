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
    /// Every section in persisted order, `Pinned` included even while empty — the view decides
    /// what renders. Falls back to the fixed builtin layout until section rows exist, so a
    /// pre-seed store renders identically to one that was never sectioned.
    let sectionDescriptors: [SidebarSectionDescriptor]
    /// Custom-section home of every visible member thread, pinned members included; drag
    /// eligibility reads it, and a member of a vanished section is absent (it renders in `Tasks`).
    let customSectionIDByTaskID: [PersistentIdentifier: String]

    private let activeThreadsByProjectID: [PersistentIdentifier: [AgentThread]]
    private let projectIDsWithActiveThreads: Set<PersistentIdentifier>
    private let activeThreadsByCustomSectionID: [String: [AgentThread]]

    init(
        viewModel: SidebarViewModel,
        projects: [Project],
        unarchivedThreads: [AgentThread],
        sections: [SidebarSection] = []
    ) {
        let regular = viewModel.regularProjects(from: projects)
        let pinnedProjects = projects.filter(\.isPinned)
        regularProjects = regular
        orderedProjects = regular + pinnedProjects.sorted(by: viewModel.comparePinnedProjects)

        let descriptors = sections.isEmpty
            ? SidebarSectionDescriptor.builtinFallback
            : SidebarSectionNormalization.orderedSections(sections).map(\.descriptor)
        sectionDescriptors = descriptors
        let customSectionIDs = Set(descriptors.compactMap(\.id.customID))

        // Provisional drafts never render as rows, counts, or pinned items.
        let visibleThreads = unarchivedThreads.filter { !$0.isDraft }
        let pinnedProjectIDs = Set(pinnedProjects.map(\.persistentModelID))

        let grouping = Self.groupThreads(
            visibleThreads,
            pinnedProjectIDs: pinnedProjectIDs,
            customSectionIDs: customSectionIDs
        )

        activeThreadsByProjectID = grouping.childThreads.mapValues(AgentThreadOrdering.sorted)
        projectIDsWithActiveThreads = grouping.projectIDsWithThreads
        activeTaskThreads = AgentThreadOrdering.sorted(grouping.unpinnedTasks)
        activeThreadsByCustomSectionID = grouping.customSectionThreads.mapValues(AgentThreadOrdering.sorted)
        customSectionIDByTaskID = grouping.customSectionByThreadID
        hasAnyActiveTaskThreads = grouping.hasAnyTask

        let pinnedProjectItems = pinnedProjects.map { project in
            SidebarPinnedItem(
                project: project,
                // Activity is only a legacy fallback for projects without a manual pin order.
                activityDate: project.pinnedSortOrder == nil
                    ? grouping.latestChildActivity[project.persistentModelID]
                    : nil
            )
        }
        let pinnedThreadItems = visibleThreads
            .filter(viewModel.isVisiblePinnedSidebarThread)
            .map(SidebarPinnedItem.init(thread:))
        pinnedItems = SidebarPinnedItemOrdering.sorted(pinnedProjectItems + pinnedThreadItems)
    }

    private struct ThreadGrouping {
        var childThreads: [PersistentIdentifier: [AgentThread]] = [:]
        var projectIDsWithThreads: Set<PersistentIdentifier> = []
        var latestChildActivity: [PersistentIdentifier: Date] = [:]
        var unpinnedTasks: [AgentThread] = []
        var customSectionThreads: [String: [AgentThread]] = [:]
        var customSectionByThreadID: [PersistentIdentifier: String] = [:]
        var hasAnyTask = false
    }

    private static func groupThreads(
        _ visibleThreads: [AgentThread],
        pinnedProjectIDs: Set<PersistentIdentifier>,
        customSectionIDs: Set<String>
    ) -> ThreadGrouping {
        var grouping = ThreadGrouping()
        for thread in visibleThreads {
            if thread.effectiveMode == .task {
                grouping.hasAnyTask = true
            }
            // A Task placed in a project renders as one of its children while staying a Task; a
            // projectless Task belongs to the `Tasks` section, or to its custom section when it
            // is a member of one that still exists.
            guard let projectID = thread.project?.persistentModelID else {
                if thread.effectiveMode == .task {
                    let memberSectionID = thread.customSection.flatMap { section in
                        customSectionIDs.contains(section.id) ? section.id : nil
                    }
                    if let memberSectionID {
                        grouping.customSectionByThreadID[thread.persistentModelID] = memberSectionID
                    }
                    if !thread.isPinned {
                        if let memberSectionID {
                            grouping.customSectionThreads[memberSectionID, default: []].append(thread)
                        } else {
                            grouping.unpinnedTasks.append(thread)
                        }
                    }
                }
                continue
            }
            grouping.projectIDsWithThreads.insert(projectID)
            if let modifiedAt = thread.modifiedAt {
                grouping.latestChildActivity[projectID] = max(
                    grouping.latestChildActivity[projectID] ?? modifiedAt,
                    modifiedAt
                )
            }
            // Pinned children render standalone unless their project is itself pinned.
            if pinnedProjectIDs.contains(projectID) || !thread.isPinned {
                grouping.childThreads[projectID, default: []].append(thread)
            }
        }
        return grouping
    }

    /// Activity-sorted like `activeTaskThreads` — custom sections share the `Tasks` ordering
    /// rules, and pinned members are excluded here because they render under `Pinned`.
    func threads(inCustomSection id: String) -> [AgentThread] {
        activeThreadsByCustomSectionID[id] ?? []
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
        let customSectionThreadCount = activeThreadsByCustomSectionID.reduce(0) { count, entry in
            collapsedSections.contains(.custom(entry.key)) ? count : count + entry.value.count
        }
        return pinnedThreadCount + projectThreadCount + taskThreadCount + customSectionThreadCount
    }
}
