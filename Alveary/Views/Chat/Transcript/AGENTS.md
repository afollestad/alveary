## Chat Transcript

Rules for `ChatView+Transcript*.swift` — scroll coordination, follow-mode, and markdown-link resolution inside `ChatTranscriptView`.

> **READ FIRST — Focus and keyboard rules are centralized.** Before touching `@FocusState`, `.onKeyPress`, or `.keyboardShortcut` on any chat surface, consult the **Focus And Keyboard Coordination** section in `Alveary/Views/AGENTS.md`.

## Follow-Mode Mechanisms

- Transcript auto-follow stays pinned when the user is at the bottom and content grows. Responsibilities are split across three mechanisms — do not collapse them into a single geometry-driven path:
    - **Content-size growth**: `.defaultScrollAnchor(.bottom, for: .sizeChanges)` on the `ScrollView`, gated on `isFollowing`. Covers streaming-bubble wrap, bubble expand/collapse, intrinsic height changes.
    - **New message / stream chunk**: explicit `scrollToBottom` calls in `onChange(of: events.count)`, `onChange(of: viewModel.messageQueue.pending.count)`, and `onChange(of: viewModel.streamingText)`. These are the only content-growth surfaces that snap to bottom.
    - **Container-size changes**: `shouldPreserveFollowMode` inside `onScrollGeometryChange`. Covers composer banner, error banners, changed-files strip appearing (shrinking viewport) while the user was near the bottom.
        - **Only *shrinks* trigger the preserve path.** Container growth pulls the user toward the bottom on its own.
        - **Offset guard is `!offsetDecreased`, not `!offsetChanged`.** `.scrollPosition(_, anchor: .bottom)` bumps `offsetY` *up* when the container shrinks so the content-bottom stays aligned. That anchor-driven increase is not a user scroll — `!offsetChanged` previously missed this and left the transcript above the bottom when a banner arrived after `.jumpToLatest` timed out. A real user drag up *decreases* `offsetY`.
- **Do not re-add `contentGrew` to `shouldPreserveFollowMode`.** Bubble expand/collapse animations emit many intermediate `onScrollGeometryChange` frames; firing `scrollToBottom` on those frames fights the bubble's own animation. `.defaultScrollAnchor` handles that case.

## Layout And Scroll Modifiers

- Scroll coordination uses `scrollPosition.scrollTo(edge: .bottom)` — **not** `scrollTo(id:)`. Edge-based scroll hits the content's trailing edge directly, no row-id estimate needed.
    - **Why**: `LazyVStack` row-height estimates are only calibrated as rows materialize. On thread re-open, the grouper is pre-populated so `LazyVStack` measures everything on a single pass — its initial estimate can be ~2× the real total height, and `scrollTo(id: "chat-bottom")` lands in a range of unmaterialized rows, rendering blank until the user drags. Cold launch doesn't repro because the grouper is empty at first body eval and heights calibrate incrementally. Edge-scroll makes re-open match cold-launch.
- **Do not apply `.scrollTargetLayout()` to the transcript's `LazyVStack`.** It marks children as scroll targets, which makes `.scrollPosition(anchor: .bottom)` and `.defaultScrollAnchor` align "last scroll target's bottom = viewport bottom" — ignoring outer `.padding(.bottom, ...)` and drifting `offsetY` up by exactly 14pt a few frames after a scroll lands (no `onScrollGeometryChange` tick emitted). Symptom: cut-off bottom inset on thread re-select. It's only needed with `scrollTargetBehavior(.viewAligned)`, which we don't use.
- The bottom inset (`transcriptBottomInset` = 14pt) is applied as trailing `.padding(.bottom, ...)` on the `LazyVStack` — **not** as an inner `Color.clear` trailing child.
    - **Why**: a trailing child is subject to the stack's *estimated* row positions during single-pass layout on re-open. `scrollTo(edge: .bottom)` anchors to an inflated bottom and the viewport lands in unmaterialized rows — transcript renders **blank until the user drags**. Outer padding is a fixed addition and isn't subject to row estimation.

## `isFollowing` And `nextFollowingState`

- Treat content-size growth differently from a user-initiated scroll-away so `Jump to bottom` only appears after a real scroll-away. `isFollowing` is the source of truth; the `onScrollGeometryChange` fallback routes through `ChatTranscriptScrollBehavior.nextFollowingState(...)`, **not** a raw `isFollowing = newMetrics.isNearBottom` write.
    - **Why**: during streaming a single markdown chunk can mount a ~100pt+ block in one render pass. `onScrollGeometryChange` fires with the new `contentHeight` *before* `.defaultScrollAnchor` bumps `offsetY` to re-pin, so `distanceFromBottom` momentarily spikes past the 60pt `isNearBottom` threshold even without a user scroll.
    - **What the raw write broke**: flipping `isFollowing` to false on that transient tick disarmed `.defaultScrollAnchor(isFollowing ? .bottom : nil, ...)` on the next size change — subsequent growth silently extended below the viewport — and `onChange(of: streamingText)`'s `guard isFollowing` short-circuited follow-up scrolls. Symptom: jump-to-latest button blinked during streaming, stuck visible at turn end.
    - **Rule**: set `true` when `isNearBottom` (anchor caught up); set `false` only when `shouldCancelProgrammaticScroll` (real user drag — offsetY decreased AND distance grew); otherwise leave it alone.

## Retry Strategies And Progressive Scroll

- `scrollToBottom` has two retry strategies via the `retries` parameter:
    - **`.triple`** (default): immediate `scrollTo` + next-runloop + 150ms retries, plus `transcriptProgrammaticScrollTimeout` cleanup. Used for `jumpToLatest` (thread entry) and content-growth preserve-follow callers (`events.count`, `messageQueue.pending.count`, `streamingText`) — async bubble layout can still shift after initial scroll.
    - **`.single`**: immediate `scrollTo` only + timeout cleanup. Used by the container-change preserve-follow path in `onScrollGeometryChange` — continued container animation is re-pinned by `shouldReissuePendingPreserveFollow` on each subsequent geometry tick, so deferred retries would be redundant and triple-fire would amplify per-frame container changes (e.g. composer banner animating in over 300ms).
- **`forceFollow` scrolls from far-up use a progressive stepped fallback** (`performProgressiveScrollToBottom`). SwiftUI's `scrollPosition.scrollTo(edge: .bottom)` jumps in one layout pass; `LazyVStack` only materializes rows intersecting the *final* viewport, so a long jump (hundreds of points from bottom) can leave bottom rows unmaterialized — transcript blank until the user drags. The progressive path issues `scrollPosition.scrollTo(y:)` calls in 300pt increments ~40ms apart so the viewport sweeps through intermediate positions and rows materialize along the way.
    - **Gate on `forceFollow && distance > 400pt && content > viewport`.** Near-bottom `forceFollow` (turn-end rebuild, streaming, thread entry) takes the fast single `scrollTo(edge: .bottom)` path.
    - **The scheduler owns the flow while running.** Gate on `isProgressiveScrolling` in the `.reissue` branch and skip the triple-retry ladder's firings — running both simultaneously causes races and `LazyVStack` never stabilizes. The scheduler calls `scrollTo(edge: .bottom)` for its final hop so reissue predicates still converge to the exact bottom.
    - **Refresh the watchdog on every step.** `schedulePendingProgrammaticScrollTimeout()` must be called inside `performProgressiveScrollToBottom` each iteration — and also from the `.reissue` branch in `pendingScrollAction` even when its scrollTo is suppressed. The reissue predicate only fires on container-shrink / content-grow ticks; during a stable progressive sequence, intermediate ticks resolve to `.noop` (which doesn't refresh the watchdog). Without explicit refresh, the watchdog fires 400ms in and strands the scroll.
    - **Reset `isProgressiveScrolling = false`** on every exit path (final-edge hop, pending-was-cleared early exit, metrics-nil fallback). Leaking the flag persistently suppresses reissues for the view's lifetime.
    - **Cap recursion with `transcriptProgressiveScrollMaxSteps`.** Normal termination is `distance <= step`; if content grows faster than we step or scroll refuses to advance, the guard never fires. The cap is ~9000pt total travel, bails to a final `scrollTo(edge: .bottom)` when hit. Without this, a degenerate case loops indefinitely — pending doesn't clear via the watchdog because the reissue branch keeps refreshing it.
    - **Guard against concurrent chains with `!isProgressiveScrolling`.** Rapid repeat `forceFollow` (double-tap jump-to-latest, send-while-mid-progressive) must not start a second chain — two chains race their `scrollTo(y:)` calls. The in-flight chain reads `latestMetrics` on every step so it adapts to content growth; a second chain would be redundant. The retry ladder's gate uses `!isProgressiveScrolling` (not `!usingProgressiveScroll`) so a repeat call that skipped starting a second chain doesn't fall through to `scrollTo(edge: .bottom)` while the existing chain is driving.

## Pending-Scroll Watchdog

- `transcriptProgrammaticScrollTimeout` (400ms) is a **reset-on-progress watchdog**, not a fixed deadline.
    - **Why**: entering a large thread, `LazyVStack` can take >400ms to materialize enough rows for a stable content size. A one-shot deadline from the initial `scrollTo` fires while content is still growing, clears `pendingProgrammaticScrollMode`, and stops the reissue loop — viewport above the true bottom, transcript blank until the user drags.
    - **How**: `schedulePendingProgrammaticScrollTimeout()` stamps a fresh `pendingProgrammaticScrollTimeoutToken` (UUID) each call; the scheduled `asyncAfter` closure only runs if its captured token still matches. Call it from initial `scrollToBottom` and every reissue branch in `onScrollGeometryChange` (both `jumpToLatest` and `preserveFollow`). Watchdog fires 400ms after the *last* reissue.
    - **Do not overwrite `isFollowing` in the watchdog.** An earlier iteration wrote `isFollowing = latestMetrics?.isNearBottom ?? false` in the `.jumpToLatest` branch — on app launch to a preselected thread, no geometry tick had emitted yet, `latestMetrics` was nil, and the button flashed for a frame. `isFollowing` is set `true` at kickoff; `.cancelled` is the only legitimate path to `false` during the pending window, and it clears the pending mode early enough that the watchdog's guard short-circuits. The watchdog's only job is to clear `pendingProgrammaticScrollMode`.
    - **Do not issue a corrective `scrollTo` from the watchdog.** A briefly-tried "final catch-up" interacted badly with `.defaultScrollAnchor` during `LazyVStack` calibration and left the transcript scrolled well above the bottom on app launch.

## `.jumpToLatest` Pending-Mode

- Programmatic `jumpToLatest` on thread entry is **not** one-shot:
    - Async composer content (e.g. the changed-files strip once `DiffViewerViewModel.files` populates) can shrink the viewport *after* `scrollTo` lands.
    - While pending, container-height shrinks or content growth re-issue `scrollTo(edge: .bottom)` via `shouldReissuePendingJumpToLatest` and refresh the watchdog. This recovery path reacts to content growth (unlike `shouldReissuePendingPreserveFollow`): the window only runs during thread entry / turn-end rebuilds, so it won't interact with per-bubble expand animations.
- **`.jumpToLatest` does NOT clear pending on a transient `isAtBottom`.** On a large thread, `LazyVStack` initially materializes a small window near the bottom anchor — `isAtBottom` is trivially true (content height ≤ viewport), so a naive "clear on `isAtBottom`" disarms the reissue loop immediately. `LazyVStack` then replaces row-height estimates with real measurements, reported `contentHeight` shifts, our offset stays at the old bottom, viewport ends up above the real content end. Symptom: "transcript blank until I scroll, then content appears." The `isAtBottom` branch only clears pending for `.preserveFollow`; `.jumpToLatest` stays pending until the watchdog fires after 400ms of no growth. `isFollowing` is still set `true` immediately so the button doesn't flash.

## `.preserveFollow` Pending-Mode

- `.preserveFollow` pending scrolls (container-size change) participate in reissuance via `shouldReissuePendingPreserveFollow`:
    - Only container *shrinks* re-issue. Content growth is excluded: `.defaultScrollAnchor(.bottom, for: .sizeChanges)` handles content growth while `isFollowing` is true, and re-issuing on every streaming / bubble-expand frame re-introduces jank.
    - Container *growth* during a pending preserve-follow is also excluded — a growing viewport pulls toward the bottom on its own and `isAtBottom` clears pending naturally.

## Cancel Predicate Guards

- User intent still wins: evaluate `shouldCancelProgrammaticScroll` before re-issuing. **Four** conditions must all hold — each rejects a distinct SwiftUI-initiated false positive:
    - **`offsetDecreased`**, not merely changed. `.defaultScrollAnchor`'s catch-up during streaming *increases* offsetY; only a real user drag up decreases it.
    - **`distanceGrew`**, so a scroll converging on the bottom never trips cancel.
    - **`!newMetrics.isNearBottom`** — new position must be clearly past the 60pt band. When content fits the viewport, `.scrollPosition(anchor: .bottom)` uses *negative* offsetY, and `scrollTo(edge: .bottom)` can swing offsetY by hundreds of points (0 → -377) while landing distance within `isNearBottom` (12pt). Without this guard every streaming chunk could false-fire cancel.
    - **`offsetDrop < transcriptCancelMaxPerTickDrop`** (250pt) — within plausible per-tick user-drag magnitude. Rejects the turn-end false positive: `forceFullRebuild` regenerates tool-group UUIDs, ForEach diffs as heavy remove+insert, `.defaultScrollAnchor` loses its anchor view mid-diff, ScrollView snaps offsetY to a stale value (observed: 347pt drop in 1ms). `distance=347` is past the near-bottom guard, so that alone doesn't catch this case. 250pt admits very fast trackpad flings (existing "user drag-away" test uses 160pt) while rejecting multi-hundred-pt programmatic snaps. Don't tighten below that band.

## Turn-End Re-Pin

- **Turn end must re-pin the transcript when the user was following.** `onChange(of: viewModel.turnState.isActive)`'s false branch calls `viewModel.rebuildChatItemsIfNeeded(from: events, forceFullRebuild: true)` and must re-anchor the scroll.
    - **Why**: `forceFullRebuild` regenerates tool-group identities with new UUIDs, so ForEach diffs as heavy remove+insert; the streaming bubble (`id("streaming")`) unmounts as `streamingText` goes nil. `.defaultScrollAnchor` loses the view it was pinning to mid-diff, ScrollView falls back to a stale offset.
    - **How**: after the rebuild, call `scrollToBottom(forceFollow: true)` when `isFollowing`. Skip when `isFollowing == false` so user scroll-away is respected.
    - **Use `forceFollow: true` (jumpToLatest), not preserveFollow**: triple-fire retries and `shouldReissuePendingJumpToLatest`'s content-growth reissue window catch the rebuild's layout shifts; preserveFollow's container-only reissue predicate does not.

## Markdown Link Resolution

Transcript markdown links like `[docs](Alveary/DI/AGENTS.md)` or `[shot](~/Desktop/file.png)` open via an `.environment(\.openURL, ...)` modifier on `ChatTranscriptView`, not SwiftUI's default. The modifier sits on the outer transcript view so both `UserBubble` and `AssistantBubble` inherit it — do not re-scope it to a single bubble type.

- **Resolve schemeless URLs against `workingDirectory`.** Foundation's markdown parser hands relative links to `openURL` as schemeless `URL`s; SwiftUI's default handler passes them straight to `NSWorkspace.shared.open(_:)`, which silently no-ops without a `file://` prefix. `resolveMarkdownLinkURL(_:workingDirectory:)` rebuilds the URL against `URL(fileURLWithPath: workingDirectory, isDirectory: true)`.
- **Expand `~` before the working-directory branch.** Tilde is a shell convention, not a URL convention — `URL` treats `~/Desktop/foo` as a plain relative path and naive baseURL resolution produces `.../alveary/~/Desktop/foo`. The resolver detects `~` first, calls `removingPercentEncoding` (the markdown parser percent-encodes path chars, and `expandingTildeInPath` operates literally — without the decode, `~/Desktop/my%20file.png` lands as `my%20file.png` and misses the real `my file.png`), runs `NSString.expandingTildeInPath`, wraps with `URL(fileURLWithPath:)`.
- **Pass absolute URLs through unchanged.** Any URL with a scheme (`https`, `file`, `mailto`, etc.) reaches `NSWorkspace.shared.open(_:)` as-is — the resolver only touches `scheme == nil`.
- **Pass fragment-only references through unchanged.** `[top](#section)` is schemeless with no path; resolving it against `workingDirectory` yields `file:///.../cwd/#section` and opens the cwd in Finder. Guard on `hasPrefix("#")` before the tilde branch so `NSWorkspace.shared.open(_:)` silently no-ops instead.
- **Keep `workingDirectory` plumbed from `ChatView`.** `ChatView` gets `conversation.thread?.worktreePath ?? conversation.thread?.project?.path` via `ConversationView.activeWorkingDirectory`; forward into `ChatTranscriptView(workingDirectory:)` so per-thread worktree links resolve correctly. `ChatTranscriptLinkResolutionTests` pins each branch — update it in lockstep when the resolver changes.
- **File-mention chips in `UserBubble` are clickable and reuse the same handler.** `AppMarkdownParser.applyComposerChip` tags every `.fileMention` chip's replacement run with `replacement.link`, so SwiftUI routes clicks through the transcript's `OpenURLAction`. Absolute stored paths (including tilde-expanded) become `file://` URLs via `URL(fileURLWithPath:)`; relative stored paths stay schemeless and resolve against `workingDirectory` at click time. Do not add a separate per-bubble click handler. Slash-command chips stay unlinked (purely visual).
