## View Models

These instructions apply to files directly under `Alveary/ViewModels/`. The rules below that name a subfolder's type are cross-cutting contracts this file owns; everything else lives in the narrowest subfolder guidance.

### Ownership Boundary

- Keep view models as coordination layers: route UI intent, own observers/watchers, and delegate service-backed state to focused collaborators when it becomes shared or long-running.
- **Own side effects.** View models own mutable runtime state, persistence, and side effects.
- **Keep presentation derived.** Renderer-neutral `*Presentation` types may derive display/action values from view-model state but never replace view-model ownership or perform service/model mutations.

### Contextual Panes

- Contextual editor view models cache drafts by stable target and give each session a generation UUID. Route-only `deactivatePane()` preserves the session for another root pane; generation-specific deactivation is phase one of closing and schedules that captured session for discard after the slide. Async completions may update only the same live generation.
- Final pane discard accepts root-level focus-restoration intent: a replacement root destination and same-target session replacement pass `restoreFocus: false`; only an actually closed pane may return focus to its invoking control.
- **Do not let the app root read a `paneSessions` entry.** `@Observable` has no per-key granularity, so indexing that dictionary from `ContentView` makes every session write re-render the whole root, mounted `ThreadDetailView` included. Mirror what the root needs onto its own property — `PullRequestsViewModel.activePaneSummaryStatus` is the pattern — refreshed from every mutation in the file that owns the dictionary's private setter.
- **Memoize list shaping behind an `@ObservationIgnored` cache**, keyed on every input it reads — `PullRequestsViewModel.visibleListCaches` (one entry per tab, since alternating tabs missed a single-entry cache every time), `SkillsViewModel.listCache`, and `ArchivedThreadsViewModel.sectionsCache`. Filling one during a render publishes nothing, but the getter **must still read every observable input to build the key before consulting the cache**, or `@Observable` stops tracking the dependency and the view goes stale. Arrays compare by shared buffer, so a hit is O(1). Defer a step the screen may not use (`searchDisplay`, `sections`) into an optional the first caller fills. Screens that render this pay for it per geometry frame — see **Render Cost** in `Alveary/Views/AGENTS.md`.
- Keep the invoking contextual-pane control ID in the root-lived feature view model, not screen-local state, so dismissal can restore the same control across screen unmount/remount.
    - When a successful mutation removes that control, retarget focus to the screen's persistent header action only while the captured pane target remains active; a delayed completion for an inactive session must not overwrite the newer target's focus owner.

### Archived Threads

- `ArchivedThreadsViewModel` owns archived-thread fetching, grouping, search/filter state, and lifecycle state for every thread mode. Permanent deletion preserves the row and app selection on pre-commit failure; after a post-commit cleanup failure, remove stale selection, bookmark, conversation, and launch-restore references while surfacing the diagnostic. Thread removal itself still routes through `SidebarViewModel` — see `Alveary/ViewModels/Sidebar/AGENTS.md`.

### Settings Editors

- `GlobalInstructionsEditorModel` backs the settings AGENTS.md editor and is built once by `SettingsViewModel` so its BlockInputKit document store and draft survive re-renders. Keep the store, undo controller, and dirty baseline `@ObservationIgnored`, guard equality before writing `isDirty`, and never recompute dirtiness by serializing per keystroke — reconfiguring `BlockInputView` on every edit resets transient editor UI.

### File Organization

- Put feature-specific view-model rules in the narrowest subfolder guidance:
  - `Conversation/` — controller registry and leases, `ConversationViewModel` companion split, handoff, tool approvals, transcript pull-request detection.
  - `PullRequests/` — list loading, search debounce, detail pane loads, review proposals; the link store in `PullRequests/Links/`.
  - `Sidebar/` — thread creation/removal/pinning, drafts, sidebar ordering and drag, Task-to-Project moves.
  - `Scheduled/` — scheduled-task management UI.
  - `DiffViewer/` — diff viewer state.
