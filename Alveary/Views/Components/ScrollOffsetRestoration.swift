import SwiftUI

/// Remembers where a screen was scrolled to, so leaving it and coming back lands in the same
/// place.
///
/// **Must live on a root-lived view model, never in screen `@State`.** `MiddlePane` renders the
/// selected sidebar item through a `switch`, which compiles to `_ConditionalContent`: choosing a
/// thread tears the whole screen down and rebuilds it from scratch on return, so screen-owned
/// state is precisely what does not survive the trip. Keeping the screens unmounted is deliberate
/// — it is what stops five `.task` refreshes from running behind whatever the user is looking at.
///
/// A plain reference type rather than `@Observable`: the offset is written on every scroll frame
/// and read only when a screen mounts, so publishing it would invalidate the screen body on each
/// one for a value nothing renders. `DiffPreviewScrollOffset` makes the same call for the same
/// reason.
@MainActor
final class ScrollOffsetStore {
    private(set) var offset: CGFloat = 0

    /// What `offset` belongs to — a filter tab, or `nil` for a screen whose whole content is one
    /// list. A restore is skipped when the screen comes back showing something else, which is how
    /// tabbed screens keep their documented "each result set starts at the top" behavior.
    private(set) var token: AnyHashable?

    /// Clamps at zero because macOS elastic scrolling reports a negative offset while the content
    /// bounces past the top: storing one would read back as "left at the top, nothing to restore".
    func record(offset: CGFloat, token: AnyHashable?) {
        self.offset = max(offset, 0)
        self.token = token
    }

    /// The offset worth restoring for `token`, or `nil` when there is nothing to do — a different
    /// token, or a screen that was left at the top.
    func restorableOffset(for token: AnyHashable?) -> CGFloat? {
        guard self.token == token, offset > 0 else {
            return nil
        }
        return offset
    }
}

extension View {
    /// Records this scroll view's vertical offset into `store`, and restores it once when the
    /// screen mounts again.
    ///
    /// - Parameters:
    ///   - store: Held by a root-lived view model; see ``ScrollOffsetStore``.
    ///   - position: Only for a screen that *also* drives the scroll view itself — `SkillsScreen`
    ///     and `MCPScreen` reset to the top on each new search query. Such a screen passes its
    ///     binding here and drops its own `.scrollPosition(_:)`, since this applies it. Everyone
    ///     else omits it and lets the modifier own one privately, which keeps the per-frame
    ///     write-back off the screen's `body`.
    ///   - token: The tab or mode the offset belongs to. `nil` for a screen with one list.
    func restoresScrollOffset(
        _ store: ScrollOffsetStore,
        position: Binding<ScrollPosition>? = nil,
        token: AnyHashable? = nil
    ) -> some View {
        modifier(ScrollOffsetRestorationModifier(store: store, token: token, externalPosition: position))
    }
}

/// One scroll geometry reading. The two heights are what say whether the content has grown tall
/// enough to honor a stored offset yet.
struct ScrollOffsetReading: Equatable {
    let offset: CGFloat
    let contentHeight: CGFloat
    let containerHeight: CGFloat

    var maximumOffset: CGFloat {
        max(contentHeight - containerHeight, 0)
    }
}

/// What one reading means. Split out and pure so the policy is testable without a live scroll
/// view, the way `TimelineBottomFollowing` splits its own follow decision.
enum ScrollOffsetRestorationStep: Equatable {
    /// A teardown or not-yet-laid-out frame. Recording it would overwrite the very offset this
    /// type exists to keep.
    case ignore
    /// Remember this offset, and stop trying to restore.
    case record
    /// Stop trying to restore without recording — the reader scrolled there first, and yanking
    /// the view out from under them is worse than losing the stored position.
    case settle
    /// Scroll here, then stop trying.
    case restore(CGFloat)
    /// The content is still too short to reach the stored offset; scrolling now would clamp to the
    /// current end and settle there. Wait for a later reading.
    case wait

    /// - Parameter restorableOffset: `nil` once there is nothing left to restore — a different
    ///   token, a screen left at the top, or a restore that already happened.
    static func next(
        reading: ScrollOffsetReading,
        hasSettled: Bool,
        restorableOffset: CGFloat?
    ) -> ScrollOffsetRestorationStep {
        guard reading.contentHeight > 0 else {
            return .ignore
        }
        guard !hasSettled, let target = restorableOffset else {
            return .record
        }
        guard reading.offset <= 0 else {
            return .settle
        }
        guard reading.maximumOffset >= target else {
            return .wait
        }
        return .restore(target)
    }
}

/// Restores on a geometry *reading* rather than `onAppear`, because a screen routinely mounts
/// before it has rows — Pull Requests mounts on `.loading` and paints a beat later — and a scroll
/// against the empty layout would land at the top and count itself done. `TimelineBottomFollowing`
/// defers a pending scroll the same way, for the same reason.
private struct ScrollOffsetRestorationModifier: ViewModifier {
    let store: ScrollOffsetStore
    let token: AnyHashable?
    let externalPosition: Binding<ScrollPosition>?

    /// Cleared to `false` only by a fresh mount of this subtree. A tabbed screen keys its scroll
    /// view by the selection, so a tab switch does reset this — and the token check below is what
    /// makes that land on "nothing to restore" rather than on the previous tab's offset.
    @State private var hasSettled = false

    /// `.scrollPosition(_:)` writes the live position back into its binding as the reader scrolls.
    /// Owning that state *here* rather than on the screen is what keeps those writes from
    /// re-evaluating the screen's `body` every frame: re-running a modifier's `body(content:)`
    /// re-applies the chain without rebuilding the view it wraps.
    @State private var ownedPosition = ScrollPosition()

    private var position: Binding<ScrollPosition> {
        externalPosition ?? $ownedPosition
    }

    func body(content: Content) -> some View {
        content
            .scrollPosition(position)
            .onScrollGeometryChange(for: ScrollOffsetReading.self) { geometry in
                ScrollOffsetReading(
                    offset: geometry.contentOffset.y,
                    contentHeight: geometry.contentSize.height,
                    containerHeight: geometry.containerSize.height
                )
            } action: { _, current in
                apply(current)
            }
    }

    private func apply(_ reading: ScrollOffsetReading) {
        switch ScrollOffsetRestorationStep.next(
            reading: reading,
            hasSettled: hasSettled,
            restorableOffset: store.restorableOffset(for: token)
        ) {
        case .ignore, .wait:
            return
        case .record:
            hasSettled = true
            store.record(offset: reading.offset, token: token)
        case .settle:
            hasSettled = true
        case .restore(let target):
            hasSettled = true
            position.wrappedValue.scrollTo(y: target)
        }
    }
}
