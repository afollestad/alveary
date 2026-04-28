## Notifications

These instructions cover `DefaultNotificationManager`, `NotificationRouter`, and `NotificationTapDelegate` under `Alveary/Services/Notification/`.

## Invariants

- OS notification `identifier` equals the `conversationId`. New events for the same conversation replace any pending banner (so stale "finished working" notifications don't pile up once newer events arrive), and `UNUserNotificationCenter.removeDeliveredNotifications(withIdentifiers:)` can target precisely on mark-read. Do not change to a per-event UUID.
- Notification copy must name the actual state:
    - **Reserve completion copy for terminal work.** Do not use "finished working" for pending approval, `AskUserQuestion`, interim usage, or successful `tool_deferred` stops.
    - **Keep pending-action copy explicit.** Permission prompts should say what tool/action needs approval; `AskUserQuestion` prompts should include a short question summary.
- The dock badge count is "unread conversations whose thread is not archived." The predicate chains through an optional relationship (`conversation.thread?.archivedAt == nil`); archive/restore/delete flows must call `NotificationManager.refreshBadgeCount()` themselves because SwiftData does not emit `.agentStatusChanged` on those flows.
- `setBadgeCount` calls are serialized through `pendingBadgeUpdate = Task { _ = await previous?.value; ... }`. Rapid mark-unread / mark-read sequences would otherwise race and leave the dock showing a stale higher count. Do not "simplify" the chain away.
- "Actively viewing" (`isActivelyViewing`) means the app is in foreground *and* the specific conversation is selected. `isAppInForeground()` alone is not enough — a foreground app with a different conversation selected should still mark the event's conversation unread.
- Any code path that removes a conversation must dismiss its banner and clear its unread flag *before* the SwiftData delete. That both dismisses any pending OS banner and captures the post-mark-read unread count for the chained `refreshBadgeCount()` task; skipping it leaves an orphaned banner and a stale dock badge until the next event. Snapshot conversation IDs before thread/project-level removals and pass them to `NotificationManager.forgetConversations(withIDs:)`; use `markConversationRead(conversationId:)` directly when removing a single conversation inside a still-live thread (`ThreadDetailView.removeConversation`).
- `.agentStatusChanged` is a shared bus. Observers that rescan the filesystem on status changes (e.g. `DiffViewerViewModel`) must gate on `userInfo["signal"] is ActivitySignal`, because `DefaultNotificationManager` also posts on this name when flipping `isUnread` and those posts carry no `signal` key. Observers that refresh purely visual status (e.g. `SidebarViewModel`'s dot) should not gate — they want both kinds of post.

## Testing seams

- `DefaultNotificationManager` exposes closure properties (`setBadgeCount`, `onPostNotification`, `onDismissDelivered`, `isAppInForeground`, `setActiveConversationProvider`) for tests. The `setBadgeCount` closure is `async`; tests that assert on badge values must call `await manager.awaitPendingBadgeUpdate()` before reading the spy, since submission goes through the chained `Task`.
- `NotificationManagerTestFactory` wires a `NotificationSpy` to those seams; prefer that helper over constructing `DefaultNotificationManager` directly in tests unless you need to control chaining or observer wiring explicitly.
