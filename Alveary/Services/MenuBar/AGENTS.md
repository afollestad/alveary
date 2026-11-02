## System Menu Bar Item

These instructions cover Alveary's status-bar item under `Alveary/Services/MenuBar/`.

## Routing

- **Never reach `AppState` from here.** It is created in `AlvearyApp` and only the view tree can see it, so actions enqueue on `MenuBarCommandRouter` or `NotificationRouter` and `ContentView` drains them. Enqueuing before the window mounts is fine — `ContentView.onAppear` replays whatever is pending.
- **Reveal before enqueueing.** Every action except Quit calls `MainWindowPresenter.activate()` first, which re-creates the scene when the user has closed it; a request routed into a windowless app would sit pending.
- `MenuBarCommandRequest` carries a `UUID` so picking the same item twice in a row is still a new value the root observes.

## Menu Contents

- **Rebuild in `menuNeedsUpdate(_:)`.** The menu only exists while it is open, so a click-time query is cheaper than observing thread changes — do not add store observers to keep it in sync. The one observer, `MenuBarReviewRequestsMonitor.onChange`, exists for the icon's badge, not the menu.
- **Recency and openability are not defined here.** `AgentThread.isListableHostToolThread` says which threads a user can be sent to and `AgentThreadOrdering` says how recent they are; copying either predicate would let the menu drift from the host tool that shares it.
- Key equivalents are labels only — a status-item menu does not participate in key-equivalent matching, so the bindings stay owned by `AlvearyApp.commands`. Derive them from the `KeyboardShortcut` constants through `MenuBarKeyEquivalent`; the define-once rule lives in `Alveary/App/Shortcuts/AGENTS.md`. Quit's ⌘Q is the system-standard literal, not an app binding.
- The icon's asset name lives once in `MenuBarController.templateImageName`, and the image stays `isTemplate` so macOS tints it for light and dark menu bars.

## Pull Requests Needing Review

- **"Needs review" is the `.reviewRequested` bucket narrowed by the screen's own filter.** The monitor searches `AppSettings.pullRequestListFilter`'s status and narrows through `PullRequestListFilter.admits`, which `PullRequestsViewModel` also uses; never add a menu-only predicate or a second filter store. It reads the app-scoped service, as the host tool does — the window's view model is window-lived.
- **Page-one reads of the review bucket are shared both ways through `.pullRequestBucketRefreshed`.** The monitor's reads also replace their bucket in `PullRequestsListCache`, and `PullRequestsViewModel.applyBackgroundRefresh(_:)` owns when an open list takes one; the screen's own loads post from `apply(_:)`, and the monitor's `adopt(_:)` takes them. Keep the monitor's reads at `.firstPage`, whose size `PullRequestsViewModel.listPageSize` shares, or the list cannot take them.
- **A pull request handed to an agent review stays out of the list and badge until the review is submitted.** Starting one changes nothing GitHub searches, so `MenuBarAgentReviewHandoffs` reads Alveary's own state and owns when a released one returns. The hide is the menu's alone; keep it out of `PullRequestListFilter`, which the screen also narrows by.
- **Activation needs all three settings:** `showsMenuBarIcon`, `menuBarShowsPullRequestsNeedingReview`, and `pullRequestsEnabled` (`MenuBarController.listsPullRequestsNeedingReview`). The Menu bar settings tab disables its rows on the same three.
- **A pick opens the pull request in Alveary, never the browser.** `Alveary/App/Routing/ContentView+MenuBarCommands.swift` selects the Pull requests screen and opens a `.screen` pane, the same as a row tap there.

## Lifecycle And Tests

- `AppDelegate` starts and stops the controller; `applySettings()` follows `AppSettings.showsMenuBarIcon` and the review-list settings through an `.appSettingsChanged` observer so the toggles take effect live. `stop()` is synchronous, per the shutdown rule in `Alveary/App/AGENTS.md`.
- **Hosted tests suppress the chrome and the network, never the lifecycle.** `AppComponent+MenuBar.swift` gives them a no-op status-item factory and a monitor built with `pollsGitHub: false`, so install, uninstall, and the poll loop all still run without an icon in the runner's menu bar or a `gh` read against the developer's account.
- **A test driving menu actions must hold the controller.** `NSMenuItem.target` is weak, so a temporary controller leaves every item with a dead target and `performActionForItem(at:)` silently does nothing.
