## Pull Request View Models

These instructions apply to files directly under `Alveary/ViewModels/PullRequests/` — the list, its buckets, and the search and status filters over them. Three scopes sit below: `Pane/AGENTS.md` for the detail pane's sessions and loads, `Review/AGENTS.md` for comments and review proposals, and `Links/AGENTS.md` for the link store. Transcript link detection is `Alveary/ViewModels/Conversation/AGENTS.md`, the pane session/generation contract is `Alveary/ViewModels/AGENTS.md`, and `Alveary/Views/PullRequests/AGENTS.md` owns the user-facing half.

**Keep a rule here only when the code that would violate it is not the code that documents it.** The barrier in `apply(_:)`, `applyMore`'s untouched `fetchedAt`, `markAllBucketsStale()`'s cursor clearing, `saveListCache()`'s first-page truncation, both cancellation guards' reason for testing the flag rather than the thrown type, `loadPhase(for:)`'s derivation, `prefetchAtLaunch()`'s idempotent delegation, and the `searchQuery` / `activeSearchQuery` split each carry theirs.

### List Loading

- **Rows reach `items` only through `bucketStates` and `rebuildItems()`.** `items` keeps a private setter to enforce it, so `applyStatus(_:toRow:)` writes through every bucket holding the row rather than the derived list. `applyStatus` is the only writer of `items` outside a refresh.
- **Keep the per-bucket fan-out here even though the service fans out too.** Handing `GitHubPullRequestsService` several buckets would return one merged result whose failed bucket is only a warning string, and `bucketFailures` needs the typed error per bucket to pick between an error banner and `.unavailable`. `Alveary/Services/PullRequests/GitHub/AGENTS.md` owns why the split is worth it.
- **A tab settles once, and late buckets merge in.** Switching tabs paints the buckets already held and merges the rest as they land — legible because the All tab is sectioned, so a late bucket appends rather than reshuffles. Do not "fix" this back into an eager fetch of everything.
- **Keep the client-side status comparison alongside the search qualifier.** It is what leaves the qualifier only ever able to make the list *sparse* rather than *wrong*: `items` still answers the previous search between a status change and its reload, and `applyStatus` has no reload behind it.
- **Gate any new automatic load on `AppSettings.pullRequestsEnabled`, and delegate rather than reaching `load` directly.** `prefetchAtLaunch()` and the screen's own `.task` are one path through `refreshForScreen()` sharing one freshness throttle; a second entry point races the warm instead of consuming it.
    - **Accepted:** a failed prefetch opens the screen on `.unavailable` for a frame before its own load retries — the failure records no `bucketStates` entry, so the throttle never suppresses that retry.

### Search

- **Point new search-derived state at `activeSearchQuery`, not `searchQuery`.** The first is committed after the debounce and already trimmed; the second republishes per keystroke, so reading it leaves the rows and the empty-state copy disagreeing mid-debounce.
- **`searchDebounce: .zero` is the seam tests and snapshot fixtures rely on.** A fixture left on the production duration renders the unnarrowed list.
