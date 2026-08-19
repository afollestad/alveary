## Sidebar Interaction Patterns

These instructions cover `Alveary/Views/Sidebar/` — the `SidebarView` root that owns the `List`: its render snapshot, the `Pinned` and `Tasks` groups it composes, selection and keyboard traversal, and the async actions and dialogs those paths raise.

The surfaces themselves each have their own scope: `Rows/` (project, thread, and section header rows, plus rename and cleanup) and `Drag/` (drag sources, target geometry, and the Task-into-project access grant).

> **READ FIRST:** Focus and keyboard rules are centralized in **Focus And Keyboard Coordination** in `Alveary/Views/AGENTS.md`. The sidebar bullets below stack on top of that parent contract — they are not a replacement for it.

## Actions

- **Re-check `voiceInputLifecycleController?.isModelPreparationModalPresented` after every suspension point**, not only on entry: an async action that selects, restores, or falls back must not navigate underneath a blocking modal that appeared while it was awaiting.

## Pinned

- Pinned items render as a shared top-level group under `Scheduled` and above `Projects`:
    - Render the `Pinned` header when pinned projects or standalone pinned threads exist, matched with the `Projects` header styling and insets.
    - Thread pinning changes only sidebar placement; `AgentThread.project` still owns cleanup, diff actions, project deletion, and restore behavior.
    - Pinning a project clears pins on its unarchived children, which render only inside the pinned project's expandable list via `SidebarViewModel.activeThreads(for:)`. Standalone pinned threads must not render separately when their parent project is pinned, and nested child context menus omit `Pin`/`Unpin`.
    - Order the group by `pinnedSortOrder`, whose shared namespace `Alveary/Data/AGENTS.md` owns. Activity, name, and stable ID are deterministic legacy and backfill fallbacks only — later activity must not move a top-level pinned item.
    - Standalone pinned thread rows have no leading icon or reserved spacer; their title starts at the top-level row inset. Pinned project rows use the normal project row layout.
    - **Placing a Task in a Project clears its pin** — `moveTaskIntoProject` documents what such a Task keeps, but always resets `isPinned`/`pinnedSortOrder`, because a leftover pin renders the Task in two places and makes the drop look like a no-op. Placement then follows Project-mode child rules; pinning afterwards promotes it back out.

## Tasks

- The Tasks section renders below Projects:
    - **Route New task to Task composition.** Its header action starts the native Task-mode composer flow, never Scheduled.
    - **Keep the empty placeholder publishing `.tasksTerminal`**, whichever of its two labels `sidebarTasksPlaceholderLabel` picks, or the Tasks drop container stops covering the label region.
    - **Route removal fallback by placement.** Removing a selected projectless Task prefers the next visible Task, then the previous; if none remains, request a blank Task composer with no selected sidebar row. A Task placed in a project uses the project-child fallback instead — previous sibling, next sibling, then the project row.

## Keyboard And Top-Level Rows

- **`sidebarTopLevelRowItems(showsPullRequests:hasArchivedThreads:)` in `SidebarView+Selection.swift` is the single ordered source of truth** for the top-level rows (`Skills`, `MCP`, `Scheduled`, `Pull Requests`, `Archived`) and for which one carries trailing spacing and `.topLevelTerminal`; it documents why both follow the list's last element. Adding, removing, or hiding a row means changing that function, never re-deriving the group's shape per row.
    - **Gate visibility on render-context flags.** `Pull Requests` follows `SidebarRenderContext.showsPullRequests` (from `AppSettings.pullRequestsEnabled`), `Archived` follows `hasArchivedThreads`; both are computed once in `makeRenderContext()`. Row builders must not read the settings service or run a fetch.
    - **Keep the geometry modifier applied and flip only its value.** Every top-level row calls `.sidebarDragGeometry(.topLevelTerminal, isEnabled:)` unconditionally; applying/removing the modifier makes `List` transition the row and can leave a stale frame published mid-drag.
    - **Traverse from the same list.** `buildNavigableItems(...hasArchivedThreads:showsPullRequests:)` seeds its prefix from `sidebarTopLevelRowItems`, and both arrow-direction predicates treat every top-level row alike; a hidden row is simply absent.
    - **A row hideable while selected must drop both `appState.selectedSidebarItem` and the Settings `previousSelection` bookmark** — `handlePullRequestsVisibilityChange(showsPullRequests:)` plus `sidebarSelectionAllowingHiddenPullRequests(_:showsPullRequests:)` in `MiddlePane.swift` carry the reasoning.
- The `Archived` row sits under `Pull Requests`, conditional on content: `SidebarView` owns a `fetchLimit: 1` existence probe reaching render code and traversal as `SidebarRenderContext.hasArchivedThreads`. Do not fetch the archived rows here — `ArchivedThreadsViewModel` owns the real fetch.
- Horizontal arrows deliberately reuse the vertical traversal path for non-project rows; left collapses an expanded project row and right expands a collapsed one before either moves. The traversal lives in `buildNavigableItems()` / `navigateVertically()` in `SidebarView+KeyboardNavigation.swift`.
- Changing the selection must not expand a project — `sidebarProjectPathToExpand` returns nil for `.project`, or traversal could never rest on a collapsed row and every left-arrow collapse would be undone by returning to it. `revealProject` is the explicit alternative and documents which callers take it.
- `buildNavigableItems` drops a collapsed section's rows and their children entirely; `Pinned` always traverses. Section headers are not navigable items, so a selection stranded inside a collapsed section behaves like one under a collapsed project — the next ↓ restarts from the top.
- When adding top-level sections or changing visibility/expansion behavior, update `sidebarTopLevelRowItems`, the keyboard-navigation functions, and their tests together.
- **Sections are data, not statement order.** `SidebarRenderSnapshot.sectionDescriptors` is the single ordered source of truth, and `SidebarView.body` renders it through one `ForEach` into `sectionGroup(_:context:)`. A new section kind has to reach `SidebarSectionID`, that switch, `SidebarCollapsibleSection`, `SidebarDragGeometryRole.sectionHeader`/`sectionTerminal`, and `buildNavigableItems` together, or it renders without collapsing, without drop geometry, or outside keyboard traversal.
    - **Custom sections are created, renamed, and removed from the sidebar alone.** Both menus are `NSMenu`s popped from the list overlay's one `SecondaryClickTarget`: creation below the last row, rename and remove over a custom header. Built-in sections offer neither. `SidebarView+SecondaryClickMenus.swift` owns why neither can be a `contextMenu`, and `Alveary/Services/Threads/AGENTS.md` why no host tool removes a section.
        - **A pointer-only sidebar menu owes VoiceOver an equivalent.** The header's `accessibilityActions` carry rename and remove, since removing `contextMenu` took its rotor entries with it.
    - **Keep the list one flat `Section`.** Every header is an ordinary row so any section can sit in any slot; a SwiftUI `Section` header would structurally wrap everything below it and publish two frames — `Alveary/Views/Sidebar/Drag/AGENTS.md` owns that consequence.

## Render Snapshot

- Sidebar rendering is snapshot-driven, not fetch-driven:
    - **Build one snapshot per body.** `SidebarView.body` calls `makeRenderContext()` exactly once, grouping the `@Query`-backed projects and unarchived threads into a `SidebarRenderSnapshot` keyed by persistent ID, paired with the thread-order animation and drag logical order in a `SidebarRenderContext`.
    - **Route every render read through the context.** Sections, project children, placeholders, expanded counts, keyboard traversal, and drag-start ordering all take `SidebarRenderContext`. Do not call `SidebarViewModel.activeThreads(for:)`, `pinnedItems(projects:)`, `fetchedPinnedItems()`, or `activeTaskThreads()` from render code — each is a `FetchDescriptor` on the click-to-highlight frame.
    - **Keep authoritative fetches for post-mutation fallbacks.** Deletion, archive, and Task-removal selection recovery still use the fetch-backed reads in `SidebarView+Selection.swift`, which run after a commit where a snapshot would be stale. Placeholder emptiness has no fetch-backed sibling — `hasAnyActiveThreads(for:)` and `hasAnyActiveTaskThreads` exist only on the snapshot, reached in tests via `SidebarTestFixture.renderSnapshot()`.
    - **Filter every `@Query` array through `isLiveForRender` at pass start**, inside `makeRenderContext()`, before anything reads a persisted property — query results can still hold rows whose delete committed this tick, and reading one traps (`Alveary/Data/PersistentModel+RenderLiveness.swift` owns the mechanism). No render read may reach back to a raw query array.
    - **Never cache models in `@State`.** The snapshot is ephemeral by contract and its inputs are the liveness-filtered `@Query` results. Do not filter `project.threads` in render code; stale relationship entries can trap during `List`/`ForEach` refreshes.
    - **Include drafts in the query, exclude them in the snapshot.** The thread query filters only `archivedAt == nil` so draft changes stay observation-tracked; `SidebarRenderSnapshot` drops drafts from rows, counts, and pinned items.
    - **Status inputs are value snapshots, never relationship walks.** `makeRenderContext()` groups the conversations query into `ConversationStatusSnapshot`s per thread once per body, and rows fold those through `SidebarViewModel.threadStatus(threadID:isArchived:conversationStatuses:)`. Do not walk `thread.conversations` or call `ConversationDecisionAttention.awaitsDecision` from render code.
        - **Fold collapsed-container attention in `makeRenderContext()` too, never in a row builder.** `SidebarWaitingAttention` reads runtime status for threads that have no mounted row, so a read registered on a `ForEach` element would never repaint when one of them starts waiting.
