# Pull Requests Screen

These instructions cover the pull-request browsing UI under `Alveary/Views/PullRequests/` — how the feature is entered and gated, plus the linked-pull-request popover that is one of those entries.

The surfaces themselves each have their own scope: `List/` (the screen, its rows and filters), `Pane/` (the detail pane, Overview, and timeline), `Comments/` (comment chrome, composer, attachments), and `Review/` (the review workflow wherever it renders, plus the footer and state changes).

## Entry Points And Gating

- **`AppSettings.pullRequestsEnabled` gates the whole integration.** It hides the sidebar row — the only entry point, so turning it off removes the screen and its `.task` refresh — *and* the thread toolbar's linked-pull-request button. The toggle lives in the Git settings tab; the screen's `onOpenGitSettings` is the route back. See `Alveary/Views/Sidebar/AGENTS.md` for the top-level-row geometry the gating obeys.
- **The detail pane has a second entry point: a thread's or project's linked pull requests.** `PullRequestLinksPopover` hands a stored `PullRequestSummary` to the same `requestDetails(_:origin:)` the screen's rows use, with `PullRequestPaneOrigin(owner:)` built from the *selection*. Pane *scoping* is not owner-aware — see `Alveary/App/Routing/AGENTS.md` for origin scoping and `Alveary/ViewModels/PullRequests/Links/AGENTS.md` for the link store.
    - **A left click opens the pane only when exactly one pull request is linked**; zero or several go to the popover, and a secondary click always opens it, so another can be linked without unlinking first.
    - **Every row keeps its true owner, and mutations route there.** In a project's aggregate, unlink removes the *thread's* link, pasting links to the selection itself, and status write-back lands on the rendered row's owner. `Project.aggregatedPullRequestLinks` documents how the aggregate is built.
    - **The popover and toolbar never fetch to render** — links carry a status snapshot, and opening one refreshes it. A network call behind the button would flicker the glyph on every selection change.
- **The Overview's linked-owners section is the reverse direction.** `PullRequestPaneLinkedOwners` `@Query`s link-holding owners through `PullRequestLinkedOwnerLookup` (see `Alveary/Data/PullRequests/AGENTS.md`), so it renders in the detail's first frame off local columns and hides itself when nothing links the pull request.
    - **Rows select their owner through `\.pullRequestLinkedOwnerOpenAction`**, injected at the pane's mount because the pane reaches neither `AppState` nor a `ModelContext`; `ContentView` re-resolves the carried `PullRequestLinkOwner`.
    - Its title names only the kinds present, and the glyph alone separates them — `folder` and `bubble.left.and.bubble.right`, matching the sidebar project row and the `list_threads` tool row — **so do not add a kind badge**.
    - **Every snapshot host of the Overview or the pane needs `assertMacModelSnapshot`**, since that section queries SwiftData; an empty container leaves it unrendered and keeps the unrelated baselines pixel-identical.
- **`pullRequestReferenceDateTick` lives here because both surfaces that render ages apply it** — the screen, and a pane opened from a thread's linked pull requests with the screen unmounted.
