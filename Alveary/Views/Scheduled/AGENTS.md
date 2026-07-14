## Scheduled Task Management

- Keep editor state in value snapshots. Re-resolve definitions and Projects through `ScheduledTasksViewModel` when the user commits an action.
- Route create, edit, pause, resume, delete, and Run now preparation through `ScheduledTaskMutationService`; never mutate `ScheduledTask` rows from a view.
- Treat edits and deletion as future-definition changes. Active runs continue from their immutable snapshots.
- Keep recurrence fields structured and preserve the selected IANA timezone. Do not expose raw RRULE input.
- Keep folder grants as native folder selections and display their full paths in accessibility help.
