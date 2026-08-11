import SwiftUI

/// Keeps the Overview pinned to the end of its conversation timeline while the
/// reader is already parked there, so an appended entry — a closed/reopened row,
/// a ready-for-review row, a reply — reveals itself instead of landing below the
/// fold. Scrolling up opts out until the reader returns to the bottom.
///
/// Lifted out of `PullRequestPaneOverview.body` to keep the scroll observers off
/// its type-check budget (see `Alveary/Views/AGENTS.md`).
struct TimelineBottomFollowing: ViewModifier {
    /// One scroll geometry reading. Carrying the content height alongside the
    /// distance is what separates "the reader scrolled away" from "the content
    /// grew underneath the reader" — the two look identical from the distance
    /// alone, and treating growth as opting out is what silently stopped the
    /// follow after the first appended row.
    struct Reading: Equatable {
        let contentHeight: CGFloat
        let distanceFromBottom: CGFloat
    }

    /// Anything appended to the timeline; a change is what triggers the scroll.
    let itemCount: Int
    @Binding var scrollPosition: ScrollPosition
    @Binding var isFollowing: Bool

    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    /// Set when an append qualifies, cleared once the grown content has actually
    /// been laid out. Scrolling on the data change alone lands against the old
    /// content height and stops short of the new row.
    @State private var hasPendingScroll = false

    /// Slack for the bottom test. Fractional content heights mean an offset can
    /// sit a hair short of the exact end while reading as parked there.
    private nonisolated static let bottomSlack: CGFloat = 8

    func body(content: Content) -> some View {
        content
            .scrollPosition($scrollPosition)
            .onScrollGeometryChange(for: Reading.self) { geometry in
                Reading(
                    contentHeight: geometry.contentSize.height,
                    distanceFromBottom: geometry.contentSize.height
                        - (geometry.contentOffset.y + geometry.containerSize.height)
                )
            } action: { previous, current in
                apply(previous: previous, current: current)
            }
            .onChange(of: itemCount) { previousCount, newCount in
                guard Self.shouldScrollToBottom(
                    previousCount: previousCount,
                    newCount: newCount,
                    isFollowing: isFollowing
                ) else {
                    return
                }
                // Scroll now *and* leave the request armed. This pass runs
                // against the pre-growth layout and can stop short of the new
                // row; the geometry reading that reports the grown content
                // finishes the job. Both are the same idempotent edge scroll, so
                // the pair reads as one motion — and neither ordering of the two
                // callbacks can drop the scroll.
                hasPendingScroll = true
                scrollToBottom()
            }
    }

    private func scrollToBottom() {
        // Reduce Motion still reveals the entry, it just jumps there.
        withAnimation(accessibilityReduceMotion ? nil : .easeOut(duration: 0.2)) {
            scrollPosition.scrollTo(edge: .bottom)
        }
    }

    /// Runs on every geometry reading: performs a pending scroll once the grown
    /// content is on screen, and otherwise re-reads whether the reader is parked
    /// at the end.
    private func apply(previous: Reading, current: Reading) {
        let contentGrew = current.contentHeight > previous.contentHeight
        if hasPendingScroll, contentGrew {
            hasPendingScroll = false
            scrollToBottom()
            return
        }
        isFollowing = Self.nextFollowState(
            wasFollowing: isFollowing,
            contentGrew: contentGrew,
            distanceFromBottom: current.distanceFromBottom
        )
        // A request that never met its growth (an entry replaced rather than
        // appended) must not fire against some later, unrelated change.
        if !isFollowing {
            hasPendingScroll = false
        }
    }

    /// Content growing underneath a reader who is parked at the end is not them
    /// opting out — their offset has not moved, only the content below it. Any
    /// other reading is a genuine scroll, so it re-decides from the distance.
    /// Content shorter than its container reads as parked, so a timeline that
    /// has not filled the pane yet still follows.
    ///
    /// `nonisolated` because the policy is pure: conforming to `ViewModifier`
    /// infers `@MainActor` for the whole type, which would otherwise force every
    /// caller — including the tests — onto the main actor for arithmetic.
    nonisolated static func nextFollowState(
        wasFollowing: Bool,
        contentGrew: Bool,
        distanceFromBottom: CGFloat
    ) -> Bool {
        if wasFollowing, contentGrew {
            return true
        }
        return distanceFromBottom <= bottomSlack
    }

    /// Only a genuine append while parked at the bottom scrolls.
    nonisolated static func shouldScrollToBottom(previousCount: Int, newCount: Int, isFollowing: Bool) -> Bool {
        // A zero previous count is the first detail landing, not an append —
        // scrolling then would bury the header the reader just opened. A
        // shrinking count is a deletion, which should not yank the view either.
        previousCount > 0 && newCount > previousCount && isFollowing
    }
}
