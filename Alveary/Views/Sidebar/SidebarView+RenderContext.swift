import SwiftData
import SwiftUI

/// Everything one `SidebarView.body` pass shares with its row builders and event handlers.
///
/// Built once per body evaluation so no row, placeholder, count, keyboard traversal,
/// or drag-start path re-reads SwiftData while the click-to-highlight frame is pending.
@MainActor
struct SidebarRenderContext {
    let snapshot: SidebarRenderSnapshot
    let threadOrderAnimation: Animation?
    let dragLogicalOrder: SidebarDragLogicalOrder
    let hasArchivedThreads: Bool
    let showsPullRequests: Bool

    var pinnedItems: [SidebarPinnedItem] { snapshot.pinnedItems }
    var orderedProjects: [Project] { snapshot.orderedProjects }
    var regularProjects: [Project] { snapshot.regularProjects }
    var activeTaskThreads: [AgentThread] { snapshot.activeTaskThreads }

    func activeThreads(for project: Project) -> [AgentThread] {
        snapshot.activeThreads(for: project)
    }

    func hasAnyActiveThreads(for project: Project) -> Bool {
        snapshot.hasAnyActiveThreads(for: project)
    }
}

extension SidebarView {
    func makeRenderContext() -> SidebarRenderContext {
        let snapshot = SidebarRenderSnapshot(
            viewModel: viewModel,
            projects: queriedProjects,
            unarchivedThreads: queriedUnarchivedThreads
        )
        return SidebarRenderContext(
            snapshot: snapshot,
            threadOrderAnimation: threadOrderAnimation(
                expandedThreadCount: snapshot.expandedThreadCount(expandedProjects: expandedProjects)
            ),
            dragLogicalOrder: SidebarDragLogicalOrder(
                pinnedItems: snapshot.pinnedItems.map(\.dragItem),
                regularProjects: snapshot.regularProjects.map { .project($0.persistentModelID) },
                projectsHeaderIsSticky: snapshot.pinnedItems.isEmpty,
                unpinnableTaskIDs: unpinnableTaskIDs(in: snapshot),
                projectIDByTaskID: projectIDByTaskID(in: snapshot)
            ),
            hasArchivedThreads: !queriedArchivedThreadProbe.isEmpty,
            showsPullRequests: viewModel.settingsService.current.showsPullRequestsInSidebar
        )
    }

    func unpinnableTaskIDs(in snapshot: SidebarRenderSnapshot) -> Set<PersistentIdentifier> {
        var ids: Set<PersistentIdentifier> = []
        for item in snapshot.pinnedItems {
            guard case .thread(let thread) = item.kind,
                  thread.effectiveMode == .task,
                  viewModel.scheduledTaskAttachmentReason(for: thread) == nil else {
                continue
            }
            ids.insert(thread.persistentModelID)
        }
        return ids
    }

    /// Every Task thread placed in a project, keyed to that project — nested children plus
    /// standalone pinned Tasks whose backing project is unpinned.
    func projectIDByTaskID(in snapshot: SidebarRenderSnapshot) -> [PersistentIdentifier: PersistentIdentifier] {
        var map: [PersistentIdentifier: PersistentIdentifier] = [:]
        for project in snapshot.orderedProjects {
            for thread in snapshot.activeThreads(for: project) where thread.effectiveMode == .task {
                map[thread.persistentModelID] = project.persistentModelID
            }
        }
        for item in snapshot.pinnedItems {
            guard case .thread(let thread) = item.kind,
                  thread.effectiveMode == .task,
                  let projectID = thread.project?.persistentModelID else {
                continue
            }
            map[thread.persistentModelID] = projectID
        }
        return map
    }

    func threadOrderAnimation(expandedThreadCount: Int) -> Animation? {
        guard !accessibilityReduceMotion,
              editingThreadID == nil,
              !isSidebarDragInteractionInFlight,
              expandedThreadCount <= 200 else {
            return nil
        }
        return .easeInOut(duration: 0.15)
    }
}
