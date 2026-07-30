import SwiftUI

/// Clearance that keeps interactive chrome out of a vertical scroll indicator's
/// grab region. Overlay scrollers float over content and their hit region is
/// wider than the visible knob — the lane itself plus AppKit's grab slop — so a
/// control too close to a scroll view's trailing edge silently loses clicks
/// whenever the indicator is showing.
///
/// This is the deliberate dual of `appKitHorizontalOverflowScrollbarReserve`,
/// which reserves *space at the end of content* and so only matters for legacy
/// scrollers. This one guards *hit-testing under a floating indicator* and so
/// only matters for overlay ones.
@MainActor
enum AppScrollIndicatorLayout {
    /// Minimum distance from a scroll view's trailing edge to an interactive
    /// control's trailing edge. Measured, not derived: the overlay lane is 17pt
    /// (`NSScroller.scrollerWidth(for: .regular, scrollerStyle: .overlay)`) but
    /// its grab region reaches further — a control 3pt clear of the lane still
    /// dropped clicks while 11pt clear never did, so this bakes in the proven
    /// 11pt margin. Repo-owned rather than read from `NSScroller` at layout
    /// time so a machine's scroller settings or an OS lane change cannot move
    /// layout or desync snapshots; `AppScrollIndicatorLayoutTests` asserts it
    /// still exceeds the real lane by that margin.
    static let interactiveTrailingClearance: CGFloat = 28
}
