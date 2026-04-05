# Part 4e: Screens and Lifecycle

Screen integration, error handling, first-run experience, keyboard shortcuts, app lifecycle. Continues from Part 4d.

Phase note: the screen-wiring sections in this file land during Phase 6. Even though this file comes after the Sidebar/Chat docs in reading order, its `Error Handling UX` and `First-Run Experience` sections are the shared component specs that Phase 6 intentionally builds first. The `App Lifecycle` section below is Phase 7 work; the minimal `AppDelegate` shell already exists from the Phase 1 bootstrap stub and is only filled in here later.

---

## Diff Viewer

The diff viewer is the right pane, toggled via the toolbar button. The full specification — layout, data flow, FSEvents watcher, staging/unstaging, agent-directed commit/open-PR actions, and `DiffViewerViewModel` — is in `plan/part3d-diff-viewer.md`. The SwiftUI view (`DiffViewerPane`) is wired in `ContentView` (see [Part 4a: Layout](part4a-layout.md)). Its visibility is independent from middle-pane routing: Settings preserves the prior thread-backed diff context, while true non-thread screens (`ProjectSettingsView`, `SkillsScreen`, `MCPScreen`, and the no-project empty state) clear the diff content and leave the pane showing an empty placeholder with watching disabled until a thread is selected again.

---

## Skills Screen

The skills management screen is shown in the middle pane when "Skills" is selected in the sidebar. The full specification — grid layout, install/uninstall, catalog fetching, skills.sh search, skill detail modal, create form, `SkillsViewModel`, and `SkillsService` — is in `plan/part3e-skills.md`.

---

## MCP Screen

The MCP server management screen is shown in the middle pane when "MCP" is selected in the sidebar. The full specification — server list, add/edit form, agent sync, adapter formats, `MCPViewModel`, and `MCPService` — is in `plan/part3g-mcp.md`.

---

## Settings Screen

The settings screen replaces the middle pane when opened (Cmd+,). The layout, tabs, and setting descriptions are in [Part 1c: Settings UI](part1c-settings-ui.md). The `SettingsViewModel` (`Skep/ViewModels/SettingsViewModel.swift`) is also defined there. When Settings is opened from a thread, the shared right-pane diff context stays pointed at that preserved thread via `AppState.previousSelection`; opening Settings is a temporary middle-pane replacement, not a signal to blank the diff viewer. That preserved diff state is read-only for agent-directed actions: **Commit** / **Open PR** stay disabled until the user returns to a live thread view, because the one-shot request consumer lives in `ConversationView`. If the preserved thread is archived or deleted while Settings is open, dismiss falls back to its project (or empty state if the model is gone) instead of restoring archived chat.

---

## Error Handling UX

Errors should be surfaced inline and contextually -- never as blocking alert dialogs unless the action is destructive and needs confirmation.

### Inline Error Patterns

**Transient operation errors** (stage failed, skill install failed):
- Show an inline banner at the top of the relevant content area with the error message and a dismiss button.
- Use a warm color (amber/red) with a subtle background, not a modal.
- Auto-dismiss after 8-10 seconds, or on user action.

```swift
struct InlineBanner: View {  // Skep/Views/Components/InlineBanner.swift
    let message: String
    let severity: Severity  // .warning, .error, .info
    let autoDismissAfter: Duration?  // nil = persistent until dismiss
    let onDismiss: () -> Void

    enum Severity: Sendable { case warning, error, info }
}
```

Use `autoDismissAfter` only for transient local-operation failures. Chat errors, session-continuity warnings, and sidebar action failures keep `autoDismissAfter == nil` so they remain visible until the user dismisses them or a successful retry clears the owning state.

Shared boundary: `InlineBanner` is the reusable plain-message surface (message + severity + optional dismiss timing). Do **not** stretch it to cover chat-only progress rows or provider-specific CTA banners. The reconfigure-status row and permission-escalation banner described in [Part 4c](part4c-chat.md) stay as chat-local helpers because they need non-dismissible progress or provider-driven actions that do not belong in the shared error component.

**Persistent state errors** (agent not installed, GitHub not connected, worktree path missing):
- Show as an inline status indicator in the relevant list item or settings panel.
- Include an action button: "Install", "Connect", "Fix".
- For a missing worktree path specifically, the Fix action appends the old branch name into `pendingCleanupBranches`, clears the stale `branch` / `worktreePath`, flips `hasCompletedInitialSetup = false`, and returns the thread to the normal first-message setup flow so the next send recreates the worktree instead of surfacing a generic spawn failure.
- Don't block other functionality -- the user can still use other agents/projects.

**Agent chat errors** (initial setup failure, turn failure, process crash):
- Before any persisted or live chat content exists, show the centered setup-error card in `EmptyThreadState` with a "Retry" button. This owner is keyed to "no history yet + `lastTurnError`", so it still applies when a first-message rollback preserved `hasCompletedInitialSetup = true` in order to reuse an existing worktree on retry.
- After the conversation has persisted history, show `lastTurnError` as a persistent inline chat banner above the composer instead of replacing the history with a centered error card.
- The next setup/send/steer attempt clears that banner before retrying. If the process died, the normal `queueOrSend()` stopped-thread routing path is the retry mechanism; there is no separate post-history "Retry" button.

```
│  ┌─ Assistant ───────────────────────────┐  │
│  │ I'll refactor the auth module...      │  │
│  └───────────────────────────────────────┘  │
│                                             │
├─ ⚠ Agent process crashed unexpectedly ─ ✕ ─┤
╭─────────────────────────────────────────────╮
│ [Type a message...]                  [Send] │
╰─────────────────────────────────────────────╯
```

Transient local-operation errors (stage failed, skill install failed) appear as a dismissible banner in the relevant surface:

```
│                                             │
├─ ⚠ Could not stage `src/auth.ts` ──── ✕ ───┤
│                                             │
```

### Destructive Action Confirmation

Only use confirmation dialogs for irreversible actions:
- **Delete thread** (destroys worktree and branch)
- **Revert file** (discards uncommitted changes)
- **Uninstall skill** (removes from all agents)

Use SwiftUI's `.confirmationDialog()` or `.alert()` with a clear description of what will be lost.

For thread deletion in v1, `SidebarView` owns the pending delete target and presents the confirmation dialog before it calls `SidebarViewModel.deleteThread(...)`, so the destructive runtime/worktree teardown still has one view-model owner while the confirmation UX stays in the view layer.

---

## First-Run Experience

When the app launches with no data, each screen should show a helpful empty or introductory state instead of a blank panel. Simple full-screen fallbacks use a shared `EmptyStateView` component; screens that still render their normal search/recommended content (Skills, MCP) use an inline intro card/header instead of replacing the entire screen:

```swift
struct EmptyStateView: View {  // Skep/Views/Components/EmptyStateView.swift
    let icon: String             // SF Symbol name
    let heading: String
    let subtext: String
    let actions: [EmptyStateAction]

    struct EmptyStateAction {
        let title: String
        let style: ActionStyle    // .primary or .secondary
        let action: () -> Void

        enum ActionStyle { case primary, secondary }
    }
}
```

### No Projects

The middle pane shows a centered `EmptyStateView`:

```
┌────────────────────────────────────────────────────────┐
│                                                        │
│                                                        │
│                     📁+                                │
│              Add your first project                    │
│                                                        │
│     Open a Git repository to start working             │
│     with AI agents.                                    │
│                                                        │
│             [ Open Existing Repo... ]                 │
│                                                        │
│                                                        │
└────────────────────────────────────────────────────────┘
```

- Icon: `folder.badge.plus`
- One primary button: **"Open Existing Repo..."** (opens `NSOpenPanel` folder picker). Repository cloning is deferred until the plan has a dedicated clone/import flow instead of an empty-state-only stub.

### Projects Exist, Nothing Selected

Because `AppState.selectedSidebarItem`, `AppState.previousSelection`, and pane visibility are launch-scoped UI state rather than persisted navigation, app relaunch normally reopens with no middle-pane selection even when projects already exist. In that case, do **not** reuse the first-run importer empty state. Show a neutral centered placeholder instead:

- Icon: `sidebar.left`
- Heading: **"Select a project or thread"**
- Subtext: **"Choose something from the sidebar to continue."**
- No primary action required; this is a selection hint, not a missing-data state.

### No Agents Installed

After the first project is added, `ProjectSettingsView` owns the provider-install surface instead of replacing the whole middle pane with a second empty state. Its inline **AI agents** card is driven by `AgentRegistry` (for provider metadata) and `ProviderDetectionService` (for live status):
- While provider detection is still `.unchecked`, show a loading/refreshing state rather than install guidance.
- When **all checked providers** are `.missing`, show the "No AI agents found" guidance inline in that card with each missing provider's `installCommand` from the matching `AgentRegistry` entry in a copyable code block.
- A **Refresh** button calls `ProviderDetectionService.checkAllProviders()`.
- If the user tries to start a thread anyway and the selected provider is still missing, the centered setup-error state from Part 3a remains the fallback owner for the provider-specific **Install ...** CTA.

### No GitHub Connection

In project settings or any PR-related surface:
- If `gh` is installed but unauthenticated, show the inline message **"Connect GitHub for PR/CI features and agent-opened PRs."** with a **"Connect GitHub"** button that calls `GitHubCLIService.authenticate()` (see `GitHubCLIService` in `Skep/Services/Git/GitHubCLIService.swift`) to start the device flow.
- If the `gh` CLI is missing, show install guidance instead (`brew install gh`) rather than a connect button.

### No Skills

When `SkillsViewModel.installed` is empty, `SkillsScreen` keeps its normal search bar and catalog grid visible. Instead of replacing the screen with a bare `EmptyStateView`, show an introductory empty-state card above the content:
- Icon: `puzzlepiece.extension`
- **"Extend your agents with skills"** heading.
- **"Skills are reusable modules that give agents new capabilities."** subtext.
- Primary action: **"+ New Skill"**.
- The regular "Browse Catalog" section still renders below the intro card using the non-installed entries from `SkillsViewModel.catalog` after `load()` completes.
- Only fall back to a centered full-screen `EmptyStateView` if both installed skills and catalog data are unavailable (for example, bundled fallback missing and catalog load failed).

### No MCP Servers

When `MCPViewModel.servers` is empty, `MCPScreen` keeps the normal Recommended section visible when bundled recommendations are available. Show an introductory empty-state card above the list rather than replacing the whole screen:
- Icon: `server.rack`
- **"Connect external tools via MCP"** heading.
- **"MCP servers give your agents access to databases, APIs, and other tools."** subtext.
- Primary action: **"Add Server"** (opens the add-server form).
- The regular Recommended section still renders below the intro card using `MCPViewModel.recommended`.
- Only fall back to a centered full-screen `EmptyStateView` if both `servers` and `recommended` are empty.

---

## Keyboard Shortcuts

| Shortcut | Action |
|---|---|
| **Cmd+,** | Open app-wide settings |
| **Cmd+N** | New thread in current project |
| **Cmd+Shift+N** | New project (open repo) |
| **Cmd+T** | New conversation (side chat) in current thread |
| **Cmd+\\** | Toggle left pane (sidebar) |
| **Cmd+Shift+\\** | Toggle right pane (diff viewer) |
| **Option+Enter** | Insert newline in the chat input without submitting |

`Cmd+N` and `Cmd+Shift+N` are implemented by replacing the default new-item commands in `SkepApp`'s single `Window` scene, so they never open a second app window. `Cmd+N` resolves the current project context from the selected project row or the selected thread's parent project. If Settings is currently open, it reuses the preserved pre-settings selection instead of treating `.settings` as contextless, so reopening Settings does not wipe out the current project context. When no project context exists yet, the command is disabled/no-op rather than guessing.

`Cmd+\\` and `Cmd+Shift+\\` are attached to the left-pane and right-pane toolbar buttons in `ContentView`. `Cmd+T` is attached to the conversation-tab add action in `ThreadDetailView`, which creates and selects a side conversation without spawning an agent until its first message. `Option+Enter` is handled directly by `ChatInputField`.

Additional navigation/edit shortcuts (archive thread, jump between threads, focus chat input, commit/push accelerators, queued-message editing) are deferred until the plan has an explicit command-routing owner for each action. V1 keeps the shortcuts above fixed and implements them with SwiftUI's `.keyboardShortcut()` modifier or local key handling in the owning view.

---

## App Lifecycle

Phase 7 only: implement the startup/shutdown behavior below after the Phase 6 app shell, views, and runtime services already compile together. Do not pull this logic forward into the earlier phases, which only carry the minimal `AppDelegate` shell needed for incremental compilation.

### Startup Sequence

On launch, the app kicks off a startup warmup task that performs the following sequence:

Keep `AppDelegate` on `@MainActor`: it resolves the shared `appAssembler`, matches `NSApplicationDelegate`'s runtime isolation, and avoids Swift 6 cross-isolation errors during delegate construction. The observer tokens below are explicit owned resources, so the plan should show their matching teardown just like the sidebar/runtime docs do.

```swift
// Skep/App/AppDelegate.swift
@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    private let resolver = appAssembler.resolver
    private var startupTask: Task<Void, Never>?
    private var wakeRefreshTask: Task<Void, Never>?
    private var wakeObserver: NSObjectProtocol?
    private var managedProcessesObserver: NSObjectProtocol?
    private var suddenTerminationDisabled = false

    deinit {
        startupTask?.cancel()
        wakeRefreshTask?.cancel()
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
        }
        if let managedProcessesObserver {
            NotificationCenter.default.removeObserver(managedProcessesObserver)
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let agentsManager = resolver.agentsManager()
        let providerDetection = resolver.providerDetectionService()
        let sessionManager = resolver.sessionManager()

        // Session map first, then orphan cleanup, then provider detection.
        startupTask?.cancel()
        startupTask = Task { [weak self] in
            await sessionManager.load()
            guard !Task.isCancelled else { return }
            await self?.cleanupOrphanedClaudeProcessesIfNeeded()
            // POST-V1: prune bindings for deleted conversations here after the
            // spawn path's missing-`.jsonl` fallback rules stay the single owner.
            guard !Task.isCancelled else { return }
            await providerDetection.checkAllProviders()
        }

        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.wakeRefreshTask?.cancel()
                self?.wakeRefreshTask = Task {
                    try? await Task.sleep(for: .seconds(2))
                    guard !Task.isCancelled else { return }
                    await providerDetection.checkAllProviders()
                }
            }
        }

        managedProcessesObserver = NotificationCenter.default.addObserver(
            forName: .managedProcessesChanged, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.updateSuddenTerminationState(using: agentsManager)
            }
        }
        updateSuddenTerminationState(using: agentsManager)

        // AppState still starts fresh each launch.
    }

    private func updateSuddenTerminationState(using agentsManager: any AgentsManager) {
        let hasLiveProcesses = !agentsManager.allProcessesSnapshot.isEmpty
        switch (hasLiveProcesses, suddenTerminationDisabled) {
        case (true, false):
            ProcessInfo.processInfo.disableSuddenTermination()
            suddenTerminationDisabled = true
        case (false, true):
            ProcessInfo.processInfo.enableSuddenTermination()
            suddenTerminationDisabled = false
        default:
            break
        }
    }

    private func cleanupOrphanedClaudeProcessesIfNeeded() async {
        // Implementation outline owned by AppDelegate:
        // 1. Inspect live Claude processes for argv session IDs and canonical cwd.
        // 2. Ask SessionManager for the owning conversation via
        //    `conversationId(forSessionId:cwd:providerId:)`.
        // 3. Skip anything the current launch already owns or is still spawning via
        //    `hasTrackedProcess(conversationId:)` / `hasInflightLifecycle(conversationId:)`.
        // 4. Use a fresh read ModelContext (resolved inside this helper) for the
        //    best-effort SwiftData existence check described below.
        // 5. Terminate only session-map-proven orphaned Claude children, preserving
        //    the session-map entry for any surviving conversation record.
    }
```

### Shutdown Sequence

On quit, all long-lived agent processes must be cleaned up. Since each conversation has a persistent Claude process, the app may have several running simultaneously.

`applicationWillTerminate` is synchronous, so the final `sessionManager.persist()` bridge must use `Task.detached` rather than `Task {}`. A plain `Task` would inherit `@MainActor`, then deadlock behind the semaphore wait shown below.

```swift
// Inside AppDelegate (continued from Startup Sequence above)
func applicationWillTerminate(_ notification: Notification) {
    let agentsManager: any AgentsManager = resolver.agentsManager()
    let sessionManager: any SessionManager = resolver.sessionManager()

    startupTask?.cancel()
    wakeRefreshTask?.cancel()

    // Freeze spawn before snapshotting live children.
    agentsManager.beginShutdown()

    // Stop UI-owned watchers/debounce work before the main-thread wait below.
    // Observers on this notification must tear down synchronously on the main actor;
    // enqueuing `Task { @MainActor ... }` here can be starved by the blocking wait.
    NotificationCenter.default.post(name: .appWillTerminate, object: nil)

    let processes = agentsManager.allProcessesSnapshot

    // SIGTERM children; stdin closes with process exit.
    for process in processes where process.isRunning {
        process.terminate()
    }

    // Brief grace period, then SIGKILL stragglers.
    let deadline = Date().addingTimeInterval(1.5)
    while processes.contains(where: { $0.isRunning }) && Date() < deadline {
        usleep(50_000)
    }
    for process in processes where process.isRunning {
        kill(process.processIdentifier, SIGKILL)
    }

    // Best-effort repair path for any in-memory session-map changes.
    let semaphore = DispatchSemaphore(value: 0)
    Task.detached {
        try? await sessionManager.persist()
        semaphore.signal()
    }
    _ = semaphore.wait(timeout: .now() + 0.5)

    // SwiftData persists through its own lifecycle.
}

} // end AppDelegate

extension Notification.Name {
    static let appWillTerminate = Notification.Name("appWillTerminate")
}
```

**Crash / termination protection**: treat signal-based cleanup as best-effort for normal termination paths such as `SIGTERM`, logout, or shutdown. It is **not** a guarantee for force-quit / `SIGKILL` / crash scenarios. `AppDelegate` owns the `ProcessInfo.processInfo.disableSuddenTermination()` / `enableSuddenTermination()` toggling via a `.managedProcessesChanged` observer: when the live-process snapshot transitions from empty → non-empty, disable sudden termination; when it returns to empty, re-enable it. This keeps the policy tied to the same process owner that already manages startup/shutdown instead of inferring process liveness from UI status notifications. `beginShutdown()` complements this by freezing new spawns before the synchronous termination snapshot is taken and by giving `sendMessage()` a global shutdown tombstone to reject late queued writes before they launch a new detached writer. The startup warmup and delayed wake-refresh checks are also `AppDelegate`-owned resources: store them in `Task` properties, cancel/restart the wake task on repeated `didWake` notifications, and cancel both tasks from `applicationWillTerminate` / `deinit` so they cannot keep running provider detection or orphan scans after shutdown intent is established. The early `.appWillTerminate` notification is part of that synchronous shutdown path, so observers that must finish before the blocking exit wait (notably `DiffViewerViewModel`) should use an inline main-actor hop such as `MainActor.assumeIsolated { ... }` rather than scheduling `Task { @MainActor ... }` work that could be starved until after termination cleanup is already underway.

**Quit is not `kill()`**: normal app shutdown terminates child processes, but it does **not** call per-conversation `kill()` or remove session-map entries. That distinction is intentional: archive/delete are explicit teardown flows that destroy resume bindings, while app quit/relaunch preserves those bindings so the next spawn can resume.

**Mid-turn quit semantics**: Claude-specific validation on v2.1.97 showed that `SIGTERM` during an active streamed turn still leaves the session resumable under the same session ID. Facts introduced by the interrupted user message were remembered after `--resume`, and the `.jsonl` already contained that user message, but Claude had **not** written a finalized assistant entry for the interrupted response before exit. A later stdin follow-up injected while the first turn was still busy could also be consumed far enough for Claude to record queue-enqueue metadata, yet still failed to appear as a persisted `user` entry and was absent after resume if shutdown landed before Claude promoted it to the next active turn. Treat app quit/relaunch as preserving provider context and the active committed user turn, not as guaranteeing that partially streamed assistant text or later queued follow-ups become completed historical messages. Any partial UI text visible only in `streamingText` remains app-owned and may be lost unless Skep already persisted equivalent history.

Because the coalesced SwiftData save path remains VM-owned and `applicationWillTerminate` does not synchronously drain those `@MainActor` save tasks before blocking the main actor, the last few already-rendered records may still depend on EventBuffer replay after relaunch rather than guaranteed on-disk persistence at quit time. This is the documented v1 durability boundary, not a hidden race: provider session continuity can survive shutdown even when UI history is still catching up.

**Orphan prevention**: `AppDelegate` runs a private `cleanupOrphanedClaudeProcessesIfNeeded()` helper once during startup, immediately after `sessionManager.load()` and before provider warmup. Ownership proof should use `SessionManager.conversationId(forSessionId:cwd:providerId:)`, not a second raw read of `session-map.json`, so startup cleanup and normal spawn logic share the same binding source of truth. The helper identifies Claude candidates from live argv inspection (`--session-id <uuid>` / `--resume <uuid>`) and recovers their cwd from process inspection; runtime validation showed both that argv is visible and that the recovered cwd is already the canonical real path rather than any symlink alias. A narrower fork-session probe also showed that a live `--resume <old> --fork-session` process keeps advertising `--resume <old>` in `ps` even after `system/init.session_id` rotates to the new branch ID, so the session-map reverse lookup must match both the current resumable `appSessionId` and the last launched argv `launchSessionId`. Because destructive teardown now keeps the session binding until the old child exit is confirmed, that lookup still works during kill/archive/delete crash windows instead of losing ownership proof halfway through teardown. Because this helper runs in an async warmup task, it must treat both `AgentsManager.hasTrackedProcess(conversationId:)` and `AgentsManager.hasInflightLifecycle(conversationId:)` as ambiguous current-launch ownership and skip termination in either case; only a proven match with no tracked child and no in-flight lifecycle bookkeeping should be treated as an orphan. This deliberately prefers a false negative (leave an uncertain process alone for one launch) over killing a just-started current-run child. After a session-map match is found, the helper should do a best-effort SwiftData existence check for that conversation using a fresh local read `ModelContext` resolved inside the helper rather than storing one on `AppDelegate`. If ownership cannot be proven, the process is left alone. If the conversation still exists and the helper terminates the orphan, leave the session-map entry intact so the next user-driven spawn can `--resume` cleanly against the stored UUID. If the conversation record is already gone, it is still safe to terminate the proven orphan to avoid leaking a stray prior-launch child; v1 simply leaves the stale session-map entry in place for the later deleted-conversation prune pass instead of expanding startup cleanup into a second destructive owner. Runtime validation also showed Claude allows a second live `--resume <uuid>` while the original long-lived process is still running, so orphan cleanup is primarily about preserving single-owner app semantics and preventing duplicate runtimes from mutating the same conversation concurrently, not about making resume possible at all. Stale session-map entry cleanup for deleted conversations remains the POST-V1 follow-up described above.

Startup orphan-cleanup decision table:

| Session-map match? | SwiftData conversation exists? | `hasTrackedProcess` | `hasInflightLifecycle` | Action |
|---|---|---|---|---|
| No | Any | Any | Any | Leave the process alone |
| Yes | Any | Yes | Any | Leave it alone — current launch already owns a published child |
| Yes | Any | No | Yes | Leave it alone — current launch is still spawning/reconfiguring |
| Yes | Yes | No | No | Terminate the orphan and keep the session-map entry |
| Yes | No | No | No | Terminate the orphan; stale session-map pruning stays post-V1 |

### Focused Lifecycle Tests

- `applicationDidFinishLaunching` stores the startup warmup in `startupTask`, and `applicationWillTerminate` / `deinit` cancel both `startupTask` and `wakeRefreshTask`
- Repeated `NSWorkspace.didWakeNotification` deliveries cancel the older delayed refresh before starting a new provider-detection pass
- `applicationWillTerminate` posts `.appWillTerminate` before entering its blocking exit wait, and the diff-viewer observer handles it synchronously on the main actor so FSEvents, debounce, and poll work are canceled promptly instead of being queued behind the wait
- `cleanupOrphanedClaudeProcessesIfNeeded()` terminates only session-map-proven Claude children, skips ambiguous current-launch ownership (`hasTrackedProcess` / `hasInflightLifecycle`), and distinguishes between existing-vs-deleted SwiftData conversations when deciding whether to preserve the session-map entry

### State Survival Matrix

| State | Navigation / tab switch | `kill()` / archive | Delete thread | Reconfigure | App relaunch / shutdown |
|---|---|---|---|---|---|
| SwiftData chat history / thread metadata | Survives | Survives | Removed with cascade delete | Survives | Survives |
| Session map entry | Survives | Removed | Removed | Survives and may be updated to the new session ID | Survives |
| Worktree on disk | Survives | Survives archive; delete removes it | Removed | Survives | Survives |
| `ConversationState` (`inputDraft`, queue, `selectedModel`, staged context, grouper cache) | Survives | Removed | Removed | Survives | Lost |
| `AppState` (`selectedSidebarItem`, `selectedConversationIDs`, `previousSelection`, pane visibility) | Survives in-launch | Archive may temporarily rehome selection; restore keeps surviving bookmarks | Thread-specific entries removed | Survives | Lost |
| `EventBuffer` | Survives VM destruction briefly | Explicit teardown keeps it only for a short durability grace window, not later replay | Not relied on | Replaced with the new session's buffer | Lost |
| Live process / status snapshot | Survives UI navigation | Terminated | Terminated | Old process terminated, replacement spawned | Terminated |

### Window Model

The app is **single-window**. All projects, threads, conversations, skills, MCP, and settings live in the same window, implemented as one SwiftUI `Window` scene rather than a `WindowGroup`. A two-column `NavigationSplitView` (sidebar + detail) with an internal `HStack` split manages all navigation within this window.

---
