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
- Treat `AppState.selectedSidebarItem` thread references as selection tokens, not proof that the backing SwiftData row is still readable. Re-resolve the thread with `ModelContext.resolveThread(id:)` and fetch live conversations before reading thread relationships for toolbar actions, notification routing, diff actions, or launch-selection persistence.
- On first appear, sync the dock badge with `notificationManager.refreshBadgeCount()`; do not also call `handleAppVisibilityChanged()`. Mark-read of the restored active conversation is driven by the `.onChange(of: activeConversationId)` observer, which fires on the SwiftUI pass after `restoreLastOpenThreadSelectionIfNeeded()` mutates `appState`. Calling `handleAppVisibilityChanged()` from `onAppear` duplicates that mark-read and enqueues an extra chained badge task.

## Command Dispatch

`handlePendingCommand(_:)` in `ContentView+Commands.swift` wraps every `AppState.CommandRequest` branch in one `Task { @MainActor in … }` with a shared `defer` that clears `appState.pendingCommand` only if its id still matches the captured `commandID`. Do not clear `pendingCommand` inline inside a specific branch — even for synchronous work like presenting a sheet — or stale-id semantics diverge between command kinds and racing commands can nil out a newer one. When adding a new `CommandRequest` case, delegate any async work to a helper that accepts the captured `commandID` and checks it after each `await` before mutating `appState.selectedSidebarItem` or surfacing errors.

## Keyboard Shortcuts

App-wide modifier-key shortcuts live in `KeyboardShortcut+Alveary.swift` as static extensions on `KeyboardShortcut`. The **Focus And Keyboard Coordination** section in `Alveary/Views/AGENTS.md` still owns the placement rule (menu registration beats toolbar-button registration because menu items dispatch through the scene responder chain and stay focus-independent); this section covers *how* to define and reference a shortcut so the binding and its tooltip cannot drift.

- **Define each shortcut once as a `static let` on `KeyboardShortcut`.** `static let toggleDiffViewer = KeyboardShortcut("d", modifiers: [.shift, .command])`. Reference the constant from the `CommandGroup(...)` menu entry and from the matching toolbar button's tooltip — do not hand-write `KeyEquivalent` + `EventModifiers` literals at the call site. Rebinding then touches a single line.
- **Register the shortcut on a menu entry in `AlvearyApp.commands`, not on the toolbar button.** The toolbar button's `.help(...)` tooltip is the only place that renders the binding to the user; do not also attach `.keyboardShortcut(...)` there or the shortcut has two owners.
- **Build tooltips with `KeyboardShortcut.displayString`.** `"\(label) (\(KeyboardShortcut.toggleDiffViewer.displayString))"` renders as `"Hide Diff Viewer (⇧⌘D)"`. `displayString` reads the binding's modifiers and key directly (via `KeyEquivalent.displaySymbol` for special keys like `.return`, `.escape`, arrows, etc.), so the displayed literal is derived from the active binding instead of a hand-written string.
- **Route menu shortcuts through `FocusedValues+Alveary.swift` when the action depends on view-local state.** Two cases both justify the pattern:
    - **Context-scoped shortcut.** Applies only while a specific view is mounted — e.g. ⌘T "New Conversation" needs a `ThreadDetailView`. `.disabled(action == nil)` greys the menu item out when that view is not in the focused scene.
    - **App-wide shortcut whose action reads view-local state.** Always enabled while the root view is mounted, but still needs a focused-value hop because the action closure captures `@State` it cannot reach from the scene menu — e.g. ⇧⌘T "Show/Hide Terminal" must call `TerminalManager.ensureSelection()` before flipping `appState.isTerminalPaneVisible`, and `terminalManager` is `ContentView`'s `@State`. Calling the `AppState` mutator directly from the menu button would skip the pre-flip setup, and wiring the setup through a `.onChange` observer runs it *after* the pane re-renders, briefly showing stale state.
    - **How to apply either case.** In order:
        1. Add a `FocusedValueKey` whose `Value` is the action closure (`@MainActor () -> Void`).
        2. Publish it via `.focusedSceneValue(\.<name>, { ... })` from the owning view.
        3. Wrap the `Button` inside `AlvearyApp.commands` in a small private `View` struct that reads `@FocusedValue`.
        4. If the button title needs to track a mutable flag (e.g. "Hide Terminal" vs. "Show Terminal"), give the struct a plain `var appState: AppState` stored property — not `@Bindable`. See the field-level comment on `ToggleTerminalPaneCommandButton` for the rationale.
        5. Keep the focused value a closure; do not try to carry label state through it.
        6. Do not inspect `appState.selectedSidebarItem` at the menu layer or duplicate the view's private logic (e.g. `ThreadDetailView.createConversation()`, `ContentView.toggleTerminalPane()`).
