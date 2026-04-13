import SwiftUI

extension SidebarView {
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
