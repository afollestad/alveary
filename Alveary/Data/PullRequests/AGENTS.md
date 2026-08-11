## Pull Request Data

These instructions cover `Alveary/Data/PullRequests/` — the JSON columns behind linked pull requests, transcript link prompts, the host-tool retry ledger and review-proposal envelope on `Conversation`, plus the value types and notifications those columns travel with. `Alveary/Data/AGENTS.md` owns the models these companions extend. Behavior lives elsewhere: `Alveary/Services/PullRequests/AGENTS.md` and `Alveary/Services/PullRequests/HostTools/AGENTS.md` own writing and propose time, `Alveary/ViewModels/PullRequests/Links/AGENTS.md` owns the link store, and `Alveary/ViewModels/Conversation/AGENTS.md` owns transcript link detection.

> **READ FIRST — fetch shapes are centralized.** `PullRequestLinkedOwnerLookup` declares `#Predicate`s here; before adding another, consult the **Fetch Predicates** section in `Alveary/Data/AGENTS.md` for the one-level-deep keypath rule and the bind-to-a-local cost rule.

**Keep a rule here only when the code that would violate it is not the code that documents it.** Mechanism whose only reader is its own file belongs in a doc comment: `LinkedPullRequestStorage`'s failure tolerance and empty-clears-to-`nil`, `PendingPullRequestPromptStorage` mirroring it, `LinkedPullRequest.summary` being a refetchable cache, `PendingPullRequestPrompt.messageEventID` anchoring a prompt to its bubble, `OwnedPullRequestLink.sourceLabel`, `Project.aggregatedPullRequestLinks`' dedup and its per-render pre-check, `PullRequestLinkedOwnerLookup`'s fetch-then-decode shape, `PullRequestReviewProposalRecord`'s version guard and append-only comment positions, and each notification type's reason for being a notification all carry theirs.

### Columns, Not Child Models

- **These are JSON columns rather than child `@Model`s, and that is the precedent to follow.** A child model adds a relationship every `ModelContainer` must register — one production site against dozens of hand-listed test containers. `Alveary/Services/PullRequests/HostTools/AGENTS.md` cites this for the review proposal.
- **Keep every column optional with no `init` parameter.** `nil` migrates pre-field stores, and the `init` omission stops `makeForkThread` from carrying links, open questions, or a scan fence onto a fork — which gets its own branch and therefore its own pull requests.
- **Address a link's owner through `PullRequestLinkOwner`** plus `ModelContext.linkedPullRequests(for:)` / `setLinkedPullRequests(_:for:)`, never by branching per model. `AgentThread` and `Project` share one codec so their two columns cannot drift.
- **Keep new reverse queries on the fetch-then-decode shape** rather than promoting links to a relationship; `#Predicate` cannot see inside a JSON column.
- **Nothing enforces uniqueness across owners.** The same pull request may be linked from several threads and projects at once; only per-owner duplicates are rejected, by `PullRequestLinkService`.

### Link Prompts

- **The watermark advances only for a message that yielded identifiers**, so ordinary traffic does not dirty the thread row. A message at or before it never prompts again.
- **A message naming more than `ConversationViewModel.maximumDetectedPullRequestsPerMessage` pull requests prompts for none of them**, and auto-links none either. It is enumerating them — a `list_involved_prs` answer runs to dozens — not discussing one, and every identifier would otherwise stack its own question under the bubble.
    - The watermark still advances: the message was scanned and deliberately produced nothing.
