## App Lifecycle And Root Layout

These instructions cover `Alveary/App/` — the entry point, `AppDelegate`, `AppState`, the root `ContentView` scaffolding and window chrome, and the root's modals and overlays. Three concerns have their own scopes: `Toolbar/` (the primary toolbar group and window header), `Routing/` (the right-pane lane, command dispatch, transcript-borne requests), and `Shortcuts/` (keyboard shortcuts, focused values, app-shot capture).

**Keep a rule here only when the code that would violate it is not the code that documents it.** Mechanism whose only reader is its own file belongs in a doc comment: `MiddlePane`, `MainWindowPresenter`, and `LastActiveProjectRecorder` each carry theirs.

## macOS Lifecycle And Concurrency

- Keep `NSApplicationDelegate` implementations such as `AppDelegate` on `@MainActor`.
- When Swift 6 strict concurrency and AppKit interop fight in lifecycle code, prefer small explicit seams: injected dependencies for startup/shutdown behavior, and `@preconcurrency import AppKit` only where needed to bridge sendability gaps.
- **`.appWillTerminate` is an early shutdown contract, not a best-effort hint.** An observer owning teardown that must finish before process exit (file watchers, debounce tasks) completes synchronously on the main actor, never behind a `Task` hop — including flushing app-scoped conversation controllers before `AgentsManager.beginShutdown()` tears down provider runtimes.
- **To reach the main actor from a delegate callback not guaranteed to run there** (for example `UNUserNotificationCenterDelegate`), use `Task { @MainActor in ... }` — never `DispatchQueue.main.async` plus `MainActor.assumeIsolated`. `assumeIsolated` stays right inside callbacks already delivered on main, such as `NotificationCenter` observers registered with `queue: .main` or synchronous `deinit` work on a `@MainActor` type.

## Root Layout

- **`MiddlePane` is the root's only memoization boundary — keep it `Equatable`.** A new stored input must join `==` unless it is a window-lifetime dependency handle or a closure reading through one; a value-typed input that varies (like `targetSettingsPage`) always joins it.
- **Keep the native titlebar separator disabled**, and render every `AppSeparatorHairline` surface at the same explicit one-physical-pixel tint.
    - **Keep the root divider unconditional.** The root toolbar hairline stays visible for every selection; a mounted multi-conversation tab strip draws its own bottom `.paneHeader` hairline, so a conditional root divider produces two separators around the strip.
    - **Keep the window toolbar's background hidden** (`rootWindowChrome`); macOS 27 otherwise elevates it above the header beneath, splitting the band. Do not substitute an explicit toolbar color — the pane headers' `.bar` and the window background are materials tracking the desktop tint, so a flat fill mismatches them instead of matching. Full screen keeps a residual step regardless: macOS draws that toolbar as its own overlay window, and `.windowToolbar`, `.automatic`, and `titlebarAppearsTransparent` all leave it untouched.
- **Commit-message generation ownership is fetch-free and exactly-once.** `AppState.CommitMessageGenerationRequest` carries both `threadID` and an explicit `conversationID` so selection and conversation-map changes validate synchronously. Every success, failure, replacement, and cancellation goes through `completeCommitMessageGenerationRequest(id:result:)`, so a stale conversation task is a no-op and can never resume a continuation twice.

## Render-Time SwiftData Discipline

- **Treat `AppState.selectedSidebarItem` thread references as selection tokens**, not proof the backing row is readable. Re-resolve with `ModelContext.resolveThread(id:)` and fetch live conversations before reading thread relationships for toolbar actions, notification routing, diff actions, or launch-selection persistence.
- **Do not gate render-time UI state in `ContentView` body on fetch-backed resolution.** Plain `ModelContext.fetch` reads are not observation-tracked, so a body-computed boolean derived from them latches until an unrelated tracked mutation re-renders. Gate on observation-tracked state and defer fetch-backed resolution to the action handlers — Diff Viewer action buttons are the worked example: `Commit` enables for selected threads or projects, and the footer's Create PR / View PR gates read `selectedPullRequestLinks` plus `canCommitDiffChanges`, with handlers re-resolving the backing rows.

## Launch, Restore, And Cleanup

- **Launch restore is exact-match and best-effort.** Re-open the last thread and conversation only when both persisted `lastOpenThreadID` and `lastOpenConversationID` resolve to the same live, unarchived pair; otherwise clear the saved IDs and fall back to the empty selection state.
- **Delete stale draft threads and their attachment directories at launch**, before selection restoration or activity backfill, so a mounted draft cannot overwrite the last-open real thread. Materialization persists its thread and main-conversation IDs after the first durable save.
- **The app outlives its last window.** `applicationShouldTerminateAfterLastWindowClosed` returns `false` so agent runs, scheduled tasks, and the capture shortcut survive a ⌘W; the status item (`Alveary/Services/MenuBar/AGENTS.md`) and the Dock icon are the ways back. Keep the activation policy `.regular` — no `LSUIElement` — so the Dock icon still answers when the user turns the status item off.
    - **`ContentView.onAppear` now runs more than once per launch.** `AppState` lives on `AlvearyApp` and survives, so launch-only guards (`didAttemptLaunchSelectionRestore`, `didStartThreadActivityBackfill`) live there rather than in view `@State`. A re-created window that re-ran launch restore would find a non-nil selection, take the clearing branch, and wipe the persisted IDs.
- **App-hosted unit tests run the real `AppDI.component` and lifecycle** against `AppRuntimeProfile.current`'s isolated Application Support root and defaults suite. Keep app-owned writable service paths derived from `AppStorageProfile`, and do not make the hosted lifecycle inert or point it at production storage.
    - **Suppress what a hosted run would take from the machine, never the lifecycle behind it.** Automatic/restored app-owned windows, status-item chrome, and the capture shortcut's system-wide registration each get a DI-branched constructor seam — an unsuppressed registration steals ⌃⇧S from the developer's own Alveary for the whole run.
- **Cleanup never touches granted folders.** Stale Task-draft cleanup snapshots its workspace descriptor before the database commit and removes only marker-verified Alveary-owned roots after it. Private-workspace orphan cleanup retains valid prepared markers from nonterminal scheduled runs and from terminal runs still linked to a Task, even when recovery withholds the Task's workspace descriptor.

## First Appear And Root Modals

- **On first appear, sync the dock badge with `notificationManager.refreshBadgeCount()`** and nothing else. Do not also call `handleAppVisibilityChanged()` — mark-read of the restored conversation is driven by `ThreadDetailView`'s selection task (`Alveary/Views/Chat/ThreadDetail/AGENTS.md`), so the extra call duplicates it plus an extra chained badge task.
- **Root modal priority is onboarding, then image preview.** Scheduling proposals are **not** modal — they are confirmed in their own transcript widget, which is why `ScheduledTaskProposalQueueCoordinator` reaches the chat surface through the environment rather than the root. Do not reintroduce a root proposal modal.
