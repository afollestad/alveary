import SwiftData

enum SidebarDragItem: Hashable {
    case project(PersistentIdentifier)
    case pinnedThread(PersistentIdentifier)
}

enum SidebarDropSection: Hashable {
    case pinned
    case projects
}

enum SidebarDropPlacement: Hashable {
    case before
    case after
    case end
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
    }
}

func sidebarOrder(
    afterMoving draggedItem: SidebarDragItem,
    to target: SidebarDropTarget,
    in order: SidebarDragOrder
) -> SidebarDragOrder? {
    if case .pinnedThread = draggedItem, target.section != .pinned {
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
    }

    return nextOrder
}
