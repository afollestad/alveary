import Foundation
import SwiftData

/// A thread or project that links a pull request, carrying the live model so a
/// row can render its name and select it.
enum PullRequestLinkingOwner: Identifiable {
    case project(Project)
    case thread(AgentThread)

    var id: PersistentIdentifier {
        switch self {
        case .project(let project):
            return project.persistentModelID
        case .thread(let thread):
            return thread.persistentModelID
        }
    }

    var displayName: String {
        switch self {
        case .project(let project):
            return project.name
        case .thread(let thread):
            return thread.displayName()
        }
    }

    var linkOwner: PullRequestLinkOwner {
        switch self {
        case .project(let project):
            return .project(project.persistentModelID)
        case .thread(let thread):
            return .thread(thread.persistentModelID)
        }
    }

    var isProject: Bool {
        if case .project = self {
            return true
        }
        return false
    }
}

/// Answers "which threads and projects link this pull request" — the reverse of
/// `linkedPullRequests`, which reads a single owner's links.
///
/// Links live inside JSON columns, so `#Predicate` cannot filter on their
/// contents. The descriptors narrow to rows that hold any link at all and the
/// pure matcher decodes only those; observing the descriptors with `@Query`
/// keeps the result tracked as links are added and removed.
enum PullRequestLinkedOwnerLookup {
    /// Sidebar-visible threads holding at least one link. Drafts and archived
    /// threads are excluded to match `Project.aggregatedPullRequestLinks`.
    static var linkHoldingThreads: FetchDescriptor<AgentThread> {
        FetchDescriptor(
            predicate: #Predicate { thread in
                thread.archivedAt == nil && thread.isDraft == false && thread.linkedPullRequestsJSON != nil
            }
        )
    }

    static var linkHoldingProjects: FetchDescriptor<Project> {
        FetchDescriptor(
            predicate: #Predicate { project in
                project.linkedPullRequestsJSON != nil
            }
        )
    }

    /// Projects first, then threads, each group ordered by when the link was
    /// made. Owners are not deduplicated against each other: the same pull
    /// request may be linked from a project *and* its child threads, and each
    /// row selects a different sidebar item.
    static func owners(
        projects: [Project],
        threads: [AgentThread],
        linking identifier: PullRequestIdentifier
    ) -> [PullRequestLinkingOwner] {
        var projectRows: [LinkingRow] = []
        for project in projects {
            guard let link = project.linkedPullRequests.first(where: { $0.id == identifier }) else {
                continue
            }
            projectRows.append(LinkingRow(owner: .project(project), linkedAt: link.linkedAt))
        }
        var threadRows: [LinkingRow] = []
        for thread in threads {
            guard let link = thread.linkedPullRequests.first(where: { $0.id == identifier }) else {
                continue
            }
            threadRows.append(LinkingRow(owner: .thread(thread), linkedAt: link.linkedAt))
        }
        let ordered = projectRows.sorted(by: LinkingRow.isOrderedBefore)
            + threadRows.sorted(by: LinkingRow.isOrderedBefore)
        return ordered.map(\.owner)
    }

    /// Names only the kinds present, so a list of threads never claims to hold
    /// projects. Callers hide the section when `owners` is empty, so the
    /// threads-only wording doubles as the fallback.
    static func title(for owners: [PullRequestLinkingOwner]) -> String {
        let hasProjects = owners.contains(where: \.isProject)
        let hasThreads = owners.contains { !$0.isProject }
        switch (hasThreads, hasProjects) {
        case (true, true):
            return "Linked threads and projects"
        case (false, true):
            return "Linked projects"
        default:
            return "Linked threads"
        }
    }
}

private struct LinkingRow {
    let owner: PullRequestLinkingOwner
    let linkedAt: Date

    static func isOrderedBefore(_ lhs: LinkingRow, _ rhs: LinkingRow) -> Bool {
        if lhs.linkedAt != rhs.linkedAt {
            return lhs.linkedAt < rhs.linkedAt
        }
        return lhs.owner.displayName < rhs.owner.displayName
    }
}
