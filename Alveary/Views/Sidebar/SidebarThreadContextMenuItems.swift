enum SidebarThreadContextMenuItem: Equatable, Hashable {
    case forkLocal
    case forkWorktree
    case divider
    case pin
    case unpin
    case rename
    case archive
    case delete

    var title: String? {
        switch self {
        case .forkLocal:
            "Fork into local"
        case .forkWorktree:
            "Fork into worktree"
        case .divider:
            nil
        case .pin:
            "Pin"
        case .unpin:
            "Unpin"
        case .rename:
            "Rename..."
        case .archive:
            "Archive..."
        case .delete:
            "Delete..."
        }
    }
}

func sidebarThreadContextMenuItems(
    isPinned: Bool,
    canRename: Bool,
    allowsPinning: Bool = true
) -> [SidebarThreadContextMenuItem] {
    var items: [SidebarThreadContextMenuItem] = [
        .forkLocal,
        .forkWorktree,
        .divider
    ]
    if allowsPinning {
        items.append(isPinned ? .unpin : .pin)
    }
    if canRename {
        items.append(.rename)
    }
    items.append(contentsOf: [.archive, .delete])
    return items
}

func sidebarProjectPinContextMenuTitle(isPinned: Bool) -> String {
    isPinned ? "Unpin Project" : "Pin Project"
}
