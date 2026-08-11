import SwiftData
import SwiftUI

extension SidebarView {
    func projectDragConfiguration(
        for project: Project,
        logicalOrder: SidebarDragLogicalOrder
    ) -> SidebarRowDragConfiguration? {
        guard editingThreadID == nil else {
            return nil
        }

        let item = SidebarDragItem.project(project.persistentModelID)
        return SidebarRowDragConfiguration(
            isEnabled: sidebarDragSourceIsEnabled(item),
            onChanged: { location in
                updateSidebarDrag(item: item, location: location, logicalOrder: logicalOrder)
            },
            onEnded: { location in
                finishSidebarDragGesture(item: item, location: location)
            }
        )
    }

    func pinnedItemDragConfiguration(
        for thread: AgentThread,
        logicalOrder: SidebarDragLogicalOrder
    ) -> SidebarRowDragConfiguration? {
        switch thread.effectiveMode {
        case .project:
            return pinnedThreadDragConfiguration(for: thread, logicalOrder: logicalOrder)
        case .task:
            return pinnedTaskDragConfiguration(for: thread, logicalOrder: logicalOrder)
        }
    }

    func pinnedItemDragGeometryRole(for thread: AgentThread) -> SidebarDragGeometryRole {
        switch thread.effectiveMode {
        case .project:
            return .pinnedThread(thread.persistentModelID)
        case .task:
            return .pinnedTask(thread.persistentModelID)
        }
    }

    private func pinnedThreadDragConfiguration(
        for thread: AgentThread,
        logicalOrder: SidebarDragLogicalOrder
    ) -> SidebarRowDragConfiguration? {
        guard editingThreadID == nil,
              thread.effectiveMode == .project,
              thread.isPinned,
              !thread.isDraft,
              thread.archivedAt == nil,
              thread.project?.isPinned != true else {
            return nil
        }

        let item = SidebarDragItem.pinnedThread(thread.persistentModelID)
        return SidebarRowDragConfiguration(
            isEnabled: sidebarDragSourceIsEnabled(item),
            onChanged: { location in
                updateSidebarDrag(item: item, location: location, logicalOrder: logicalOrder)
            },
            onEnded: { location in
                finishSidebarDragGesture(item: item, location: location)
            }
        )
    }

    private func pinnedTaskDragConfiguration(
        for thread: AgentThread,
        logicalOrder: SidebarDragLogicalOrder
    ) -> SidebarRowDragConfiguration? {
        guard editingThreadID == nil,
              thread.effectiveMode == .task,
              thread.isPinned,
              !thread.isDraft,
              thread.archivedAt == nil else {
            return nil
        }

        let item = SidebarDragItem.pinnedTask(thread.persistentModelID)
        return SidebarRowDragConfiguration(
            isEnabled: sidebarDragSourceIsEnabled(item),
            onChanged: { location in
                updateSidebarDrag(item: item, location: location, logicalOrder: logicalOrder)
            },
            onEnded: { location in
                finishSidebarDragGesture(item: item, location: location)
            }
        )
    }

    /// A project's nested child rows: Task children drag as `.unpinnedTask` (they can leave for
    /// `Tasks` or pin), Project-mode children drag as `.projectThread` (pin is their only move).
    func projectChildDragConfiguration(
        for thread: AgentThread,
        logicalOrder: SidebarDragLogicalOrder
    ) -> SidebarRowDragConfiguration? {
        switch thread.effectiveMode {
        case .task:
            return unpinnedTaskDragConfiguration(for: thread, logicalOrder: logicalOrder)
        case .project:
            return projectThreadDragConfiguration(for: thread, logicalOrder: logicalOrder)
        }
    }

    private func projectThreadDragConfiguration(
        for thread: AgentThread,
        logicalOrder: SidebarDragLogicalOrder
    ) -> SidebarRowDragConfiguration? {
        guard editingThreadID == nil,
              thread.effectiveMode == .project,
              !thread.isPinned,
              !thread.isDraft,
              thread.archivedAt == nil,
              // A pinned parent absorbs child pins, so the drop's only destination would render
              // nothing — withhold the source rather than offer a drag that looks like a no-op.
              thread.project?.isPinned != true else {
            return nil
        }

        let item = SidebarDragItem.projectThread(thread.persistentModelID)
        return SidebarRowDragConfiguration(
            isEnabled: sidebarDragSourceIsEnabled(item),
            onChanged: { location in
                updateSidebarDrag(item: item, location: location, logicalOrder: logicalOrder)
            },
            onEnded: { location in
                finishSidebarDragGesture(item: item, location: location)
            }
        )
    }

    func unpinnedTaskDragConfiguration(
        for thread: AgentThread,
        logicalOrder: SidebarDragLogicalOrder
    ) -> SidebarRowDragConfiguration? {
        guard editingThreadID == nil,
              thread.effectiveMode == .task,
              !thread.isPinned,
              !thread.isDraft,
              thread.archivedAt == nil else {
            return nil
        }

        let item = SidebarDragItem.unpinnedTask(thread.persistentModelID)
        return SidebarRowDragConfiguration(
            isEnabled: sidebarDragSourceIsEnabled(item),
            onChanged: { location in
                updateSidebarDrag(item: item, location: location, logicalOrder: logicalOrder)
            },
            onEnded: { location in
                finishSidebarDragGesture(item: item, location: location)
            }
        )
    }

    func sidebarDragSourceIsEnabled(_ item: SidebarDragItem) -> Bool {
        switch sidebarDragInteractionState {
        case .idle:
            return true
        case .active(let session):
            return session.item == item
        case .cancelledUntilMouseUp:
            return false
        }
    }
}
