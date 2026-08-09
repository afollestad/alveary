import Foundation
import SwiftData

/// Where an address-feedback thread runs.
///
/// A ladder, cheapest first, because the top rungs decide before the caller has navigated:
///
/// 1. a thread that already links this pull request,
/// 2. a thread already checked out on its head branch,
/// 3. a fresh worktree on that branch in a local project for the repository,
/// 4. nothing, and the thread keeps its private workspace.
///
/// Rungs 1, 2, and 4 are local reads — a SwiftData fetch and a directory check — so they land in
/// front of the return and the thread's working directory is right the moment it exists. Rung 3 is
/// a network fetch plus a git checkout, so it runs behind the navigation and upgrades the thread
/// in place.
///
/// Every rung degrades rather than refuses. A thread with the wrong workspace can still read the
/// feedback, reply, and resolve; the instructions have it check `git status` and its branch before
/// editing, so a private workspace makes it say so rather than edit the wrong tree.
extension PullRequestAgenticThreadService {
    /// Rungs 1 and 2 — the ones that answer from local state alone. `headRefName` is nil when the
    /// caller had no detail yet, which skips rung 2 rather than guessing at a branch.
    func borrowedWorkspace(
        identifier: PullRequestIdentifier,
        headRefName: String?
    ) -> TaskWorkspaceDescriptor? {
        if let linked = linkedThreadWorkspace(identifier: identifier, headRefName: headRefName) {
            return linked
        }
        guard let headRefName else {
            return nil
        }
        return branchThreadWorkspace(headRefName: headRefName)
    }

    /// The deferred half of the ladder: rungs 1 and 2 again — the head branch may only have become
    /// known now — then rung 3. Silent on failure by design; the thread already has a workspace.
    func upgradeWorkspace(
        threadID: PersistentIdentifier,
        identifier: PullRequestIdentifier,
        headRefName: String?,
        threadName: String,
        preferredProjectID: PersistentIdentifier?
    ) async {
        if let borrowed = borrowedWorkspace(identifier: identifier, headRefName: headRefName) {
            try? lifecycleService.replaceTaskWorkspace(threadID: threadID, with: borrowed)
            return
        }
        guard let headRefName,
              let project = resolvedProject(for: identifier, preferredProjectID: preferredProjectID) else {
            return
        }
        await createWorkspace(
            threadID: threadID,
            projectPath: project.path,
            remoteName: project.remoteName,
            branch: headRefName,
            threadName: threadName
        )
    }

    /// Rung 3. `createFromBranch` checks the branch out rather than creating one, which is why
    /// rung 2 has to come first: git refuses a second worktree on a branch already checked out.
    private func createWorkspace(
        threadID: PersistentIdentifier,
        projectPath: String,
        remoteName: String?,
        branch: String,
        threadName: String
    ) async {
        guard let created = try? await worktreeManager.createFromBranch(
            projectPath: projectPath,
            threadName: threadName,
            branch: branch,
            remoteName: remoteName
        ) else {
            return
        }
        do {
            let descriptor = try taskWorkspaceOwnershipService.registerOwnedWorktree(
                at: created.path,
                sourceProjectPath: projectPath,
                grantedRoots: []
            )
            try lifecycleService.replaceTaskWorkspace(threadID: threadID, with: descriptor)
        } catch {
            // Nothing points at the checkout now, and an unowned worktree in the user's project is
            // worse than no upgrade at all. `branch: nil` removes the worktree and leaves the pull
            // request's head branch alone.
            try? await worktreeManager.remove(
                projectPath: projectPath,
                worktreePath: created.path,
                branch: nil
            )
        }
    }

    /// Rung 1. The link is the most precise evidence there is — the linked thread is usually the
    /// one that opened the pull request — so it outranks a branch match.
    private func linkedThreadWorkspace(
        identifier: PullRequestIdentifier,
        headRefName: String?
    ) -> TaskWorkspaceDescriptor? {
        let threads = (try? lifecycleService.modelContext.fetch(
            PullRequestLinkedOwnerLookup.linkHoldingThreads
        )) ?? []
        let linked = PullRequestLinkedOwnerLookup.owners(projects: [], threads: threads, linking: identifier)
            .compactMap { owner -> AgentThread? in
                guard case .thread(let thread) = owner else {
                    return nil
                }
                return thread
            }
        return linked.lazy
            .filter { Self.isOnBranch($0, headRefName: headRefName) }
            .compactMap(borrowableWorkspace(of:))
            .first
    }

    /// Rung 2. No `#Predicate` can reach `branch` alongside the visibility filter cheaply, so this
    /// narrows to sidebar-visible threads and matches in memory, as task-workspace retention does.
    private func branchThreadWorkspace(headRefName: String) -> TaskWorkspaceDescriptor? {
        let descriptor = FetchDescriptor<AgentThread>(
            predicate: #Predicate { thread in
                thread.archivedAt == nil && thread.isDraft == false
            }
        )
        let threads = (try? lifecycleService.modelContext.fetch(descriptor)) ?? []
        return threads.lazy
            .filter { $0.branch == headRefName }
            .compactMap(borrowableWorkspace(of:))
            .first
    }

    /// A thread naming a *different* branch has moved on from the pull request, so its checkout is
    /// not one of this head. A thread naming none — every Task thread — leaves the link as the only
    /// evidence, and the instructions have the agent confirm its branch before it edits anything.
    private static func isOnBranch(_ thread: AgentThread, headRefName: String?) -> Bool {
        guard let headRefName, let branch = thread.branch else {
            return true
        }
        return branch == headRefName
    }

    /// Borrowed, never owned: `.projectLocal` is the strategy whose cleanup does nothing, so
    /// deleting the address-feedback thread leaves the checkout the lender is still using.
    private func borrowableWorkspace(of thread: AgentThread) -> TaskWorkspaceDescriptor? {
        guard let root = thread.primaryWorkingDirectory,
              // A private workspace has no source project, so it is a scratch directory rather
              // than a checkout. This is also what stops the new thread from lending to itself
              // once linking has put it in rung 1's results: until the upgrade lands, the only
              // workspace it has is the private one.
              let sourceProjectPath = thread.sourceProjectCleanupPath,
              directoryExists(root) else {
            return nil
        }
        return TaskWorkspaceDescriptor(
            primaryRoot: root,
            ownershipStrategy: .projectLocal,
            sourceProjectPath: sourceProjectPath
        )
    }

    /// The pane's own project, when it has one and holds this repository; otherwise any project
    /// that does, by path so the pick is stable.
    private func resolvedProject(
        for identifier: PullRequestIdentifier,
        preferredProjectID: PersistentIdentifier?
    ) -> Project? {
        let repository = identifier.nameWithOwner.lowercased()
        let projects = ((try? lifecycleService.modelContext.fetch(FetchDescriptor<Project>())) ?? [])
            .filter { Self.repository(of: $0)?.lowercased() == repository }
        if let preferredProjectID,
           let preferred = projects.first(where: { $0.persistentModelID == preferredProjectID }) {
            return preferred
        }
        return projects.sorted { $0.path < $1.path }.first
    }

    /// `githubRepository` is written once at import and never refreshed, so a project whose remote
    /// was set afterwards is only reachable through the derived fallback.
    private static func repository(of project: Project) -> String? {
        project.githubRepository ?? project.gitRemote.flatMap(Project.parseGitHubRepository(from:))
    }
}
