import SwiftData
import SwiftUI

extension SidebarView {
    static let backspaceKey = KeyEquivalent("\u{7F}")

    func navigableItems(context: SidebarRenderContext) -> [SidebarItem] {
        buildNavigableItems(
            sections: context.sectionDescriptors,
            pinnedItems: context.pinnedItems,
            projects: context.regularProjects,
            expandedProjects: expandedProjects,
            activeThreads: context.activeThreads(for:),
            activeTasks: context.activeTaskThreads,
            customSectionThreads: context.threads(inCustomSection:),
            collapsedSections: collapsedSections,
            hasArchivedThreads: context.hasArchivedThreads,
            showsPullRequests: context.showsPullRequests
        )
    }

    func handleVerticalArrow(_ key: KeyEquivalent, context: SidebarRenderContext) -> KeyPress.Result {
        let items = navigableItems(context: context)
        let isDown = key == .downArrow
        guard let next = navigateVertically(
            in: items,
            from: effectiveSidebarSelection(appState.selectedSidebarItem),
            forward: isDown
        ) else {
            return items.isEmpty ? .ignored : .handled
        }
        appState.selectedSidebarItem = next
        return .handled
    }

    func handleSidebarKeyPress(_ keyPress: KeyPress, context: SidebarRenderContext) -> KeyPress.Result {
        if isSidebarDragInteractionInFlight {
            return .handled
        }

        // Let the inline-rename TextField own the keyboard while editing so arrow keys,
        // Return, and Delete don't leak into sidebar navigation or trigger a re-entrant
        // rename. Re-enabling this path while `editingThreadID` is set produces key
        // collisions — `handleRenameKey()` guards against re-entering edit mode, but
        // the other cases still mutate `selectedSidebarItem`, leaving the TextField
        // stranded on a different row.
        if shouldSuppressSidebarKeyPressWhileEditing(isInlineEditingActive: isSidebarInlineEditingActive) {
            return .ignored
        }

        switch keyPress.key {
        case .upArrow, .downArrow:
            return handleVerticalArrow(keyPress.key, context: context)
        case .return:
            return handleRenameKey()
        case Self.backspaceKey:
            return handleDeleteKey()
        case .leftArrow, .rightArrow:
            return handleHorizontalArrow(keyPress.key, context: context)
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
        guard let confirmation = threadCleanupConfirmation(
            for: appState.selectedSidebarItem,
            action: viewModel.defaultThreadCleanupAction
        ) else {
            return .ignored
        }

        switch confirmation {
        case .archive(let thread):
            requestArchive(thread)
        case .delete(let thread):
            requestDelete(thread)
        }
        return .handled
    }

    func handleHorizontalArrow(_ key: KeyEquivalent, context: SidebarRenderContext) -> KeyPress.Result {
        let selection = effectiveSidebarSelection(appState.selectedSidebarItem)
        switch key {
        case .leftArrow:
            if shouldNavigateUpOnLeftArrow(
                selection: selection,
                expandedProjects: expandedProjects
            ) {
                return handleVerticalArrow(.upArrow, context: context)
            }

            guard case .project(let project) = selection else {
                return .ignored
            }
            expandedProjects.remove(project.path)
            return .handled
        case .rightArrow:
            if shouldNavigateDownOnRightArrow(
                selection: selection,
                expandedProjects: expandedProjects
            ) {
                return handleVerticalArrow(.downArrow, context: context)
            }

            guard case .project(let project) = selection else {
                return .ignored
            }
            expandedProjects.insert(project.path)
            return .handled
        default:
            return .ignored
        }
    }
}

func effectiveSidebarSelection(_ selection: SidebarItem?) -> SidebarItem? {
    guard case .thread(let thread) = selection,
          thread.isDraft else {
        return selection
    }
    guard thread.effectiveMode == .project,
          let project = thread.project else {
        return nil
    }
    return .project(project)
}

func shouldNavigateUpOnLeftArrow(
    selection: SidebarItem?,
    expandedProjects: Set<String>
) -> Bool {
    switch selection {
    case .skills, .mcp, .scheduled, .pullRequests, .archived:
        return true
    case .thread:
        return true
    case .project(let project):
        return !expandedProjects.contains(project.path)
    default:
        return false
    }
}

func shouldNavigateDownOnRightArrow(
    selection: SidebarItem?,
    expandedProjects: Set<String>
) -> Bool {
    switch selection {
    case .skills, .mcp, .scheduled, .pullRequests, .archived:
        return true
    case .thread:
        return true
    case .project(let project):
        return expandedProjects.contains(project.path)
    default:
        return false
    }
}

// While any inline field is active — a thread rename, a section rename, or the pending
// new-section row — that TextField must own the keyboard so typing/arrow/Delete don't
// leak into sidebar navigation. Split out so tests can lock in the invariant
// without needing to instantiate `SidebarView`.
func shouldSuppressSidebarKeyPressWhileEditing(isInlineEditingActive: Bool) -> Bool {
    isInlineEditingActive
}

enum SidebarThreadCleanupConfirmation {
    case archive(AgentThread)
    case delete(AgentThread)
}

func threadCleanupConfirmation(
    for selection: SidebarItem?,
    action: ThreadCleanupAction
) -> SidebarThreadCleanupConfirmation? {
    guard case .thread(let thread) = selection, !thread.isDraft else {
        return nil
    }

    switch action {
    case .archive:
        return .archive(thread)
    case .delete:
        return .delete(thread)
    }
}

func renameThreadID(
    for selection: SidebarItem?,
    editingThreadID: PersistentIdentifier?
) -> PersistentIdentifier? {
    guard editingThreadID == nil,
          case .thread(let thread) = selection,
          !thread.isDraft else {
        return nil
    }

    return thread.persistentModelID
}

/// Traversal follows the rendered section order, so a reordered sidebar arrows in the order the
/// user sees. Section headers are never navigable, and a collapsed section contributes nothing.
func buildNavigableItems(
    sections: [SidebarSectionDescriptor] = SidebarSectionDescriptor.builtinFallback,
    pinnedItems: [SidebarPinnedItem] = [],
    projects: [Project],
    expandedProjects: Set<String>,
    activeThreads: (Project) -> [AgentThread],
    activeTasks: [AgentThread] = [],
    customSectionThreads: (String) -> [AgentThread] = { _ in [] },
    collapsedSections: Set<SidebarCollapsibleSection> = [],
    hasArchivedThreads: Bool = false,
    showsPullRequests: Bool = true
) -> [SidebarItem] {
    var items = sidebarTopLevelRowItems(
        showsPullRequests: showsPullRequests,
        hasArchivedThreads: hasArchivedThreads
    )
    for section in sections {
        if let collapseKey = SidebarCollapsibleSection(sectionID: section.id),
           collapsedSections.contains(collapseKey) {
            continue
        }
        switch section.id {
        case .pinned:
            // `Pinned` has no collapse of its own, so its rows always traverse.
            for pinnedItem in pinnedItems {
                items.append(pinnedItem.sidebarItem)
                if case .project(let project) = pinnedItem.kind,
                   expandedProjects.contains(project.path) {
                    items.append(contentsOf: activeThreads(project).map(SidebarItem.thread))
                }
            }
        case .projects:
            for project in projects {
                items.append(.project(project))
                if expandedProjects.contains(project.path) {
                    items.append(contentsOf: activeThreads(project).map(SidebarItem.thread))
                }
            }
        case .tasks:
            items.append(contentsOf: activeTasks.map(SidebarItem.thread))
        case .custom(let sectionID):
            items.append(contentsOf: customSectionThreads(sectionID).map(SidebarItem.thread))
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
