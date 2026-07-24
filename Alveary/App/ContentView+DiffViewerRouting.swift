import Foundation
import SwiftData

/// Root selection reduced to the identity the Diff Viewer actually routes on.
///
/// Built from selection tokens only — no SwiftData property reads — so the
/// click-to-highlight frame never waits on a fetch. `Settings` normalizes to the
/// same route as its preserved bookmark, so opening Settings from a project does
/// not re-route the pane.
enum DiffViewerRoutingSelection: Equatable {
    case none
    case thread(PersistentIdentifier)
    case project(String)

    init(selection: SidebarItem?, previousSelection: AppState.SidebarBookmark?) {
        switch selection {
        case .thread(let thread):
            self = .thread(thread.persistentModelID)
        case .project(let project):
            self = .project(project.path)
        case .settings:
            switch previousSelection {
            case .threadId(let threadID):
                self = .thread(threadID)
            case .projectPath(let path):
                self = .project(path)
            case .skills, .mcp, .scheduled, .archived, nil:
                self = .none
            }
        case .skills, .mcp, .scheduled, .archived, nil:
            self = .none
        }
    }
}

/// The complete set of inputs that decide what the Diff Viewer shows.
struct DiffViewerRoutingKey: Equatable {
    let selection: DiffViewerRoutingSelection
    let scope: DiffViewerSwitchScope
    let draftRevision: UInt64
}

/// Runs one Diff Viewer route with an injected suspension gate.
///
/// The gate is `Task.yield()` in production; tests replace it to prove that target
/// resolution and pane work start only after the selected frame has painted, and
/// that a superseded key applies nothing.
@MainActor
struct DiffViewerRouteRunner {
    let isCurrent: @MainActor (DiffViewerRoutingKey) -> Bool
    let resolveTarget: @MainActor (DiffViewerRoutingSelection) -> DiffViewerSwitchTarget?
    let clear: @MainActor () -> Void
    let applyTarget: @MainActor (DiffViewerSwitchTarget, DiffViewerSwitchScope) async -> Void
    let suspendBeforeResolving: @MainActor () async -> Void

    func run(key: DiffViewerRoutingKey) async {
        await suspendBeforeResolving()
        guard isCurrent(key) else {
            return
        }

        let target = resolveTarget(key.selection)

        guard isCurrent(key) else {
            return
        }

        guard let target else {
            clear()
            return
        }

        await applyTarget(target, key.scope)
    }
}

extension ContentView {
    var diffViewerRoutingSelection: DiffViewerRoutingSelection {
        DiffViewerRoutingSelection(
            selection: appState.selectedSidebarItem,
            previousSelection: appState.previousSelection
        )
    }

    var diffViewerSwitchScope: DiffViewerSwitchScope {
        // The toolbar diff summary must stay fresh even while the pane is
        // hidden; only the heavy pane payload waits for the pane to show.
        isDiffViewerRendered ? .full : .toolbarStatsOnly
    }

    var diffViewerRoutingKey: DiffViewerRoutingKey {
        DiffViewerRoutingKey(
            selection: diffViewerRoutingSelection,
            scope: diffViewerSwitchScope,
            draftRevision: diffViewerDraftRefreshRevision
        )
    }

    func routeDiffViewer(key: DiffViewerRoutingKey) async {
        await DiffViewerRouteRunner(
            isCurrent: isDiffViewerRoutingKeyCurrent,
            resolveTarget: resolvedDiffViewerTarget(for:),
            clear: { diffViewModel.clear() },
            applyTarget: { target, scope in
                await diffViewModel.switchToTarget(target, scope: scope)
            },
            // Let the new selection paint before any SwiftData or Git work starts.
            suspendBeforeResolving: { await Task.yield() }
        ).run(key: key)
    }

    /// `Task.isCancelled` covers the draft revision, which only ever changes by
    /// restarting the keyed task; selection and scope are read live from
    /// reference-backed state so a resumed job cannot act on a stale route.
    func isDiffViewerRoutingKeyCurrent(_ key: DiffViewerRoutingKey) -> Bool {
        guard !Task.isCancelled else {
            return false
        }
        return key.selection == diffViewerRoutingSelection && key.scope == diffViewerSwitchScope
    }

    func resolvedDiffViewerTarget(for selection: DiffViewerRoutingSelection) -> DiffViewerSwitchTarget? {
        switch selection {
        case .none:
            return nil
        case .thread(let threadID):
            guard let thread = uiModelContext.resolveThread(id: threadID),
                  thread.archivedAt == nil else {
                return nil
            }
            if thread.effectiveMode == .project, thread.isDraft, let project = thread.project {
                return diffViewerTarget(for: project)
            }
            return DiffViewerSwitchTarget.forThread(
                thread,
                candidateConversationIDs: liveDiffViewerConversationIDs(for: thread)
            )
        case .project(let path):
            guard let project = resolveProject(path: path) else {
                return nil
            }
            return diffViewerTarget(for: project)
        }
    }

    private func diffViewerTarget(for project: Project) -> DiffViewerSwitchTarget {
        let threads = liveDiffViewerThreads(for: project)
        return DiffViewerSwitchTarget.forProject(
            project,
            candidateThreads: threads,
            candidateConversationIDs: liveDiffViewerConversationIDs(for: project, threads: threads)
        )
    }

    private func liveDiffViewerThreads(for project: Project) -> [AgentThread] {
        let projectPath = project.path
        var descriptor = FetchDescriptor<AgentThread>(
            predicate: #Predicate { thread in
                thread.archivedAt == nil && thread.isDraft == false && thread.project?.path == projectPath
            }
        )
        // The project route reads every candidate thread's conversations right after this
        // fetch, so prefetching keeps that batched instead of one fault per thread.
        descriptor.relationshipKeyPathsForPrefetching = [\.conversations]
        return ((try? uiModelContext.fetch(descriptor)) ?? []).filter { $0.effectiveMode == .project }
    }

    private func liveDiffViewerConversationIDs(for thread: AgentThread) -> Set<String> {
        let threadID = thread.persistentModelID
        let descriptor = FetchDescriptor<Conversation>(
            predicate: #Predicate { conversation in
                conversation.thread?.persistentModelID == threadID
            }
        )
        return Set(((try? uiModelContext.fetch(descriptor)) ?? []).map(\.id))
    }

    /// Reads the relationship prefetched by `liveDiffViewerThreads(for:)` instead of running
    /// a conversation fetch per candidate thread. A project-scoped conversation predicate
    /// cannot replace it: `conversation.thread?.project?.path` is a nested relationship
    /// keypath the store cannot translate, and it traps the fetch at runtime.
    private func liveDiffViewerConversationIDs(for project: Project, threads: [AgentThread]) -> Set<String> {
        let projectPath = project.path
        return Set(
            threads
                .filter { $0.worktreePath == nil || $0.worktreePath == projectPath }
                .flatMap { $0.conversations.map(\.id) }
        )
    }
}
