import SwiftUI

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

func sidebarThreadContextMenuDisabledReason(
    for item: SidebarThreadContextMenuItem,
    scheduledTaskAttachmentReason: String?
) -> String? {
    guard let scheduledTaskAttachmentReason else { return nil }
    switch item {
    case .unpin, .archive, .delete:
        return scheduledTaskAttachmentReason
    case .forkLocal, .forkWorktree, .divider, .pin, .rename:
        return nil
    }
}

func sidebarThreadContextMenuItems(
    isPinned: Bool,
    canRename: Bool,
    allowsPinning: Bool = true,
    allowsForking: Bool = true
) -> [SidebarThreadContextMenuItem] {
    var items: [SidebarThreadContextMenuItem] = []
    if allowsForking {
        items.append(contentsOf: [.forkLocal, .forkWorktree, .divider])
    }
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

struct SidebarThreadContextMenuActionButton: View {
    let title: String
    let role: ButtonRole?
    let disabledReason: String?
    let action: () -> Void

    init(
        _ title: String,
        role: ButtonRole? = nil,
        disabledReason: String? = nil,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.role = role
        self.disabledReason = disabledReason
        self.action = action
    }

    var body: some View {
        Button(role: role, action: action) {
            HStack(spacing: 6) {
                Text(title)

                if let disabledReason {
                    AppHoverInfoIcon(text: disabledReason)
                }
            }
        }
        .disabled(disabledReason != nil)
        .accessibilityHint(disabledReason ?? "")
    }
}
