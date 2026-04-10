# Part 4b: Sidebar

SidebarViewModel, SidebarView, sidebar selection binding. Continues from Part 4a.

## Implementation Status

- [x] `SidebarViewModel` is implemented in the repo, including project import, thread creation, archive/restore/delete actions, aggregate thread-status rules, sidebar error state, and focused unit coverage.
- [x] `SidebarView` is implemented in the repo, and snapshot coverage now includes a populated sidebar state.

## SidebarViewModel

Drives the left pane. Loads projects and threads from SwiftData, provides thread status:

```swift
enum ThreadStatus: Sendable {  // Skep/ViewModels/SidebarViewModel.swift
    case busy       // At least one conversation is actively processing
    case idle       // Awaiting input
    case stopped    // No live activity to show (no dot in sidebar)
    case error      // Agent encountered an error (red dot in sidebar)
    case archived   // Thread is archived (dimmed)
}

@MainActor @Observable
class SidebarViewModel {  // Skep/ViewModels/SidebarViewModel.swift
    private let agentsManager: any AgentsManager
    private let modelContext: ModelContext
    private let shell: ShellRunner
    private let gitHubCLI: GitHubCLIService
    private let worktreeManager: WorktreeManager
    private let settingsService: SettingsService
    private var statusObserver: NSObjectProtocol?
    /// Shared banner state for sidebar-triggered failures, including project/thread
    /// creation plus archive/restore/delete actions.
    private(set) var sidebarError: String?
    /// Incremented on every agent status change (via NotificationCenter).
    /// SidebarView reads this to create an @Observable dependency so the
    /// view re-evaluates when any agent's status changes.
    private(set) var statusVersion: Int = 0

    init(agentsManager: any AgentsManager, modelContext: ModelContext,
         shell: ShellRunner, gitHubCLI: GitHubCLIService,
         worktreeManager: WorktreeManager, settingsService: SettingsService) {
        self.agentsManager = agentsManager
        self.modelContext = modelContext
        self.shell = shell
        self.gitHubCLI = gitHubCLI
        self.worktreeManager = worktreeManager
        self.settingsService = settingsService
        statusObserver = NotificationCenter.default.addObserver(
            forName: .agentStatusChanged, object: nil, queue: .main
        ) { [weak self] _ in
            self?.statusVersion += 1
        }
    }

    deinit {
        if let statusObserver {
            NotificationCenter.default.removeObserver(statusObserver)
        }
    }

    /// This VM writes through its injected transient `ModelContext`, so incoming
    /// `Project` / `AgentThread` values are treated as identity handles only. Re-resolve
    /// them here before mutating relationships or lifecycle fields.
    private func requireProject(_ project: Project) throws -> Project {
        let path = project.path
        let descriptor = FetchDescriptor<Project>(predicate: #Predicate { $0.path == path })
        guard let dbProject = try modelContext.fetch(descriptor).first else {
            throw AgentError.spawnFailed("Project no longer exists")
        }
        return dbProject
    }

    private func requireThread(_ thread: AgentThread) throws -> AgentThread {
        guard let dbThread = modelContext.model(for: thread.persistentModelID) as? AgentThread else {
            throw AgentError.spawnFailed("Thread no longer exists")
        }
        return dbThread
    }

    // SwiftData queries drive the list; this VM handles actions.
    // See Part 3a (Projects, Thread Creation, Thread Archiving) for the full
    // step-by-step flows these methods implement.

    /// See "Project Creation Flow" in Part 3a.
    /// 1. Run `git rev-parse --show-toplevel` to confirm repo and get root path.
    /// 2. Resolve the preferred remote once (upstream remote → sole remote → `origin`
    ///    only as ambiguity-breaking fallback), then read `git remote get-url <remoteName>`.
    /// 3. Parse `.skep.json` via `SkepProjectConfig(projectPath:)`.
    /// 4. Check `gh auth status` only when the CLI is installed.
    /// 5. Prefer `git symbolic-ref refs/remotes/<remoteName>/HEAD`; fall back to the current local branch.
    /// 6. Insert `Project` into modelContext with path, name, `remoteName`, remote URL, branch, base ref, and GitHub info.
    /// The returned project carries stable identity for the caller, but callers should
    /// resolve it again in their own UI read context before storing it in navigation state.
    func createProject(path: String) async throws -> Project {
        // Implementation follows the 7-step flow in Part 3a > Project Creation Flow.
        // Uses ShellRunner for git commands and GitHubCLIService only when `gh` is available.
    }

    /// Creates an `AgentThread` under the project. Does NOT spawn the agent —
    /// that happens when the user sends the first message (see Thread Creation Flow in Part 3a).
    /// Sets default `permissionMode` and `effort` from AppSettings. Creates an initial
    /// main `Conversation` and seeds its provider from the caller's chosen default.
    /// The returned thread carries stable identity for the caller, but callers should
    /// resolve that identity again in their own UI read context before storing it in
    /// long-lived navigation state.
    func createThread(project: Project, provider: String, permissionMode: String) async throws -> AgentThread {
        let dbProject = try requireProject(project)
        let thread = AgentThread()
        thread.name = "New thread"
        thread.permissionMode = permissionMode
        thread.effort = settingsService.current.effort
        thread.useWorktree = settingsService.current.createWorktreeByDefault
        thread.project = dbProject
        let conversation = Conversation()
        conversation.isMain = true
        conversation.provider = provider
        conversation.thread = thread
        modelContext.insert(thread)
        modelContext.insert(conversation)
        try modelContext.save()
        return thread
    }

    func presentSidebarError(_ error: Error) {
        sidebarError = error.localizedDescription
    }

    func dismissSidebarError() {
        sidebarError = nil
    }

    /// Shared precondition for thread lifecycle mutations that require the thread to be
    /// fully dormant afterward. Archive and delete both reuse this helper so the manager-
    /// owned destructive-teardown order (kill → await exit → session cleanup) stays in one place.
    /// Always attempt every conversation even if one teardown fails so a multi-conversation
    /// thread cannot be left partially live just because the first failure short-circuited the loop.
    private func quiesceThreadConversations(_ thread: AgentThread) async throws {
        let conversationIds = thread.conversations.map(\.id)
        var firstError: Error?
        for id in conversationIds {
            do {
                try await agentsManager.destroyRuntime(conversationId: id)
            } catch {
                if firstError == nil {
                    firstError = error
                }
            }
        }
        if let firstError {
            throw firstError
        }
    }

    /// See "Thread Archiving and Worktree Cleanup > Archive" in Part 3a.
    /// 1. Destroy all runtimes for the thread's conversations.
    /// 2. Let `AgentsManager.destroyRuntime()` own the exit wait + session cleanup.
    /// 3. Set `archivedAt` timestamp. Worktree is preserved on disk.
    /// The caller may optimistically rehome selection / preserved settings context to the
    /// parent project before starting archive; if any later step fails, that caller must
    /// restore the previous selection/bookmark because the thread record still exists even
    /// though its runtime may already have been quiesced.
    func archiveThread(_ thread: AgentThread) async throws {
        let dbThread = try requireThread(thread)
        try await quiesceThreadConversations(dbThread)
        dbThread.archivedAt = Date()
        try modelContext.save()
    }

    /// See "Thread Archiving and Worktree Cleanup > Restore" in Part 3a.
    /// Clear `archivedAt`. Worktree is already on disk. The next user message
    /// uses the existing Conversation identity and normal spawn path, but it
    /// intentionally starts a fresh provider session because archive removed the
    /// session-map entry.
    func restoreThread(_ thread: AgentThread) async throws {
        let dbThread = try requireThread(thread)
        dbThread.archivedAt = nil
        try modelContext.save()
    }

    /// See "Thread Archiving and Worktree Cleanup > Delete" in Part 3a.
    /// 1. Destroy all runtimes.
    /// 2. Let `AgentsManager.destroyRuntime()` own the exit wait + session cleanup.
    /// 3. Remove the current worktree + branch, plus any deferred orphan branches,
    ///    via WorktreeManager.
    /// 4. Delete thread from SwiftData (cascades to conversations and events).
    /// If worktree cleanup fails, abort the delete and keep the thread record so the
    /// user can retry without losing the only durable pointer to the worktree path.
    /// The caller (SidebarView action handler) must move `appState.selectedSidebarItem`
    /// to the parent project if the deleted thread was selected. After a successful
    /// delete, it also removes the thread's `appState.selectedConversationIDs` entry
    /// so the app-session tab map does not retain orphaned per-thread UI state.
    /// Because selection/bookmark rewrites happen before the delete attempt, the
    /// caller must snapshot and restore those values if deletion fails and the thread
    /// record survives.
    func deleteThread(_ thread: AgentThread) async throws {
        let dbThread = try requireThread(thread)
        try await quiesceThreadConversations(dbThread)
        guard let projectPath = dbThread.project?.path else {
            throw AgentError.spawnFailed("Thread is missing its parent project")
        }
        for pendingCleanupBranch in dbThread.pendingCleanupBranches
        where pendingCleanupBranch != dbThread.branch {
            try await worktreeManager.deleteBranch(
                projectPath: projectPath,
                branch: pendingCleanupBranch
            )
        }
        let requiresFullWorktreeCleanup = dbThread.useWorktree && dbThread.hasCompletedInitialSetup
        if requiresFullWorktreeCleanup {
            guard let worktreePath = dbThread.worktreePath,
                  let branch = dbThread.branch else {
                throw AgentError.spawnFailed("Thread is missing worktree cleanup metadata needed for deletion")
            }
            try await worktreeManager.remove(
                projectPath: projectPath,
                worktreePath: worktreePath,
                branch: branch
            )
        } else if dbThread.worktreePath != nil || dbThread.branch != nil {
            guard let worktreePath = dbThread.worktreePath else {
                throw AgentError.spawnFailed("Thread is missing worktree metadata needed for deletion cleanup")
            }
            try await worktreeManager.remove(
                projectPath: projectPath,
                worktreePath: worktreePath,
                branch: dbThread.branch
            )
        }
        modelContext.delete(dbThread)
        try modelContext.save()
    }

    /// Synchronous — reads the lock-protected status snapshot from AgentsManager.
    /// No async needed, safe to call during SwiftUI rendering.
    func threadStatus(for thread: AgentThread) -> ThreadStatus {
        if thread.archivedAt != nil { return .archived }
        var hasError = false
        var hasStopped = false
        var hasIdle = false
        for conversation in thread.conversations {
            switch agentsManager.status(for: conversation.id) {
            case .busy: return .busy      // Any busy → thread is busy
            case .error: hasError = true
            case .stopped: hasStopped = true
            case .idle: hasIdle = true
            case .neutral: break          // No live status entry yet — e.g. never spawned or post-relaunch before respawn
            }
        }
        if hasError { return .error }     // Any error (no busy) → thread has error
        if hasIdle { return .idle }       // Any idle → awaiting input
        if hasStopped { return .stopped } // All stopped → thread stopped
        return .stopped                   // All neutral (no live process/status yet) → no dot
    }
}
```

**Used by**: `SidebarView` (left pane).

---

## SidebarView Selection Binding

The sidebar uses `List(selection:)` to bind the selected item to `appState.selectedSidebarItem`. Each row uses `.tag()` matching the `SidebarItem` enum case. This gives native selection highlighting and keyboard navigation:

```swift
struct SidebarView: View {  // Skep/Views/Sidebar/SidebarView.swift
    let viewModel: SidebarViewModel
    @Bindable var appState: AppState
    @Query private var projects: [Project]
    /// Tracks which projects are expanded. Separate from List selection to avoid
    /// the DisclosureGroup + List(selection:) interaction conflict on macOS.
    @State private var expandedProjects: Set<String> = []
    @State private var expandedArchivedProjects: Set<String> = []
    @State private var pendingDeleteThread: AgentThread?

    var body: some View {
        // Touch the version counter to observe agent status changes.
        let _ = viewModel.statusVersion
        VStack(spacing: 0) {
            if let sidebarError = viewModel.sidebarError {
                InlineBanner(message: sidebarError, severity: .error) {
                    viewModel.dismissSidebarError()
                }
            }
            List(selection: $appState.selectedSidebarItem) {
                Section {
                    Label("Skills", systemImage: "puzzlepiece.extension")
                        .tag(SidebarItem.skills)
                    Label("MCP", systemImage: "server.rack")
                        .tag(SidebarItem.mcp)
                }
                // Use @State expansion tracking instead of DisclosureGroup to avoid
                // the macOS conflict where .tag() on a DisclosureGroup label fails to
                // register as a List selection target (tapping the label toggles expansion
                // instead of setting the selection). With manual expansion, the project
                // row is a plain selectable row with .tag(), and threads are conditionally
                // rendered below it.
                Section("Projects") {
                    ForEach(projects) { project in
                        ProjectRow(project: project, isExpanded: expandedProjects.contains(project.path)) {
                            if expandedProjects.contains(project.path) {
                                expandedProjects.remove(project.path)
                            } else {
                                expandedProjects.insert(project.path)
                            }
                        }
                        .tag(SidebarItem.project(project))
                        if expandedProjects.contains(project.path) {
                            ForEach(project.threads.filter { $0.archivedAt == nil }) { thread in
                                ThreadRow(thread: thread, status: viewModel.threadStatus(for: thread))
                                .tag(SidebarItem.thread(thread))
                                .padding(.leading, 16)
                                .contextMenu {
                                    Button("Archive") {
                                        Task {
                                            let previousSelectedItem = appState.selectedSidebarItem
                                            let previousBookmark = appState.previousSelection
                                            // Archived rows are not selectable. If the user archives
                                            // the currently selected thread, move selection back to the
                                            // parent project before the thread leaves the active list.
                                            if case .thread(let selected) = appState.selectedSidebarItem,
                                               selected.persistentModelID == thread.persistentModelID,
                                               let project = thread.project {
                                                appState.selectedSidebarItem = .project(project)
                                            }
                                            // Settings preserves the last non-settings selection in
                                            // `previousSelection`. If that preserved thread is archived
                                            // while Settings is open, redirect the bookmark to the
                                            // parent project so dismiss/Cmd+N/shared diff context stop
                                            // treating the archived thread as active.
                                            if case .threadId(let bookmarkedId) = appState.previousSelection,
                                               bookmarkedId == thread.persistentModelID,
                                               let project = thread.project {
                                                appState.previousSelection = .projectPath(project.path)
                                            }
                                            do {
                                                try await viewModel.archiveThread(thread)
                                            } catch {
                                                appState.selectedSidebarItem = previousSelectedItem
                                                appState.previousSelection = previousBookmark
                                                viewModel.presentSidebarError(error)
                                            }
                                        }
                                    }
                                    Button("Delete", role: .destructive) {
                                        pendingDeleteThread = thread
                                    }
                                }
                        }

                            let archivedThreads = project.threads.filter { $0.archivedAt != nil }
                            if !archivedThreads.isEmpty {
                                Button {
                                    if expandedArchivedProjects.contains(project.path) {
                                        expandedArchivedProjects.remove(project.path)
                                    } else {
                                        expandedArchivedProjects.insert(project.path)
                                    }
                                } label: {
                                    Label(
                                        "Archived",
                                        systemImage: expandedArchivedProjects.contains(project.path)
                                            ? "chevron.down"
                                            : "chevron.right"
                                    )
                                }
                                .buttonStyle(.plain)
                                .padding(.leading, 16)

                                if expandedArchivedProjects.contains(project.path) {
                                    ForEach(archivedThreads) { thread in
                                        ThreadRow(thread: thread, status: .archived)
                                            .padding(.leading, 16)
                                            .contextMenu {
                                                Button("Restore") {
                                                    Task {
                                                        do {
                                                            try await viewModel.restoreThread(thread)
                                                            expandedProjects.insert(project.path)
                                                        } catch {
                                                            viewModel.presentSidebarError(error)
                                                        }
                                                    }
                                                }
                                                Button("Delete", role: .destructive) {
                                                    pendingDeleteThread = thread
                                                }
                                            }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        .onAppear {
            syncExpansionWithSelection(appState.selectedSidebarItem)
        }
        .onChange(of: appState.selectedSidebarItem) { _, item in
            syncExpansionWithSelection(item)
        }
        .confirmationDialog(
            "Delete thread?",
            isPresented: Binding(
                get: { pendingDeleteThread != nil },
                set: { if !$0 { pendingDeleteThread = nil } }
            ),
            presenting: pendingDeleteThread
        ) { thread in
            Button("Delete", role: .destructive) {
                Task { await confirmDelete(thread) }
            }
            Button("Cancel", role: .cancel) {
                pendingDeleteThread = nil
            }
        } message: { thread in
            Text("This permanently deletes \(thread.name) and removes its worktree and branch if present.")
        }
    }

    private func syncExpansionWithSelection(_ item: SidebarItem?) {
        switch item {
        case .project(let project):
            expandedProjects.insert(project.path)
        case .thread(let thread):
            if let projectPath = thread.project?.path {
                expandedProjects.insert(projectPath)
            }
        default:
            break
        }
    }

    private func confirmDelete(_ thread: AgentThread) async {
        pendingDeleteThread = nil
        let previousSelectedItem = appState.selectedSidebarItem
        let previousBookmark = appState.previousSelection
        // Move selection to the parent project BEFORE delete so the middle pane keeps
        // valid project context instead of pointing at a soon-to-be-deleted thread.
        if case .thread(let selected) = appState.selectedSidebarItem,
           selected.persistentModelID == thread.persistentModelID {
            appState.selectedSidebarItem = thread.project.map(SidebarItem.project)
        }
        // Mirror the same protection for Settings' preserved bookmark so
        // dismiss/app-wide commands/shared diff state fall back to the surviving
        // project instead of the soon-to-be-deleted thread.
        if case .threadId(let bookmarkedId) = appState.previousSelection,
           bookmarkedId == thread.persistentModelID,
           let project = thread.project {
            appState.previousSelection = .projectPath(project.path)
        }
        do {
            try await viewModel.deleteThread(thread)
            appState.selectedConversationIDs.removeValue(forKey: thread.persistentModelID)
        } catch {
            appState.selectedSidebarItem = previousSelectedItem
            appState.previousSelection = previousBookmark
            viewModel.presentSidebarError(error)
        }
    }
}
```

**Key**: `SidebarItem` conforms to `Hashable` (defined in `part1b-data-and-services.md`). `.tag()` values must use the same `SidebarItem` enum cases that `MiddlePane` switches on. `List(selection:)` provides native selection highlighting and arrow-key navigation on macOS. `ProjectRow` shows the project name with a chevron toggle button that adds/removes the project path from `expandedProjects`. The toggle is a separate button in the row, not the row itself — tapping the row selects the project (opens project settings), tapping the chevron expands/collapses threads.

Programmatic selection changes still need the same visibility guarantees as direct row taps. `Cmd+N`, Settings dismiss, create-project/create-thread flows, and archive/delete fallbacks can all change `appState.selectedSidebarItem` without touching the chevron buttons, so `SidebarView` mirrors that selection into `expandedProjects` via `syncExpansionWithSelection(_:)`. Without that, the app can select a thread or project that remains hidden inside a collapsed group.

Archived threads are rendered as a second collapsible group per project, tracked independently via `expandedArchivedProjects`. Archived rows are dimmed, non-selectable chat history entries that expose restore/delete actions.

Restoring an archived thread should also insert its parent project path into `expandedProjects` after success so the row does not appear to vanish from a collapsed Archived section into a still-collapsed active section.

Project/thread creation failures and thread-action failures (archive, restore, delete) are surfaced through `SidebarViewModel.sidebarError`, rendered as an `InlineBanner` above the list. This keeps sidebar-triggered errors from disappearing while reusing the same UX for both app commands and row context-menu actions.

Delete remains the one destructive sidebar action that goes through a view-owned confirmation step first: the context menu only sets `pendingDeleteThread`, and the actual `deleteThread(...)` call runs from the confirmation dialog's destructive button.

When Settings is open, sidebar thread actions must reconcile `AppState.previousSelection` in addition to `selectedSidebarItem`. Archiving or deleting a bookmarked thread rewrites the preserved selection to its parent project before the action so Settings dismiss, Cmd+N routing, and the shared diff viewer fall back to a safe context instead of a thread that may disappear. If either action fails, the caller restores the original selection/bookmark so the still-live thread remains reachable.

**Unit tests for SidebarViewModel** (inject `MockAgentsManager`, `MockShellRunner`, `MockGitHubCLIService`, `MockWorktreeManager`, `InMemorySettingsService` + in-memory `ModelContext`): cover all public methods with standard happy-path and error tests. Non-obvious:
- `createProject()` persists the resolved `remoteName` alongside `gitRemote`, and uses that remote for base-ref detection instead of hardcoding `origin`
- `createProject()` falls back gracefully when the chosen remote has no HEAD, and allows local-only repositories (nil `remoteName`) instead of failing project creation
- `createProject()` parses `.skep.json` via `SkepProjectConfig` and stores project name from last path component
- `createProject()` treats missing `gh` as disconnected instead of failing the import flow
- `createProject()` sets `githubConnected` based on `gh auth status` only when the CLI exists
- `createProject()` returns the inserted `Project` so command handlers can select it immediately after creation
- `createThread()` reads default `effort` from `SettingsService.current.effort` (not hardcoded to `"medium"`)
- `createThread()` returns the inserted `AgentThread` so toolbar/menu flows can select the new thread immediately
- `createThread()` stores provider on the initial main `Conversation`, not on `AgentThread`, so side chats can diverge later without a thread-level provider field
- `createThread()` resolves the passed `Project` inside the VM's injected `ModelContext` before attaching the new thread, so it never links a relationship across contexts
- `presentSidebarError()` / `dismissSidebarError()` drive the shared inline banner for sidebar actions and menu-command create flows
- Archive, restore, and delete failures are surfaced through the same inline banner instead of being swallowed by `try?`
- Active-thread archive callers rehome `selectedSidebarItem` / `previousSelection` before the action, then restore them if archive fails so the UI does not lose context for a thread record that still exists even if runtime state was already quiesced
- `archiveThread()` waits for `AgentsManager.destroyRuntime()` to finish for every conversation before setting `archivedAt`, so archived threads never show as dormant while a child is still winding down or while a stale session binding is still being removed
- `quiesceThreadConversations()` still attempts later `destroyRuntime()` calls after an earlier one fails, then rethrows the first error after the full pass so multi-conversation threads do not remain partially live because teardown short-circuited early
- `restoreThread()` clears `archivedAt` — no process restart (user sends a message to trigger respawn)
- Archive/restore/delete re-resolve the passed `AgentThread` in the VM's own `ModelContext` before mutating it, so sidebar actions stay safe even when selection models came from a different SwiftUI read context
- `archiveThread()` and `deleteThread()` both flow through `quiesceThreadConversations()`, so destructive teardown ordering has exactly one owner in `AgentsManager`
- `deleteThread()` deletes every deferred branch in `pendingCleanupBranches` except the thread's current live `branch`, then removes the current worktree/branch when present
- `deleteThread()` fails fast when the parent project is missing or a completed worktree-backed thread is missing branch/worktree cleanup metadata, instead of falling back to an empty project path or silently skipping cleanup the plan said was required
- `deleteThread()` aborts and preserves the SwiftData thread record if worktree cleanup fails
- `deleteThread()` callers clear the thread's `selectedConversationIDs` entry so per-thread tab selection does not outlive the thread
- Active-thread delete rehomes `selectedSidebarItem` to the parent project before the destructive attempt, then restores the original selection/bookmark on failure
- Settings-open archive/delete flows reconcile the preserved `previousSelection` bookmark to the parent project before the model mutation happens, restoring the original bookmark on delete failure
- Archive/restore intentionally preserve `selectedConversationIDs[threadID]` within the same app session so reopening the thread returns to the last selected tab
- `threadStatus()` aggregation priority across conversations: `.busy` > `.error` > `.idle` > `.stopped`, with an all-`.neutral` fallback to `.stopped`
- `threadStatus()` returns `.archived` regardless of underlying agent status
- `threadStatus()` returns `.stopped` (no dot) when all conversations are `.neutral` (for example, never spawned or after relaunch/restore before the next spawn) — not `.idle`
- `statusVersion` increments via `.agentStatusChanged` notification (and does not increment for unrelated notifications), and `deinit` removes the observer token so recreation cannot leak duplicate invalidations
- `SidebarView` auto-expands the owning project when selection changes programmatically to a project/thread, so menu-command or fallback selection never lands on a hidden row
- Restoring an archived thread expands its parent project so the row stays discoverable after it leaves the Archived section

**Snapshot tests for SidebarView:** cover key visual states (projects with threads and status indicators, archived section collapsed/expanded, empty state).
