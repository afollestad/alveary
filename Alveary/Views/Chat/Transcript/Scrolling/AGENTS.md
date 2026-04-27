## Transcript Scrolling

Rules for `ChatView+Transcript.swift`, `ChatView+Transcript+ScrollBehavior.swift`, and small transcript-scrolling companions.

> **READ FIRST:** Focus and keyboard rules are centralized in `Alveary/Views/AGENTS.md`.

## Follow Mode

- Keep follow-mode split across three mechanisms:
    - Content-size growth: `.defaultScrollAnchor(.bottom, for: .sizeChanges)`, gated on `isFollowing`.
    - New messages/stream chunks: explicit `scrollToBottom` from `events.count`, pending queue count, and `streamingText`.
    - Container shrinks: `shouldPreserveFollowMode` in `onScrollGeometryChange`.
- Only container shrinks trigger preserve-follow. Growth pulls toward bottom by itself.
- The offset guard is `!offsetDecreased`, not `!offsetChanged`.
- Do not re-add `contentGrew` to `shouldPreserveFollowMode`; bubble expansion emits animation frames that would fight the bubble animation.

## Layout

- Use `scrollPosition.scrollTo(edge: .bottom)`, not `scrollTo(id:)`.
- Edge scroll avoids `LazyVStack` row-height estimate blanks on thread reopen.
- Do not apply `.scrollTargetLayout()` to the transcript `LazyVStack`.
- Keep `transcriptBottomInset` as trailing `.padding(.bottom, ...)` on the `LazyVStack`, not as a trailing `Color.clear` child.

## Following State

- `isFollowing` is the source of truth.
- Route geometry fallback through `ChatTranscriptScrollBehavior.nextFollowingState(...)`.
- Set `true` when `isNearBottom`.
- Set `false` only when `shouldCancelProgrammaticScroll` confirms a real user drag.
- Do not raw-write `isFollowing = newMetrics.isNearBottom`; streaming can momentarily report far from bottom before the anchor catches up.

## Retries And Progressive Scroll

- `scrollToBottom(retries:)` has two strategies:
    - `.triple`: immediate, next-runloop, and 150ms retries plus watchdog. Use for thread entry and content-growth callers.
    - `.single`: immediate plus watchdog. Use container-shrink preserve-follow; geometry reissues cover the animation.
- Far-up `forceFollow` uses `performProgressiveScrollToBottom`.
- Gate progressive scroll on `forceFollow && distance > 400pt && content > viewport`.
- While progressive scrolling runs, suppress retry-ladder reissues.
- Refresh the watchdog on every progressive step and suppressed reissue.
- Reset `isProgressiveScrolling = false` on every exit path.
- Cap recursion with `transcriptProgressiveScrollMaxSteps`.
- Guard against concurrent chains with `!isProgressiveScrolling`.

## Pending Scroll Watchdog

- `transcriptProgrammaticScrollTimeout` is a reset-on-progress watchdog, not a fixed deadline.
- `schedulePendingProgrammaticScrollTimeout()` stamps a UUID token.
- The delayed closure clears pending state only if its token still matches.
- Call it from initial `scrollToBottom` and every reissue branch.
- Do not overwrite `isFollowing` in the watchdog.
- Do not issue corrective `scrollTo` from the watchdog.

## Pending Modes

- `.jumpToLatest` is not one-shot.
    - Container shrink or content growth reissues bottom scroll while pending.
    - Do not clear pending on transient `isAtBottom`; large-thread materialization can report a false bottom.
    - Pending clears after the watchdog sees 400ms with no growth.
- `.preserveFollow` reissues only on container shrinks.
    - Exclude content growth; `.defaultScrollAnchor` owns it.
    - Exclude container growth; it naturally pulls toward bottom and clears when at bottom.

## Cancel Guards

- User intent wins: check `shouldCancelProgrammaticScroll` before reissuing.
- All four guards are required:
    - `offsetDecreased`, not merely changed.
    - `distanceGrew`.
    - `!newMetrics.isNearBottom`.
    - `offsetDrop < transcriptCancelMaxPerTickDrop` (250pt).

## Turn End

- When a turn ends and the user was following, re-pin after `forceFullRebuild`.
- Call `scrollToBottom(forceFollow: true)` when `isFollowing`.
- Skip when the user scrolled away.
- Use jump-to-latest behavior, not preserve-follow; rebuild layout shifts need content-growth reissues.
