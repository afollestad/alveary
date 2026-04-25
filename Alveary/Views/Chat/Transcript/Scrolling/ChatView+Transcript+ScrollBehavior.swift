import Foundation

private let transcriptBottomSnapThreshold: CGFloat = 6

/// Maximum single-tick offsetY drop that can plausibly be a user drag-away.
/// Anything larger is treated as a programmatic scroll-state disturbance (e.g.
/// the turn-end `forceFullRebuild` making the ScrollView lose its anchor view
/// mid-diff and snap offset to a stale value — a 347pt single-tick drop was
/// observed). 250pt is loose enough to admit very fast trackpad flings while
/// rejecting the multi-hundred-pt programmatic snaps.
private let transcriptCancelMaxPerTickDrop: CGFloat = 250

struct ChatTranscriptScrollMetrics: Equatable {
    let offsetY: CGFloat
    let contentHeight: CGFloat
    let containerHeight: CGFloat

    var distanceFromBottom: CGFloat {
        contentHeight - (offsetY + containerHeight)
    }

    var isNearBottom: Bool {
        return distanceFromBottom < 60
    }

    var isAtBottom: Bool {
        return distanceFromBottom < transcriptBottomSnapThreshold
    }
}

enum PendingProgrammaticScrollMode {
    case preserveFollow
    case jumpToLatest
}

enum PendingProgrammaticScrollAction: Equatable {
    /// The user (or `.defaultScrollAnchor`) has already landed at the bottom and
    /// the pending mode's job is done — clear it and mark us as following.
    case settleFollowingAndClear
    /// Already at the bottom but the pending mode is `.jumpToLatest` — mark us
    /// as following but keep the pending mode live so subsequent content-size
    /// growth keeps re-issuing via `shouldReissuePendingJumpToLatest`.
    case followWithoutClearing
    /// User dragged away from the bottom — clear pending mode and stop following.
    case cancelled
    /// Re-issue `scrollPosition.scrollTo(edge: .bottom)` (and refresh the watchdog).
    case reissue
    /// Geometry change is not interesting for the pending mode — leave state alone.
    case noop
}

enum ChatTranscriptScrollBehavior {
    /// Preserve follow mode when the *viewport* shrinks under the user (e.g. a composer
    /// banner appearing) and they were already near the bottom.
    ///
    /// The predicate is deliberately asymmetric on both axes:
    /// - **Container shrinks, not any change.** Container *growth* pulls the user toward
    ///   the bottom on its own (more viewport, less to scroll) and doesn't need a re-pin.
    ///   `shouldReissuePendingPreserveFollow` already uses the same shrunk-only rule.
    /// - **Offset didn't *decrease*, not "didn't change".** `.scrollPosition(_, anchor: .bottom)`
    ///   bumps `offsetY` *up* when the container shrinks to keep the content-bottom aligned
    ///   to the viewport-bottom. That anchor-driven offset increase is not a user scroll —
    ///   excluding all offset changes (the old `!offsetChanged`) made us miss composer
    ///   banners that appear *after* the initial thread-open scroll has settled and
    ///   `.jumpToLatest` pending has timed out. A real user drag up *decreases* offsetY,
    ///   so `!offsetDecreased` is the correct guard: it rejects user drags but allows
    ///   anchor adjustments.
    ///
    /// Content-size growth is still deliberately excluded: `.defaultScrollAnchor(.bottom, for: .sizeChanges)`
    /// already pins the bottom during content growth, and new-message / streaming snaps are
    /// handled by the dedicated `events.count` / `streamingText` onChange paths. Firing here
    /// on content growth caused `scrollToBottom` to run on every frame of a bubble expand or
    /// collapse animation, fighting the animation and producing jank.
    static func shouldPreserveFollowMode(
        oldMetrics: ChatTranscriptScrollMetrics,
        newMetrics: ChatTranscriptScrollMetrics
    ) -> Bool {
        let containerShrunk = newMetrics.containerHeight < oldMetrics.containerHeight - 0.5
        let offsetDecreased = newMetrics.offsetY < oldMetrics.offsetY - 0.5
        return oldMetrics.isNearBottom && containerShrunk && !offsetDecreased
    }

    /// A user scroll-away should cancel a pending programmatic scroll, but normal
    /// `.defaultScrollAnchor(.bottom, for: .sizeChanges)` catch-up during streaming,
    /// `.scrollPosition(anchor: .bottom)` anchor adjustments, and turn-end rebuild
    /// scroll-state disturbances must not.
    ///
    /// Three guards working together:
    /// - **offsetDecreased**: a real user drag up decreases offsetY; anchor catch-up
    ///   during content growth *increases* it. Rejecting catch-up requires the
    ///   offset to have actually decreased.
    /// - **clearlyAwayFromBottom** (`!newMetrics.isNearBottom`): when content fits
    ///   the viewport, `.scrollPosition(anchor: .bottom)` uses *negative* offsetY
    ///   to pin content to the viewport bottom. A programmatic `scrollTo(edge: .bottom)`
    ///   in that state causes a large offsetY decrease (e.g. 0 → -377) that looks
    ///   like a user drag per the offset-decrease rule, but `distanceFromBottom`
    ///   lands within the near-bottom band (e.g. 12pt). A real user drag-away moves
    ///   past 60pt; anchor adjustments don't.
    /// - **plausibleUserVelocity** (`offsetDrop < transcriptCancelMaxPerTickDrop`):
    ///   turn-end `forceFullRebuild` regenerates tool-group identities, so the
    ///   ScrollView loses its anchor view mid-diff and offsetY can snap to a stale
    ///   value in a single geometry tick (e.g. 893 → 546 = 347pt drop in 1ms). No
    ///   user can drag that fast between ticks — a 347pt single-tick offset decrease
    ///   is programmatic disturbance, not user intent. Capping cancel to a plausible
    ///   per-tick user drag magnitude rejects this case.
    static func shouldCancelProgrammaticScroll(
        oldMetrics: ChatTranscriptScrollMetrics,
        newMetrics: ChatTranscriptScrollMetrics
    ) -> Bool {
        let offsetDrop = oldMetrics.offsetY - newMetrics.offsetY
        let offsetDecreased = offsetDrop > 0.5
        let movedFurtherFromBottom = newMetrics.distanceFromBottom > oldMetrics.distanceFromBottom + 0.5
        let clearlyAwayFromBottom = !newMetrics.isNearBottom
        let plausibleUserVelocity = offsetDrop < transcriptCancelMaxPerTickDrop
        return offsetDecreased && movedFurtherFromBottom && clearlyAwayFromBottom && plausibleUserVelocity
    }

    /// While a `jumpToLatest` scroll is still pending, composer-area changes that shrink the
    /// transcript viewport or content that grows below the current bottom move the real
    /// bottom out from under the pending scroll. Re-issue `scrollTo` so we land at the new
    /// bottom instead of timing out.
    static func shouldReissuePendingJumpToLatest(
        oldMetrics: ChatTranscriptScrollMetrics,
        newMetrics: ChatTranscriptScrollMetrics
    ) -> Bool {
        let containerShrunk = newMetrics.containerHeight < oldMetrics.containerHeight - 0.5
        let contentGrew = newMetrics.contentHeight > oldMetrics.contentHeight + 0.5
        return containerShrunk || contentGrew
    }

    /// While a `preserveFollow` scroll is still pending (initiated by a container-size change
    /// at the bottom), a composer banner can continue animating its frame over
    /// multiple layout passes. Re-issue `scrollTo` whenever the viewport shrinks further so
    /// the transcript stays pinned through the full banner animation, not just at the initial
    /// scrollTo + timeout snapshots. Unlike `shouldReissuePendingJumpToLatest`, content growth
    /// is not considered here: `.defaultScrollAnchor(.bottom, for: .sizeChanges)` handles content
    /// growth while `isFollowing` is true, and re-issuing on every streaming frame would
    /// re-introduce the bubble-expand jank that the preserve-follow narrowing was meant to fix.
    static func shouldReissuePendingPreserveFollow(
        oldMetrics: ChatTranscriptScrollMetrics,
        newMetrics: ChatTranscriptScrollMetrics
    ) -> Bool {
        newMetrics.containerHeight < oldMetrics.containerHeight - 0.5
    }

    /// Decide whether `isFollowing` should change in the fallback branch of
    /// `onScrollGeometryChange` (no pending programmatic scroll, not a
    /// `shouldPreserveFollowMode` case). Returns the next `isFollowing` value;
    /// passes `currentIsFollowing` through when the geometry change is ambiguous.
    ///
    /// Why this isn't just `newMetrics.isNearBottom`: during streaming, a markdown
    /// chunk can mount a ~100pt+ block on a single render pass. SwiftUI fires
    /// `onScrollGeometryChange` with the new `contentHeight` before
    /// `.defaultScrollAnchor(.bottom, for: .sizeChanges)` has bumped `offsetY`
    /// to re-pin the bottom, so `distanceFromBottom` momentarily spikes past the
    /// 60pt `isNearBottom` threshold. Naively writing `isFollowing = isNearBottom`
    /// on that tick flips the flag to `false`, which cascades:
    /// - `.defaultScrollAnchor(isFollowing ? .bottom : nil, for: .sizeChanges)`
    ///   stops pinning on the very next size change, so further content growth
    ///   silently extends below the viewport.
    /// - `onChange(of: streamingText)`'s `guard isFollowing` short-circuits and
    ///   blocks follow-up programmatic scrolls.
    /// - The jump-to-latest button appears mid-stream.
    /// Only a real user drag away from the bottom (`shouldCancelProgrammaticScroll`)
    /// should drop follow mode here; otherwise leave `isFollowing` alone until
    /// either the anchor catches up and we're near-bottom again, or the user
    /// scrolls intentionally.
    static func nextFollowingState(
        currentIsFollowing: Bool,
        oldMetrics: ChatTranscriptScrollMetrics,
        newMetrics: ChatTranscriptScrollMetrics
    ) -> Bool {
        if newMetrics.isNearBottom {
            return true
        }
        if shouldCancelProgrammaticScroll(oldMetrics: oldMetrics, newMetrics: newMetrics) {
            return false
        }
        return currentIsFollowing
    }

    /// Resolve what to do when `onScrollGeometryChange` fires while a programmatic
    /// scroll is still pending. Keeps the priority order (`isAtBottom` → user-cancel →
    /// reissue) in one place so tests can assert the behavior without simulating a
    /// real `ScrollView`.
    ///
    /// The load-bearing subtlety: `.jumpToLatest` must NOT clear pending mode on a
    /// transient `isAtBottom`. On thread re-open, `LazyVStack` materializes a small
    /// window first (viewport briefly fits all rows → `isAtBottom` fires), then
    /// over-estimates remaining row heights as it expands — the real bottom moves
    /// out from under the scroll. Clearing pending on that first `isAtBottom` would
    /// disarm `shouldReissuePendingJumpToLatest` and leave the viewport stranded.
    /// `.preserveFollow` has no equivalent growth scenario, so it clears normally.
    static func pendingScrollAction(
        pending: PendingProgrammaticScrollMode,
        oldMetrics: ChatTranscriptScrollMetrics,
        newMetrics: ChatTranscriptScrollMetrics
    ) -> PendingProgrammaticScrollAction {
        if newMetrics.isAtBottom {
            switch pending {
            case .preserveFollow:
                return .settleFollowingAndClear
            case .jumpToLatest:
                return .followWithoutClearing
            }
        }
        if shouldCancelProgrammaticScroll(oldMetrics: oldMetrics, newMetrics: newMetrics) {
            return .cancelled
        }
        switch pending {
        case .jumpToLatest:
            if shouldReissuePendingJumpToLatest(oldMetrics: oldMetrics, newMetrics: newMetrics) {
                return .reissue
            }
        case .preserveFollow:
            if shouldReissuePendingPreserveFollow(oldMetrics: oldMetrics, newMetrics: newMetrics) {
                return .reissue
            }
        }
        return .noop
    }
}
