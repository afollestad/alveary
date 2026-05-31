## Transcript Scrolling

Rules for `ChatView+Transcript.swift`, `ChatView+Transcript+ScrollBehavior.swift`, and small transcript-scrolling companions.

> **READ FIRST:** Focus and keyboard rules are centralized in `Alveary/Views/AGENTS.md`.

## AppKit Scroll Ownership

- **Keep the transcript scroll owner in AppKit.** SwiftUI lazy-list recycling and measurement were not adequate for Alveary's variable-height transcript UX at the time of writing; scroll position and performance must be controlled by explicit AppKit row frames.
- **Own scrolling in AppKit.** New transcript-container work should route through `NSScrollView` plus an AppKit document/layout view; keep SwiftUI bridges as data and action adapters.
- **Start eager.** Prefer deterministic vertical layout with stable row frames before adding recycling or virtualization.
- **Cache measurements, not rows.** Keep every row mounted; optimize long transcripts with dirty height measurement keyed by row id and width, not viewport recycling.
- **Hydrate by viewport margin.** Markdown text rows hydrate after layout and scroll when their fixed shells intersect the visible rect plus the prefetch margin; hydration must not change document height.
- **Prewarm markdown before layout.** AppKit bridge updates should asynchronously prewarm renderer-neutral markdown documents before installing cold text rows so exact row measurement does not parse markdown on the main actor.
- **Name dirty rows.** Row height invalidation should pass the stable row id when available. Use all-row invalidation only for width or unknown-row changes.
- **Batch configure invalidations.** If row views invalidate while a bridge is rebuilding rows, collect those row ids and apply them with `configure(rows:dirtyRowIDs:preserveBottomIfFollowing:)`.
- **Skip unchanged dirty-row frames.** Named dirty-row invalidations that remeasure to the same frames should publish metrics without reapplying downstream frames or restoring anchors; unnamed fallback invalidations stay conservative.
- **Remeasure typography changes.** Settings-driven `TranscriptTypography` changes are row configuration changes; cached AppKit rows should invalidate dirty heights while preserving anchors.
- **Restore explicit anchors.** Preserve position by row identity plus offset within row for prepend/pagination, expansion, streaming growth, and turn-end rebuilds.
- **Publish metrics.** AppKit containers should emit `ChatTranscriptScrollMetrics` after layout, content changes, and scroll moves so follow-mode logic can stay shared.
- **Cancel stale pagination.** Increment the pagination generation when the user scrolls during an in-flight prepend; never apply an anchor captured under an older generation.
- **Invalidate from rows.** AppKit rows should call their height invalidation callbacks when expansion, streaming, task toggles, tables, or code overflow change their fitted height.
- **Animate row frames together.** Expansion and collapse change one row plus every row below it; collect frame updates and run them in one `NSAnimationContext` transaction so displaced rows move on the same curve instead of lagging behind.
- **Avoid reentrant layout.** If height invalidation fires while rows are being measured or frames are being applied, ignore or defer it; reentering AppKit layout from those phases causes staggered animations and unstable measured frames.
- **Clamp horizontal scroll.** The transcript scroll container is vertical-only even when child code blocks own horizontal overflow. Keep `NSClipView.bounds.origin.x` at `0`, and do not fix horizontal drift by changing transcript content width or switching measurement to clip-view width.
- **Adapt through row factories.** Convert `ChatItem` values into cached AppKit row views by stable row id so refreshes do not reset expansion or prompt state.
- **Bridge transient rows.** Pass live thinking, streaming, and interrupted state separately from persisted `ChatItem`s; use stable transient ids.
- **Measure the bridge.** The AppKit surface reports the SwiftUI wrapper width so shared bubble-width caps stay aligned with the host layout.
- **Bridge narrowly.** SwiftUI representables should only pass transcript data, state, and actions into the AppKit owner; scroll math stays in AppKit.

## Following State

- `isFollowing` is the source of truth.
- Route AppKit metrics fallback through `ChatTranscriptScrollBehavior.nextFollowingState(...)`.
- Set `true` when `isNearBottom`.
- Set `false` only when `shouldCancelProgrammaticScroll` confirms a real user drag.
- Do not raw-write `isFollowing = newMetrics.isNearBottom`; streaming can momentarily report far from bottom before the anchor catches up.

## Bottom Scroll Requests

- `scrollToBottom(retries:)` has two strategies:
    - `.triple`: immediate, next-runloop, and 150ms AppKit request increments plus watchdog. Use for thread entry and content-growth callers.
    - `.single`: immediate AppKit request plus watchdog. Use container-shrink preserve-follow; metrics reissues cover the animation.
- Keep retry requests as `appKitScrollToBottomRequest` increments so the representable coordinator owns the actual scroll command.
- Unanswered prompt presentation is a row-top pin, not a bottom scroll.
  Route it through `AppKitTranscriptRowTopScrollRequest`, keep the prompt row stable at the viewport top,
  and let transient thinking rows mount underneath without stealing the pin.

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
    - Exclude content growth; the AppKit container owns row-height anchoring.
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
