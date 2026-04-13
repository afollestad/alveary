import SwiftData
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
        case .return:
            return handleRenameKey()
        case Self.backspaceKey:
            return handleDeleteKey()
        case .leftArrow, .rightArrow:
            return handleHorizontalArrow(keyPress.key)
        default:
            return .ignored
        }
    }

    func handleRenameKey() -> KeyPress.Result {
        guard let threadID = renameThreadID(
            for: appState.selectedSidebarItem,
            editingThreadID: editingThreadID
        ) else {
            return .ignored
        }

        editingThreadID = threadID
        return .handled
    }

    func handleDeleteKey() -> KeyPress.Result {
        guard case .thread(let thread) = appState.selectedSidebarItem else {
            return .ignored
        }

        switch viewModel.deleteKeyAction {
        case .archive:
            pendingArchiveThread = thread
        case .delete:
            pendingDeleteThread = thread
        }
        return .handled
    }

    func handleHorizontalArrow(_ key: KeyEquivalent) -> KeyPress.Result {
        switch key {
        case .leftArrow:
            if shouldNavigateUpOnLeftArrow(
                selection: appState.selectedSidebarItem,
                expandedProjects: expandedProjects,
                projectHasVisibleThreads: { project in
                    !activeThreads(for: project).isEmpty
                }
            ) {
                return handleVerticalArrow(.upArrow)
            }

            guard case .project(let project) = appState.selectedSidebarItem else {
                return .ignored
            }
            expandedProjects.remove(project.path)
            return .handled
        case .rightArrow:
            if shouldNavigateDownOnRightArrow(
                selection: appState.selectedSidebarItem,
                expandedProjects: expandedProjects
            ) {
                return handleVerticalArrow(.downArrow)
            }

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

func shouldNavigateUpOnLeftArrow(
    selection: SidebarItem?,
    expandedProjects: Set<String>,
    projectHasVisibleThreads: (Project) -> Bool = { _ in true }
) -> Bool {
    switch selection {
    case .skills, .mcp:
        return true
    case .thread:
        return true
    case .project(let project):
        return !expandedProjects.contains(project.path) || !projectHasVisibleThreads(project)
    default:
        return false
    }
}

func shouldNavigateDownOnRightArrow(
    selection: SidebarItem?,
    expandedProjects: Set<String>
) -> Bool {
    switch selection {
    case .skills, .mcp:
        return true
    case .thread:
        return true
    case .project(let project):
        return expandedProjects.contains(project.path)
    default:
        return false
    }
}

func renameThreadID(
    for selection: SidebarItem?,
    editingThreadID: PersistentIdentifier?
) -> PersistentIdentifier? {
    guard editingThreadID == nil,
          case .thread(let thread) = selection else {
        return nil
    }

    return thread.persistentModelID
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
