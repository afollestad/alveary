## App Lifecycle And Root Layout

These instructions cover the app entry point, `AppDelegate`, and the root `ContentView` scaffolding under `Alveary/App/`.

## macOS Lifecycle and Concurrency

- Keep `NSApplicationDelegate` implementations such as `AppDelegate` on `@MainActor`.
- When Swift 6 strict concurrency and AppKit interop fight each other in lifecycle code, prefer small explicit seams over broad workarounds: use injected dependencies for startup/shutdown behavior, and use `@preconcurrency import AppKit` only when needed to bridge AppKit/Objective-C sendability gaps.
- `.appWillTerminate` is an early shutdown contract, not a best-effort hint. Observers that own teardown required before process exit, such as file watchers or debounce tasks, must complete synchronously on the main actor rather than queueing follow-up cleanup behind `Task` hops.
- Shutdown paths that must complete before process exit should not rely on queued `Task { @MainActor ... }` cleanup. Prefer synchronous main-actor teardown for observer-driven lifecycle work that must happen before blocking termination waits.
- To hop to the main actor from an AppKit or `UserNotifications` delegate callback that is not guaranteed to run on main (for example a `UNUserNotificationCenterDelegate` method), use `Task { @MainActor in ... }`. Do not combine `DispatchQueue.main.async` with `MainActor.assumeIsolated`; the GCD hop plus an isolation assertion is strictly worse than a single `Task` hop. `MainActor.assumeIsolated` is still the right choice inside callbacks already delivered on main — for example, `NotificationCenter` observers registered with `queue: .main` or synchronous `deinit` work on a `@MainActor` type.

## Layout And Launch Restore

- The app layout uses a two-column `NavigationSplitView` with a conditional right-pane `HStack` detail split. Do not switch the diff pane back to native three-column `NavigationSplitViewVisibility` control on macOS 26; it does not behave correctly for programmatic right-pane toggling.
- Launch-time "re-open last thread and conversation" restore is exact-match and best-effort. Only restore when both persisted `lastOpenThreadID` and `lastOpenConversationID` still resolve to the same live, unarchived thread/conversation pair; otherwise clear the saved IDs and fall back to the normal empty selection state.
- On first appear, sync the dock badge with `notificationManager.refreshBadgeCount()`; do not also call `handleAppVisibilityChanged()`. Mark-read of the restored active conversation is driven by the `.onChange(of: activeConversationId)` observer, which fires on the SwiftUI pass after `restoreLastOpenThreadSelectionIfNeeded()` mutates `appState`. Calling `handleAppVisibilityChanged()` from `onAppear` duplicates that mark-read and enqueues an extra chained badge task.

## Command Dispatch

`handlePendingCommand(_:)` in `ContentView+Commands.swift` wraps every `AppState.CommandRequest` branch in one `Task { @MainActor in … }` with a shared `defer` that clears `appState.pendingCommand` only if its id still matches the captured `commandID`. Do not clear `pendingCommand` inline inside a specific branch — even for synchronous work like presenting a sheet — or stale-id semantics diverge between command kinds and racing commands can nil out a newer one. When adding a new `CommandRequest` case, delegate any async work to a helper that accepts the captured `commandID` and checks it after each `await` before mutating `appState.selectedSidebarItem` or surfacing errors.
