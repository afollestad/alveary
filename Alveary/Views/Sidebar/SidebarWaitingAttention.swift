/// Which collapsed sidebar containers hide a thread that is waiting on the user.
///
/// A `.waitingForUser` thread shows its own blue dot on its row, and collapsing the container that
/// holds it hides that signal entirely — so the container shows the dot in its place. Only collapsed
/// containers are folded, and that gate is the whole rule: `SidebarSectionHeaderRow` and
/// `SidebarProjectRow` draw on the flag alone rather than re-checking their own expansion.
struct SidebarWaitingAttention: Equatable {
    static let none = SidebarWaitingAttention(sections: [], projectPaths: [])

    let sections: Set<SidebarCollapsibleSection>
    /// Keyed by `Project.path`, matching `SidebarView.expandedProjects`.
    let projectPaths: Set<String>

    /// `false` for `Pinned`, which has no collapse of its own.
    func hidesWaitingThread(inSection sectionID: SidebarSectionID) -> Bool {
        guard let section = SidebarCollapsibleSection(sectionID: sectionID) else {
            return false
        }
        return sections.contains(section)
    }

    func hidesWaitingThread(inProjectAt path: String) -> Bool {
        projectPaths.contains(path)
    }
}

/// Folds one render pass's collapsed containers against the threads they hide.
///
/// `isWaitingForUser` stays a closure so the fold is testable without an `AgentsManager`; its live
/// form runs `SidebarViewModel.threadStatus(threadID:isArchived:conversationStatuses:)`. Call this
/// from `SidebarView.body`'s own scope — `makeRenderContext()` — and never from a row builder: the
/// threads it reads have no mounted row, so a runtime-status read registered on a `ForEach` element
/// would never repaint when one of them starts waiting.
@MainActor
func sidebarWaitingAttention(
    snapshot: SidebarRenderSnapshot,
    collapsedSections: Set<SidebarCollapsibleSection>,
    expandedProjects: Set<String>,
    isWaitingForUser: (AgentThread) -> Bool
) -> SidebarWaitingAttention {
    var projectPaths: Set<String> = []
    // `orderedProjects` rather than `regularProjects`: `Pinned` never collapses, but the project rows
    // inside it are ordinary collapsible groups and hide their children just the same.
    for project in snapshot.orderedProjects where !expandedProjects.contains(project.path) {
        if snapshot.activeThreads(for: project).contains(where: isWaitingForUser) {
            projectPaths.insert(project.path)
        }
    }

    var sections: Set<SidebarCollapsibleSection> = []
    for section in collapsedSections where sectionHidesWaitingThread(
        section,
        snapshot: snapshot,
        isWaitingForUser: isWaitingForUser
    ) {
        sections.insert(section)
    }

    return SidebarWaitingAttention(sections: sections, projectPaths: projectPaths)
}

/// One collapsed section's half of the fold. A custom section whose row vanished this pass answers
/// `false` through an empty member list, which is also how its rows render.
@MainActor
private func sectionHidesWaitingThread(
    _ section: SidebarCollapsibleSection,
    snapshot: SidebarRenderSnapshot,
    isWaitingForUser: (AgentThread) -> Bool
) -> Bool {
    switch section {
    case .projects:
        // Pinned projects render under `Pinned`, which this collapse does not hide.
        return snapshot.regularProjects.contains { project in
            snapshot.activeThreads(for: project).contains(where: isWaitingForUser)
        }
    case .tasks:
        return snapshot.activeTaskThreads.contains(where: isWaitingForUser)
    case .custom(let id):
        return snapshot.threads(inCustomSection: id).contains(where: isWaitingForUser)
    }
}
