## Project Settings Views

These instructions cover the project settings UI under `Alveary/Views/Projects/`.

- Project actions are edited from project settings via `.alveary.json`, but they surface in the main toolbar only while a thread for that project is selected. Execution should prefer the thread's `worktreePath` and only fall back to the project root when no worktree exists.

## Add Project Sheet

`AddProjectSheet` is the intermediate modal triggered by `AppState.CommandRequest.newProject`. It owns a four-state machine rendered via an internal `Step` enum: `.chooser`, `.cloneForm`, `.cloneRunning`, and `.cloneFailed(String)`. The initial step and `CloneDraft` are injectable through the init for snapshot coverage — do not pass those arguments from production call sites.

- "Add From Disk" dismisses the sheet and hands control back to `ContentView.importProjectFromDisk()`, which runs the existing `NSOpenPanel` + `SidebarViewModel.createProject(path:)` flow.
- "Clone from Git" collects a URL, parent folder, folder name, and optional branch. The folder name auto-derives from the URL until the user edits it (tracked by `CloneDraft.folderNameIsDirty`, which latches on first manual edit and never resets).
- Clone cancellation is not an error: cancel from the running step returns to `.cloneForm` (draft intact); close-during-run (sheet X, Esc) cancels the task via `.onDisappear` and dismisses.
- Cancellation that races a successful clone commits to success: once `cloneRepository` has returned, `startClone` calls `onProjectCreated` unconditionally rather than guarding on `Task.isCancelled`. Skipping the hand-off after persistence would orphan the cloned project in SwiftData without a sidebar selection pointing at it.
- `.cloneFailed` offers Retry (re-clones with the same draft) and Back. Back returns all the way to `.chooser`, matching the Back button in `.cloneForm`, so "Back" always means "first modal". The `@State` draft survives the round trip, so reopening the clone form keeps the user's inputs.
- The top-right sheet `X` dismisses the whole sheet from any step (cancelling any in-flight clone via `.onDisappear`). The success path hands off via the parent's `isPresented` binding in `onProjectCreated` rather than calling `dismiss()` itself.

## Clone Invariants

`SidebarViewModel.cloneRepository(url:into:branch:)` is the canonical entry point for repo cloning and has a hard "no artifacts on cancel/error" invariant:

- It refuses pre-existing destination paths so cleanup is always scoped to a directory it created itself.
- Before `mkdir -p`'ing the parent chain, it snapshots the deepest already-existing ancestor. On failure — including `CancellationError` from the caller — a `Task.detached` block removes the destination and walks back up removing only the *empty* intermediate directories the clone itself created, stopping at that pre-existing ancestor. User-owned parents like `~/Development` are never touched even if they end up empty by coincidence. Mirror this pattern if you add sibling async destination-creating flows.
- On success, the project is persisted through `createProject(path:)` so the `Project.remoteName` / `Project.gitRemote` paired invariant in `Data/AGENTS.md` is preserved automatically.
