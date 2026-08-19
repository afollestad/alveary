/// What a collapsed sidebar container hides that is worth surfacing on the container itself.
///
/// A thread shows its own status on its row, so collapsing the container holding it hides that
/// signal; the container stands in for the row it hid. Only these two states are worth standing in
/// for — an inert or finished thread has nothing the user needs to act on or wait for.
enum SidebarHiddenActivity: Equatable {
    /// At least one hidden thread is `.waitingForUser`.
    case waitingForUser
    /// No hidden thread is waiting, but at least one is `.busy`.
    case working
}

/// Which collapsed sidebar containers hide a thread worth surfacing, and what they hide.
///
/// Only collapsed containers are folded, and that gate is the whole rule:
/// `SidebarSectionHeaderRow` and `SidebarProjectRow` draw on the value alone rather than
/// re-checking their own expansion.
struct SidebarCollapsedActivity: Equatable {
    static let none = SidebarCollapsedActivity(sections: [:], projectPaths: [:])

    let sections: [SidebarCollapsibleSection: SidebarHiddenActivity]
    /// Keyed by `Project.path`, matching `SidebarView.expandedProjects`.
    let projectPaths: [String: SidebarHiddenActivity]

    /// `nil` for `Pinned`, which has no collapse of its own.
    func hiddenActivity(inSection sectionID: SidebarSectionID) -> SidebarHiddenActivity? {
        guard let section = SidebarCollapsibleSection(sectionID: sectionID) else {
            return nil
        }
        return sections[section]
    }

    func hiddenActivity(inProjectAt path: String) -> SidebarHiddenActivity? {
        projectPaths[path]
    }
}

/// Folds one render pass's collapsed containers against the threads they hide.
///
/// `statusFor` stays a closure so the fold is testable without an `AgentsManager`; its live form
/// is `SidebarViewModel.threadStatus(threadID:isArchived:conversationStatuses:)`. Call this from
/// `SidebarView.body`'s own scope — `makeRenderContext()` — and never from a row builder: the
/// threads it reads have no mounted row, so a runtime-status read registered on a `ForEach`
/// element would never repaint when one of them starts working or starts waiting.
@MainActor
func sidebarCollapsedActivity(
    snapshot: SidebarRenderSnapshot,
    collapsedSections: Set<SidebarCollapsibleSection>,
    expandedProjects: Set<String>,
    statusFor: (AgentThread) -> ThreadStatus
) -> SidebarCollapsedActivity {
    var projectPaths: [String: SidebarHiddenActivity] = [:]
    // `orderedProjects` rather than `regularProjects`: `Pinned` never collapses, but the project
    // rows inside it are ordinary collapsible groups and hide their children just the same.
    for project in snapshot.orderedProjects where !expandedProjects.contains(project.path) {
        if let activity = hiddenActivity(in: snapshot.activeThreads(for: project), statusFor: statusFor) {
            projectPaths[project.path] = activity
        }
    }

    var sections: [SidebarCollapsibleSection: SidebarHiddenActivity] = [:]
    for section in collapsedSections {
        if let activity = hiddenActivity(in: threads(in: section, of: snapshot), statusFor: statusFor) {
            sections[section] = activity
        }
    }

    return SidebarCollapsedActivity(sections: sections, projectPaths: projectPaths)
}

/// Waiting outranks working, inverting `ThreadStatus.folded`'s own ladder — deliberately.
///
/// There `.busy` beats `.waitingForUser` because both can describe the *same* thread, and a live
/// busy proves its turn never ended. Across *different* hidden threads that argument does not
/// apply: one thread genuinely needs an answer while another genuinely works, and the answer is
/// the only one the user can act on. Reporting the spinner there would bury it.
@MainActor
private func hiddenActivity(
    in threads: [AgentThread],
    statusFor: (AgentThread) -> ThreadStatus
) -> SidebarHiddenActivity? {
    var isWorking = false
    for thread in threads {
        switch statusFor(thread) {
        case .waitingForUser:
            return .waitingForUser
        case .busy:
            isWorking = true
        case .unread, .stopped, .error, .archived:
            continue
        }
    }
    return isWorking ? .working : nil
}

/// The rows a collapsed section hides. A custom section whose row vanished this pass answers with
/// an empty list, which is also how its rows render.
@MainActor
private func threads(in section: SidebarCollapsibleSection, of snapshot: SidebarRenderSnapshot) -> [AgentThread] {
    switch section {
    case .projects:
        // Pinned projects render under `Pinned`, which this collapse does not hide.
        return snapshot.regularProjects.flatMap(snapshot.activeThreads(for:))
    case .tasks:
        return snapshot.activeTaskThreads
    case .custom(let id):
        return snapshot.threads(inCustomSection: id)
    }
}
