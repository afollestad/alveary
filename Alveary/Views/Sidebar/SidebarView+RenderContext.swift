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
    /// Waiting-dot sources the runtime cannot report, built once per body.
    ///
    /// Every set behind it is cached observable state on a coordinator, so this costs a few
    /// reference copies rather than a fetch. It is here rather than read per row because the read
    /// has to land inside `SidebarView.body`'s observation scope: every `sidebarThreadRow` call
    /// site sits in a `ForEach` content closure, which registers on that element instead, and
    /// nothing else repaints the row when a proposal resolves. That happens outside the provider
    /// turn, so no `.agentStatusChanged` bumps `statusVersion`, and both proposal coordinators
    /// clear through their own `ModelContext`, so the sidebar's `@Query` never sees it either.
    /// `ThreadDetailView+DecisionAttention.swift` hoists into `body` against the same hazard.
    let decisionAttention: ConversationDecisionAttention

    var pinnedItems: [SidebarPinnedItem] { snapshot.pinnedItems }
    var orderedProjects: [Project] { snapshot.orderedProjects }
    var regularProjects: [Project] { snapshot.regularProjects }
    var activeTaskThreads: [AgentThread] { snapshot.activeTaskThreads }
    var sectionDescriptors: [SidebarSectionDescriptor] { snapshot.sectionDescriptors }

    func activeThreads(for project: Project) -> [AgentThread] {
        snapshot.activeThreads(for: project)
    }

    func threads(inCustomSection id: String) -> [AgentThread] {
        snapshot.threads(inCustomSection: id)
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
            unarchivedThreads: queriedUnarchivedThreads,
            sections: queriedSidebarSections
        )
        let settings = viewModel.settingsService.current
        return SidebarRenderContext(
            snapshot: snapshot,
            threadOrderAnimation: threadOrderAnimation(
                expandedThreadCount: snapshot.expandedThreadCount(
                    expandedProjects: expandedProjects,
                    collapsedSections: collapsedSections
                )
            ),
            dragLogicalOrder: SidebarDragLogicalOrder(
                pinnedItems: snapshot.pinnedItems.map(\.dragItem),
                regularProjects: snapshot.regularProjects.map { .project($0.persistentModelID) },
                unpinnableTaskIDs: unpinnableTaskIDs(in: snapshot),
                projectIDByTaskID: projectIDByTaskID(in: snapshot),
                owningProjectIDByPinnedThreadID: owningProjectIDByPinnedThreadID(in: snapshot),
                customSectionIDByTaskID: snapshot.customSectionIDByTaskID,
                sections: visibleSectionDragItems(in: snapshot),
                sectionOrder: snapshot.sectionDescriptors.map(\.id)
            ),
            hasArchivedThreads: !queriedArchivedThreadProbe.isEmpty,
            showsPullRequests: settings.pullRequestsEnabled,
            decisionAttention: ConversationDecisionAttention(
                approvals: unresolvedApprovalRegistry,
                scheduledProposals: scheduledTaskProposalQueueCoordinator,
                reviewProposals: pullRequestReviewProposalCoordinator,
                settings: settings
            )
        )
    }

    /// Sections in rendered order, minus an empty `Pinned` — it draws no header, so it is neither
    /// a drag source nor a boundary anchor. Its persisted slot survives regardless, because
    /// `SidebarSectionService.moveSection` anchors on the visible neighbours the drop names.
    func visibleSectionDragItems(in snapshot: SidebarRenderSnapshot) -> [SidebarDragItem] {
        snapshot.sectionDescriptors.compactMap { descriptor in
            if descriptor.id == .pinned, snapshot.pinnedItems.isEmpty {
                return nil
            }
            return .section(descriptor.id)
        }
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

    /// The owning project for every standalone pinned Project-mode thread that may unpin by
    /// dropping onto that project group. Scheduled-attached threads are excluded, matching their
    /// disabled context-menu Unpin; `setThreadPinned`'s attachment guard is the backstop.
    func owningProjectIDByPinnedThreadID(
        in snapshot: SidebarRenderSnapshot
    ) -> [PersistentIdentifier: PersistentIdentifier] {
        var map: [PersistentIdentifier: PersistentIdentifier] = [:]
        for item in snapshot.pinnedItems {
            guard case .thread(let thread) = item.kind,
                  thread.effectiveMode == .project,
                  let projectID = thread.project?.persistentModelID,
                  viewModel.scheduledTaskAttachmentReason(for: thread) == nil else {
                continue
            }
            map[thread.persistentModelID] = projectID
        }
        return map
    }

    func threadOrderAnimation(expandedThreadCount: Int) -> Animation? {
        guard !accessibilityReduceMotion,
              !isSidebarInlineEditingActive,
              !isSidebarDragInteractionInFlight,
              expandedThreadCount <= 200 else {
            return nil
        }
        return .easeInOut(duration: 0.15)
    }
}
