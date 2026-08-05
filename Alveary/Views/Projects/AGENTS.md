## Project Settings Views

These instructions cover the project settings UI under `Alveary/Views/Projects/`.

- Project actions are edited from project settings via `.alveary.json` and surface in the main toolbar while either that project's row or one of its project-mode threads is selected. A materialized thread executes them in its `worktreePath`, falling back to the project root; a project row or a draft thread executes at the project root.
- Hand every successful config write to `ProjectConfigStore.shared.store(_:forProjectPath:)`, passing the config that was written rather than re-deriving it — the editor's state can move while the write runs. The store caches it and posts the change notification the toolbar listens for, so a save path that skips it leaves other surfaces stale. Call it from this editor's main-actor save paths, never from `AlvearyProjectConfig.write`, which resumes off the main actor.
- This editor `reload`s rather than accepting the store's cached value, because it is the surface that must show an edit made to `.alveary.json` outside the app. Its initial state comes from the cache (`MiddlePane`) so a revisited project renders populated while that reload runs.
- Project settings has no archived-threads card. `Alveary/Views/Archived/` owns every archived surface; do not reintroduce a project-scoped archived list here. Asynchronous config loading and its save debounce stay on their own task.

## Add Project Sheet

`AddProjectSheet` is the intermediate modal triggered by `AppState.CommandRequest.newProject`, a four-state machine over an internal `Step` enum. The initial step and `CloneDraft` are injectable through the init for snapshot coverage — do not pass those arguments from production call sites.

- "Add From Disk" dismisses the sheet and hands control back to `ContentView.importProjectFromDisk()`, which runs the existing `NSOpenPanel` + `SidebarViewModel.createProject(path:)` flow.
- "Clone from Git" collects a URL, parent folder, folder name, and optional branch; the folder name auto-derives from the URL until the user edits it (`CloneDraft.folderNameIsDirty`).
- Clone cancellation is not an error: cancel from the running step returns to `.cloneForm` (draft intact); close-during-run (sheet X, Esc) cancels the task via `.onDisappear` and dismisses.
- Cancellation that races a successful clone commits to success: once `cloneRepository` has returned, `startClone` calls `onProjectCreated` unconditionally rather than guarding on `Task.isCancelled`. Skipping the hand-off after persistence would orphan the cloned project in SwiftData without a sidebar selection pointing at it.
- `.cloneFailed` offers Retry (re-clones with the same draft) and Back. Back returns all the way to `.chooser`, matching the Back button in `.cloneForm`, so "Back" always means "first modal". The `@State` draft survives the round trip, so reopening the clone form keeps the user's inputs.
- The top-right sheet `X` dismisses the whole sheet from any step (cancelling any in-flight clone via `.onDisappear`). The success path hands off via the parent's `isPresented` binding in `onProjectCreated` rather than calling `dismiss()` itself.

## Clone Invariants

`SidebarViewModel.cloneRepository(url:into:branch:)` is the canonical entry point for repo cloning and has a hard "no artifacts on cancel/error" invariant:

- It refuses pre-existing destination paths so cleanup is always scoped to a directory it created itself.
- Before `mkdir -p`'ing the parent chain, it snapshots the deepest already-existing ancestor. On failure — including `CancellationError` from the caller — a `Task.detached` block removes the destination and walks back up removing only the *empty* intermediate directories the clone itself created, stopping at that pre-existing ancestor. User-owned parents like `~/Development` are never touched even if they end up empty by coincidence. Mirror this pattern if you add sibling async destination-creating flows.
- On success, the project is persisted through `createProject(path:)` so the `Project.remoteName` / `Project.gitRemote` paired invariant in `Data/AGENTS.md` is preserved automatically.
