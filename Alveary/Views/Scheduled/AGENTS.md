## Scheduled Task Management

- Keep editor state in value snapshots. Re-resolve definitions and Projects through `ScheduledTasksViewModel` when the user commits an action.
- Route create, edit, pause, resume, delete, and Run now preparation through `ScheduledTaskMutationService`; never mutate `ScheduledTask` rows from a view.
- Treat edits and deletion as future-definition changes. Active runs continue from their immutable snapshots.
- Keep recurrence fields structured and hide timezone input. Treat the persisted IANA identifier as a derived cache of the Mac's current zone, and rebase future wall-clock occurrences when the system zone changes.
- Scheduled editor menu controls wrap their selected value at normal widths and compress with tail truncation inside narrow panes. Date fields inherit the host view's timezone so production follows the Mac while snapshots can inject a deterministic timezone.
- Keep folder grants as native folder selections and display their full paths in accessibility help.
- Keep the Scheduled screen's filters in a fixed conversation-style pane header: compact `TabChipButtonStyle` controls, a trailing primary create action, `.bar` background, and the shared titlebar-matched `AppSeparatorHairline(surface: .paneHeader)`. Keep list content on the header's 20-point leading inset. Do not restore a redundant screen title or explanatory subtitle.
- Reuse `ScheduledTaskEditorContent` for manual panes and create/edit proposals. The proposal modal wrapper owns its own draft/error state and submits through the proposal queue; it must never clear or mutate cached manual pane sessions. Root-overlay editors must compress inside a 640-point window; destructive/action-only proposals use the root confirmation overlay and disable confirmation when their captured revision or Project is stale.
- Keep the shared editor section order Task, Schedule, Workspace, then Agent. Existing-thread destinations omit Agent while preserving the same leading section order.
- Provider refresh completion may normalize the bound editor draft only for modal surfaces. The Scheduled screen uses `loadForScreen()` to normalize its active manual session without clearing its local error; proposal presentation uses plain `load()` so it cannot mutate a cached manual session.
