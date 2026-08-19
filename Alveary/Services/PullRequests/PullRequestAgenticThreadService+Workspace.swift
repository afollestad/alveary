import Foundation
import SwiftData

/// Where an `.addressFeedback` thread runs.
///
/// A ladder, cheapest first:
///
/// 1. a thread that already links this pull request,
/// 2. a thread already checked out on its head branch,
/// 3. a fresh worktree on that branch in a local project for the repository.
///
/// Rungs 1 and 2 are local reads — a SwiftData fetch and a directory check — so a *provisional*
/// borrow lands in front of the return and the thread has a working directory the moment it exists.
/// Rung 3 is a network fetch plus a git command, so it runs behind, and so does the branch probe
/// that decides whether the provisional borrow was right.
///
/// ## This ladder refuses rather than degrading past its last rung
///
/// There is no fourth rung. Addressing feedback means editing files and pushing them, so a thread
/// left on a private scratch directory could not do the job at all — it would burn a turn
/// discovering that. When nothing can be borrowed and no project holds the repository, `start`
/// throws `StartError.projectMissing` before creating anything, and the pane says so.
///
/// ## Why a borrow is verified rather than trusted
///
/// `isOnBranch` can only compare against `thread.branch`, which is nil for every Task thread — so
/// rung 1 accepting a lender on the strength of the link alone would hand the agent whatever that
/// lender happens to have checked out. Only git knows, and asking it is a subprocess, so the
/// question is asked behind the return and a wrong guess is corrected in place. A borrowed tree is
/// never `git checkout`-ed: the lender is still using it.
extension PullRequestAgenticThreadService {
    /// Rungs 1 and 2, first match only, from local state alone — the provisional borrow `start`
    /// seeds the thread with. `headRefName` is nil when the caller had no detail yet, which skips
    /// rung 2 rather than guessing at a branch.
    func borrowedWorkspace(
        identifier: PullRequestIdentifier,
        headRefName: String?
    ) -> TaskWorkspaceDescriptor? {
        borrowableWorkspaces(identifier: identifier, headRefName: headRefName).first
    }

    /// Every rung-1 and rung-2 candidate, in ladder order, so the deferred half can keep asking
    /// after a probe rejects one. Deduplicated by root: a linked thread that is also on the head
    /// branch appears on both rungs.
    func borrowableWorkspaces(
        identifier: PullRequestIdentifier,
        headRefName: String?
    ) -> [TaskWorkspaceDescriptor] {
        var seenRoots: Set<String> = []
        var candidates: [TaskWorkspaceDescriptor] = []
        for descriptor in linkedThreadWorkspaces(identifier: identifier, headRefName: headRefName)
            + branchThreadWorkspaces(headRefName: headRefName) where seenRoots.insert(descriptor.primaryRoot).inserted {
            candidates.append(descriptor)
        }
        return candidates
    }

    /// The deferred half: confirm the seeded borrow, or find one that survives the probe, or cut
    /// the thread its own worktree. Silent on failure by design — the thread already has somewhere
    /// to run, and the instructions have the agent check its branch before it edits anything.
    func settleCheckout(_ work: DeferredWork, headRefName: String?) async {
        let seededBorrow = work.seededBorrow
        if let seededBorrow, await isOnHeadBranch(seededBorrow, headRefName: headRefName) {
            return
        }
        // The head branch may only have become known now, so the local rungs get a second look —
        // and this time every candidate is probed before it is kept.
        for candidate in borrowableWorkspaces(identifier: work.identifier, headRefName: headRefName)
        where candidate != seededBorrow {
            guard await isOnHeadBranch(candidate, headRefName: headRefName) else {
                continue
            }
            try? lifecycleService.replaceTaskWorkspace(threadID: work.threadID, with: candidate)
            return
        }
        guard let headRefName,
              let project = resolvedProject(
                  for: work.identifier,
                  preferredProjectID: work.preferredProjectID
              ) else {
            // Nothing better exists, so whatever the thread already has stays — a wrong-branch
            // borrow included, since it is at least a checkout of this repository.
            //
            // The pre-flight rules out "no borrow and no project", but not this: a detail fetch
            // that failed leaves `headRefName` nil, and then even a matching project has no branch
            // to check out. That thread keeps its private workspace, and the instructions' own
            // `git status` check is what stops the agent editing on the strength of it.
            return
        }
        await createWorkspace(
            threadID: work.threadID,
            projectPath: project.path,
            remoteName: project.remoteName,
            branch: headRefName,
            threadName: work.threadName
        )
    }

    /// True when the tree is on the pull request's head branch — or when nothing can be proven.
    /// An unreadable branch or an unknown head leaves a probably-right checkout in place, because
    /// discarding one on a failed probe trades a likely-correct tree for a certainly-worse one.
    private func isOnHeadBranch(
        _ descriptor: TaskWorkspaceDescriptor,
        headRefName: String?
    ) async -> Bool {
        guard let headRefName else {
            return true
        }
        guard let branch = await currentBranch(descriptor.primaryRoot) else {
            return true
        }
        return branch == headRefName
    }

    /// Rung 3. `createFromBranch` checks the branch out rather than creating one, which is why the
    /// borrow rungs come first: git refuses a second worktree on a branch already checked out.
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
    private func linkedThreadWorkspaces(
        identifier: PullRequestIdentifier,
        headRefName: String?
    ) -> [TaskWorkspaceDescriptor] {
        let threads = (try? lifecycleService.modelContext.fetch(
            PullRequestLinkedOwnerLookup.linkHoldingThreads
        )) ?? []
        return PullRequestLinkedOwnerLookup.owners(projects: [], threads: threads, linking: identifier)
            .compactMap { owner -> AgentThread? in
                guard case .thread(let thread) = owner else {
                    return nil
                }
                return thread
            }
            .filter { Self.isOnBranch($0, headRefName: headRefName) }
            .compactMap(borrowableWorkspace(of:))
    }

    /// Rung 2. No `#Predicate` can reach `branch` alongside the visibility filter cheaply, so this
    /// narrows to sidebar-visible threads and matches in memory, as task-workspace retention does.
    private func branchThreadWorkspaces(headRefName: String?) -> [TaskWorkspaceDescriptor] {
        guard let headRefName else {
            return []
        }
        let descriptor = FetchDescriptor<AgentThread>(
            predicate: #Predicate { thread in
                thread.archivedAt == nil && thread.isDraft == false
            }
        )
        let threads = (try? lifecycleService.modelContext.fetch(descriptor)) ?? []
        return threads
            .filter { $0.branch == headRefName }
            .compactMap(borrowableWorkspace(of:))
    }

    /// A thread naming a *different* branch has moved on from the pull request, so its checkout is
    /// not one of this head. A thread naming none — every Task thread — passes here and is settled
    /// by the git probe instead; this filter is only the cheap half.
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
              // once linking has put it in rung 1's results: until the checkout settles, the only
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
    /// that does, by path so the pick is stable. Internal because the pre-flight refusal in
    /// `start` asks the same question before it creates anything.
    func resolvedProject(
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
