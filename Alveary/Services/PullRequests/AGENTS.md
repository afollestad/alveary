## Pull Request Services

App-scoped pull-request services that are neither the tool surface nor the client: `PullRequestLinkService`, `PullRequestAgenticThreadService`, `PullRequestAgenticThreadActivity`, `PullRequestSummaryHandoff`, and `PullRequestReviewProposalOutcomeRecorder`. The `alveary_host` tools are the nested `HostTools/` scope and the GitHub client is `GitHub/`; the dependency runs one way, so nothing under `GitHub/` may reach the host tools, linking, SwiftData, or MCP.

**Keep a rule here only when the code that would violate it is not the code that documents it.** Mechanism whose only reader is its own file belongs in a doc comment: `PullRequestAgenticThreadStart`, `PullRequestAgenticDispatchOutcome`, `PullRequestAgenticThreadService`, `PullRequestAgenticThreadActivity`, `+Workspace.swift`'s ladder, `PullRequestLinkService.link`, `PullRequestSummaryHandoff`, and `PullRequestReviewProposalOutcomeRecorder` each carry theirs.

### Linking

- `PullRequestLinkService` is the app-scoped link store; `Alveary/ViewModels/PullRequests/Links/AGENTS.md` owns its split with `PullRequestLinksViewModel` and the `detail:`/`summary:` handovers a caller with a fresh copy may use, and `Alveary/Services/Threads/AGENTS.md` owns the `link_pr`/`unlink_pr` tools that write through it.

### Agentic Threads

`PullRequestAgenticThreadService` spawns both footer routes; add a caller by using the service, never by copying it.

- **A `.review` thread is project-less, never a project one.** Every step runs through the host tools against GitHub, so it needs no checkout — and a project worktree would have the agent reviewing whatever is checked out there rather than the pull request. `grantedRoots` stays empty for both kinds: the workspace root is the only grant either needs.
- **Seed resolution degrades, it does not refuse.** A pinned provider that is no longer ready, or a model or effort the provider retired, falls back to what a typed thread would get; only "no ready provider at all" throws. The trigger is a footer button with nowhere to explain a rejection, unlike `create_thread`, whose caller can correct itself.
- **Both routes for a job run one path, and the instructions tool is the seam.** The footer spawns a thread whose first prompt is a short request — *not* the instructions — and the agent fetches those itself, exactly as it does when the user asks in a thread that already exists. So the guidance cannot drift, both show the same card, and only the prompt differs. Do not inline the instructions here to save a round trip.
- **A section pick seeds creation and never moves an existing thread.** `insertTaskThread` throws on a vanished section, so `resolvedPlacement` validates first and degrades to `Tasks`; its doc comment owns why. Never `.project` — both kinds stay projectless, which is what makes a section render at all.
- **Nothing may move in front of `start`'s return** except a refusal. Everything ahead of it delays the moment the footer's spinner stands for a real thread, and delays the thread itself; only the checkout pre-flight earns the spot, because it is a local read that decides whether to create anything at all.
- **`dispatch` links before dispatching**, best-effort, regardless of `automaticallyLinkPullRequests`. Linking first means transcript detection finds the pull request already linked and asks no redundant "link this?" question under the prompt. A GitHub hiccup must not stop the thread, and a racing auto-link resolves as `alreadyLinked`. Re-resolve the thread after that `await` rather than carrying the model across it.
    - **Give it a detail *and* a summary** — between them the link never needs the network, which is the difference between reliably linked and merely attempted.
    - **A link failure rides the outcome value, never a throw.** A throw means the prompt never went out and ends the working indicator; the run is in fact working, so throwing would take the spinner off a live thread. One consumer either way — do not give it a second.

#### The Checkout Ladder

`+Workspace.swift` resolves where an `.addressFeedback` thread runs; its doc comment owns the rung order, the refusal, and the branch probe. These are the constraints behind them.

- **The ladder refuses rather than degrading past its last rung.** No borrow and no project for the repository throws `StartError.projectMissing` before anything is created, and the pane shows it as a modal. Addressing feedback edits and pushes, so a scratch directory only buys a wasted turn.
- **A borrow is branch-verified, never trusted.** `isOnBranch` compares against `thread.branch`, which every Task thread leaves nil, so the link alone would hand the agent whatever the lender had checked out. Only git settles it — behind `start`'s return, and never by checking the lender's tree out from under it.
- **`thread.branch` stays nil on every rung, and so do `worktreePath` and `useWorktree`.** `cleanupOwnedTaskWorktree` computes `branchToDelete` from `branch` and `branch -D`s it when git still reports it on the worktree — here that is the user's live pull request head. A Task carries its checkout in the descriptor alone.
- **A borrow is `.projectLocal`, whose cleanup does nothing**, so deleting the thread leaves the lender's checkout intact. Only rung 3's own worktree is `.projectWorktreeOwned`.
- **A lender must have a source project.** A private workspace is a scratch directory rather than a checkout, and it belongs to a thread whose deletion would remove it — that filter is also what keeps the new thread from lending to itself once linking has put it in rung 1's results.
- **Branch-match must precede creating a worktree**: `git worktree add` refuses a branch already checked out elsewhere.

### Review Proposal Outcomes

- `PullRequestReviewProposalOutcomeRecorder` writes the hidden marker that resolves a proposal card, mirroring scheduling's. `Alveary/Services/PullRequests/HostTools/AGENTS.md` owns proposing, `Alveary/ViewModels/PullRequests/Review/AGENTS.md` owns confirming and the clear-then-mark ordering this participates in.
- **A staged comment's anchor is a fingerprint, not just a line number.** `ReviewProposalAnchorResolution` is the one place that decides where a comment publishes; content at the stored line is what proves nothing moved, because inserting a line above leaves that *number* occupied by different code. Relocate only on an unambiguous match — a wrong one posts review feedback onto code it was not written about.
- `PullRequestReviewProposalPreviewCache` persists a proposal's narrowed hunks so its card paints without a round trip, on the paint-then-refresh terms `Alveary/Services/PullRequests/GitHub/AGENTS.md` states for `PullRequestsListCache`. It lives here rather than under `GitHub/` because propose time writes it, and `ReviewProposalDiffNarrowing` beside it is the one narrowing both that seed and the card's refresh run through.
