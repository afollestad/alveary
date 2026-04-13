import SwiftUI

extension SidebarView {
    static let backspaceKey = KeyEquivalent("\u{7F}")

    var navigableItems: [SidebarItem] {
        buildNavigableItems(
            projects: projects,
            expandedProjects: expandedProjects,
            activeThreads: activeThreads
        )
    }

    func handleVerticalArrow(_ key: KeyEquivalent) -> KeyPress.Result {
        let items = navigableItems
        let isDown = key == .downArrow
        guard let next = navigateVertically(
            in: items,
            from: appState.selectedSidebarItem,
            forward: isDown
        ) else {
            return items.isEmpty ? .ignored : .handled
        }
        appState.selectedSidebarItem = next
        return .handled
    }

    func handleSidebarKeyPress(_ keyPress: KeyPress) -> KeyPress.Result {
        switch keyPress.key {
        case .upArrow, .downArrow:
            return handleVerticalArrow(keyPress.key)
        case Self.backspaceKey:
            guard case .thread(let thread) = appState.selectedSidebarItem else {
                return .ignored
            }
            switch viewModel.deleteKeyAction {
            case .archive:
                Task { await archive(thread) }
            case .delete:
                pendingDeleteThread = thread
            }
            return .handled
        case .leftArrow:
            guard case .project(let project) = appState.selectedSidebarItem else {
                return .ignored
            }
            expandedProjects.remove(project.path)
            return .handled
        case .rightArrow:
            guard case .project(let project) = appState.selectedSidebarItem else {
                return .ignored
            }
            expandedProjects.insert(project.path)
            return .handled
        default:
            return .ignored
        }
    }
}

func buildNavigableItems(
    projects: [Project],
    expandedProjects: Set<String>,
    activeThreads: (Project) -> [AgentThread]
) -> [SidebarItem] {
    var items: [SidebarItem] = [.skills, .mcp]
    for project in projects {
        items.append(.project(project))
        if expandedProjects.contains(project.path) {
            for thread in activeThreads(project) {
                items.append(.thread(thread))
            }
        }
    }
    return items
}

func navigateVertically(
    in items: [SidebarItem],
    from current: SidebarItem?,
    forward: Bool
) -> SidebarItem? {
    guard !items.isEmpty else {
        return nil
    }

    let currentIndex = current.flatMap { selected in
        items.firstIndex(where: { $0 == selected })
    }

    let nextIndex: Int
    if forward {
        nextIndex = (currentIndex ?? -1) + 1
    } else {
        guard let current = currentIndex, current > 0 else {
            return nil
        }
        nextIndex = current - 1
    }

    guard items.indices.contains(nextIndex) else {
        return nil
    }

    return items[nextIndex]
}
