import SwiftData

enum SidebarDragItem: Hashable {
    case project(PersistentIdentifier)
    case pinnedThread(PersistentIdentifier)
    case pinnedTask(PersistentIdentifier)
    case unpinnedTask(PersistentIdentifier)
    /// An unpinned Project-mode thread nested under its project. Draggable only to pin: its sole
    /// target is `Pinned`, because a project's child list has no manual order to reorder against.
    case projectThread(PersistentIdentifier)
}

enum SidebarDropSection: Hashable {
    case pinned
    case projects
    case tasks
}

enum SidebarDropPlacement: Hashable {
    case before
    case after
    case end
    /// Drop onto a container rather than between rows. Reparents a Task, or unpins a pinned
    /// thread dropped onto its owning project; never reorders.
    case into
}

struct SidebarDropTarget: Hashable {
    let section: SidebarDropSection
    let item: SidebarDragItem?
    let placement: SidebarDropPlacement

    init(section: SidebarDropSection, item: SidebarDragItem? = nil, placement: SidebarDropPlacement) {
        self.section = section
        self.item = item
        self.placement = placement
    }
}

struct SidebarDragOrder: Equatable {
    var pinnedItems: [SidebarDragItem]
    var regularProjects: [SidebarDragItem]
}

func sidebarInsertionIndex(
    in items: [SidebarDragItem],
    draggedItem: SidebarDragItem,
    target: SidebarDropTarget
) -> Int? {
    guard target.placement != .into else {
        return nil
    }
    if target.item == draggedItem {
        return items.firstIndex(of: draggedItem)
    }

    let remainingItems = items.filter { $0 != draggedItem }
    guard let targetItem = target.item else {
        switch target.placement {
        case .before:
            return 0
        case .after, .end:
            return remainingItems.count
        case .into:
            return nil
        }
    }

    guard let targetIndex = remainingItems.firstIndex(of: targetItem) else {
        return nil
    }

    switch target.placement {
    case .before:
        return targetIndex
    case .after, .end:
        return targetIndex + 1
    case .into:
        return nil
    }
}

func sidebarOrder(
    afterMoving draggedItem: SidebarDragItem,
    to target: SidebarDropTarget,
    in order: SidebarDragOrder
) -> SidebarDragOrder? {
    // Dropping into a project reparents the thread; `commitSidebarDrop` never routes it here.
    guard target.placement != .into else {
        return nil
    }
    if draggedItem.isConversation, target.section != .pinned {
        return nil
    }

    var nextOrder = order
    nextOrder.pinnedItems.removeAll { $0 == draggedItem }
    nextOrder.regularProjects.removeAll { $0 == draggedItem }

    switch target.section {
    case .pinned:
        guard let insertionIndex = sidebarInsertionIndex(
            in: order.pinnedItems,
            draggedItem: draggedItem,
            target: target
        ) else {
            return nil
        }
        nextOrder.pinnedItems.insert(draggedItem, at: min(insertionIndex, nextOrder.pinnedItems.count))
    case .projects:
        guard case .project = draggedItem,
              let insertionIndex = sidebarInsertionIndex(
                  in: order.regularProjects,
                  draggedItem: draggedItem,
                  target: target
              ) else {
            return nil
        }
        nextOrder.regularProjects.insert(draggedItem, at: min(insertionIndex, nextOrder.regularProjects.count))
    case .tasks:
        // Tasks are activity-sorted, never manually ordered; a Tasks drop is an unpin, not a reorder.
        return nil
    }

    return nextOrder
}

extension SidebarDragItem {
    var isConversation: Bool {
        switch self {
        case .project:
            false
        case .pinnedThread, .pinnedTask, .unpinnedTask, .projectThread:
            true
        }
    }
}
