## App Shortcuts And Capture

These instructions cover `Alveary/App/Shortcuts/` — app-wide `KeyboardShortcut` constants, the `FocusedValues` that carry view-local actions to scene menus, and the app-shot capture trigger and its routing.

> **READ FIRST:** The placement rule — menu registration beats toolbar-button registration — lives in **Focus And Keyboard Coordination** in `Alveary/Views/AGENTS.md`. This scope covers how to *define* and *reference* a shortcut so a binding and its tooltip cannot drift.

**Keep a rule here only when the code that would violate it is not the code that documents it.** Mechanism whose only reader is its own file belongs in a doc comment: `KeyboardShortcut.displayString`, the shortcut constants' own header, `NewConversationAction`, and `DiffViewerCommand` each carry theirs.

### Defining A Shortcut

- **Define each one once as a `static let` on `KeyboardShortcut`**, and reference that constant from both the `CommandGroup(...)` menu entry and the matching toolbar button's tooltip — no hand-written `KeyEquivalent` + `EventModifiers` literals — so rebinding touches one line.
- **Register it on the menu entry, not the toolbar button.** The button's `.help(...)` only renders the binding; also attaching `.keyboardShortcut(...)` gives the shortcut two owners.

### Focused Values

- **Route a menu shortcut through `FocusedValues+Alveary.swift` when its action depends on view-local state.** Two cases qualify: a *context-scoped* shortcut that applies only while a view is mounted (⌘T "New Conversation" needs a `ThreadDetailView`; `.disabled(action == nil)` greys it out otherwise), and an *app-wide* shortcut whose closure captures state the scene menu cannot reach (⇧⌘T must set up a shell session before flipping `appState.isTerminalPaneVisible`, and `terminalManager` is `ContentView`'s `@State`). Calling the `AppState` mutator directly skips the pre-flip setup; an `.onChange` observer runs it a render too late.
- **How to apply**, in order:
    1. Add a `FocusedValueKey` whose `Value` is the action closure (`@MainActor () -> Void`).
    2. Publish it via `.focusedSceneValue(\.<name>, { ... })` from the owning view.
    3. Wrap the `Button` inside `AlvearyApp.commands` in a small private `View` struct reading `@FocusedValue`.
    4. If the title tracks a mutable flag ("Hide Terminal" vs "Show Terminal"), give that struct a plain `var appState: AppState` — not `@Bindable`; see the field comment on `ToggleTerminalPaneCommandButton`.
    5. Keep the focused value a closure and carry no label state through it — unless anything inside the window tree reads it, in which case it must instead be an `Equatable` wrapper with stable identity. `NewConversationAction` and `TogglePullRequestsActionKey` document both sides of that choice.
    6. Do not inspect `appState.selectedSidebarItem` at the menu layer or duplicate the view's private logic (`ThreadDetailView.createConversation()`, `ContentView.toggleTerminalPane()`).

### App-Shot Capture

- **Capture is the one shortcut that is not menu-owned**, because it must fire while Alveary is backgrounded — which is why `AppShotCoordinator` registers it with the system instead. The default stays a regular chord (`⌃⇧S`): `⌘⌘` collides with Codex's trigger, and a regular chord needs no Input Monitoring where the modifier-only path does. Route missing permissions through `AppShotPermissionRequester` / `AppShotPermissionDragGrantAssistant`, never composer banners.
- **`ContentView` is the sole trigger observer and destination router.** Every capture source converges on `pendingTriggerID` — anything that is not the global shortcut, such as the composer `+` menu's "Attach <app>" row, calls `AppShotCoordinator.requestCapture()` rather than the capture controller, and a new affordance does the same. Drain the trigger from both the observer and the `onAppear` replay, since a press taken with the window closed has no `.onChange` to fire.
- **Never redirect a capture once storage begins.** Resolve and revalidate a persistent-ID destination before storage, let project/no-thread routes create or reuse the provisional draft only after capture preparation succeeds, and if selection changes mid-storage finish staging into the claimed conversation without navigating back.
- **Failures before storage are app-level.** Storage and staging failures use the selected conversation's `lastTurnError` only while it is mounted, else stay app-level so they cannot hide in an unmounted runtime state.
