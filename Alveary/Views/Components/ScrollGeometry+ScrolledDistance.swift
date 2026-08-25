import SwiftUI

extension ScrollGeometry {
    /// How far a horizontal chip strip has scrolled from its start: `0` at rest, rising to
    /// `contentSize.width - containerSize.width` at the end, and leaving that range only under
    /// rubber-band overscroll.
    ///
    /// **Gate a strip's edge dividers on this, never on `contentOffset.x`.** That value is biased
    /// by `-contentInsets.leading`, and these strips inherit a leading content inset from the
    /// split-view detail column in some window layouts and none in others — measured at 280pt and
    /// at 0 on the same strip. Comparing the raw offset against a scrollable distance is then true
    /// at every position, which pinned each trailing divider on permanently. Taking the magnitude
    /// instead fails just as badly: the offset crosses zero whenever the scrollable distance
    /// exceeds the inset, so `abs` reads true at both ends of a long strip. Adding the inset back
    /// is what makes the value 0-based and increasing in every layout.
    ///
    /// Verify a change here in a running app. Nothing scrolls a snapshot, so a baseline records
    /// only the resting state — where the biased comparison happened to be right — which is how
    /// `testTerminalPaneSessionsOverflow` kept passing while that pane's dividers were wrong at
    /// every other scroll position.
    var horizontalScrolledDistance: CGFloat {
        contentOffset.x + contentInsets.leading
    }

    /// The vertical twin of ``horizontalScrolledDistance``: `0` at rest, rising as the content
    /// scrolls up, and negative only under the elastic overscroll past the top edge. Adding the
    /// inset back is what makes it 0-based in every layout, for the reason that property's doc
    /// comment gives — a scroll view with a top content inset rests at `contentOffset.y ==
    /// -contentInsets.top`, not at zero.
    var verticalScrolledDistance: CGFloat {
        contentOffset.y + contentInsets.top
    }

    /// Whether content has scrolled away from the top edge, for chrome that appears only once
    /// rows pass under it. The slack absorbs a fractional resting offset, which would otherwise
    /// read as a scroll; it matches the `0.5` the chip strips compare their own distances against.
    ///
    /// Transform a scroll observer to *this* rather than to the distance when the reading only
    /// gates something on or off — `onScrollGeometryChange` then fires on the crossing instead of
    /// on every scroll frame.
    var isScrolledFromTop: Bool {
        verticalScrolledDistance > 0.5
    }
}
