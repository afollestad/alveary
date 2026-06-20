enum SidebarThreadContextMenuItem: Equatable, Hashable {
    case forkLocal
    case forkWorktree
    case divider
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
        case .rename:
            "Rename..."
        case .archive:
            "Archive..."
        case .delete:
            "Delete..."
        }
    }
}

func sidebarThreadContextMenuItems(canRename: Bool) -> [SidebarThreadContextMenuItem] {
    var items: [SidebarThreadContextMenuItem] = [
        .forkLocal,
        .forkWorktree,
        .divider
    ]
    if canRename {
        items.append(.rename)
    }
    items.append(contentsOf: [.archive, .delete])
    return items
}
