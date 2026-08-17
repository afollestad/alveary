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
    /// Per-thread status inputs, snapshotted as values once per body.
    ///
    /// Two constraints meet here. The waiting-dot sets behind `ConversationDecisionAttention`
    /// are cached observable coordinator state whose reads must land inside `SidebarView.body`'s
    /// observation scope: every `sidebarThreadRow` call site sits in a `ForEach` content closure,
    /// which registers on that element instead, and nothing else repaints the row when a proposal
    /// resolves — that happens outside the provider turn, so no `.agentStatusChanged` bumps
    /// `statusVersion`, and both proposal coordinators clear through their own `ModelContext`, so
    /// the sidebar's `@Query` never sees it either. And the persisted per-conversation reads must
    /// happen while this pass's liveness-filtered rows are known live — deferring them to a row
    /// or fold that runs later can trap on a deleted row (`ConversationStatusSnapshot` owns the
    /// mechanism). `ThreadDetailView` builds its tab presentations in `body` against the same
    /// hazards.
    let conversationStatusesByThreadID: [PersistentIdentifier: [ConversationStatusSnapshot]]

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

    /// `[]` for an unknown thread — the correct degradation for a row whose conversations died
    /// mid-pass: the fold answers `.stopped` instead of reading anything.
    func conversationStatuses(for threadID: PersistentIdentifier) -> [ConversationStatusSnapshot] {
        conversationStatusesByThreadID[threadID] ?? []
    }
}

extension SidebarView {
    func makeRenderContext() -> SidebarRenderContext {
        // Drop dead rows before anything reads a persisted property. `@Query` arrays are not
        // re-fetched per body evaluation, so a delete that committed this tick — through this
        // context or merged in from another — leaves dead instances published until the query
        // republishes, and a body re-run from any other observation (a selection write, a
        // `statusVersion` bump) gets there first. The 0.2.2 (11) notification-click crash was
        // this pass's pinned-thread walk reading such a row; `isLiveForRender` owns the check.
        // Nothing below this filter may read from the raw query arrays.
        let snapshot = SidebarRenderSnapshot(
            viewModel: viewModel,
            projects: queriedProjects.filter(\.isLiveForRender),
            unarchivedThreads: queriedUnarchivedThreads.filter(\.isLiveForRender),
            sections: queriedSidebarSections.filter(\.isLiveForRender)
        )
        let settings = viewModel.settingsService.current
        let decisionAttention = ConversationDecisionAttention(
            approvals: unresolvedApprovalRegistry,
            scheduledProposals: scheduledTaskProposalQueueCoordinator,
            reviewProposals: pullRequestReviewProposalCoordinator,
            settings: settings
        )
        var conversationStatusesByThreadID: [PersistentIdentifier: [ConversationStatusSnapshot]] = [:]
        for conversation in queriedStatusFoldConversations.filter(\.isLiveForRender) {
            guard let thread = conversation.thread, thread.isLiveForRender else {
                continue
            }
            conversationStatusesByThreadID[thread.persistentModelID, default: []].append(
                ConversationStatusSnapshot(conversation: conversation, attention: decisionAttention)
            )
        }
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
            conversationStatusesByThreadID: conversationStatusesByThreadID
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
