## System Menu Bar Item

These instructions cover Alveary's status-bar item under `Alveary/Services/MenuBar/`.

## Routing

- **Never reach `AppState` from here.** It is created in `AlvearyApp` and only the view tree can see it, so actions enqueue on `MenuBarCommandRouter` or `NotificationRouter` and `ContentView` drains them. Enqueuing before the window mounts is fine — `ContentView.onAppear` replays whatever is pending.
- **Reveal before enqueueing.** Every action except Quit calls `MainWindowPresenter.activate()` first, which re-creates the scene when the user has closed it; a request routed into a windowless app would sit pending.
- `MenuBarCommandRequest` carries a `UUID` so picking the same item twice in a row is still a new value the root observes.

## Menu Contents

- **Rebuild in `menuNeedsUpdate(_:)`.** The menu only exists while it is open, so a click-time query is cheaper than observing thread changes — do not add store observers to keep it in sync.
- **Recency and openability are not defined here.** `AgentThread.isListableHostToolThread` says which threads a user can be sent to and `AgentThreadOrdering` says how recent they are; copying either predicate would let the menu drift from the host tool that shares it.
- Key equivalents are labels only — a status-item menu does not participate in key-equivalent matching, so the bindings stay owned by `AlvearyApp.commands`. Derive them from the `KeyboardShortcut` constants through `MenuBarKeyEquivalent`; the define-once rule lives in `Alveary/App/AGENTS.md`. Quit's ⌘Q is the system-standard literal, not an app binding.
- The icon's asset name lives once in `MenuBarController.templateImageName`, and the image stays `isTemplate` so macOS tints it for light and dark menu bars.

## Lifecycle And Tests

- `AppDelegate` starts and stops the controller; `applySettings()` follows `AppSettings.showsMenuBarIcon` through an `.appSettingsChanged` observer so the toggle takes effect live. `stop()` is synchronous, per the shutdown rule in `Alveary/App/AGENTS.md`.
- **The status-item factory pair is the only test seam.** Hosted tests get a no-op factory from `AppComponent+MenuBar.swift` so the real install/uninstall lifecycle still runs without an icon appearing in the runner's menu bar — suppress the chrome, never the lifecycle.
- **A test driving menu actions must hold the controller.** `NSMenuItem.target` is weak, so a temporary controller leaves every item with a dead target and `performActionForItem(at:)` silently does nothing.
