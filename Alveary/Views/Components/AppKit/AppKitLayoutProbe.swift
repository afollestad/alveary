import CoreGraphics

/// The frame height AppKit transcript and markdown views assign while measuring: a view is given a
/// full-width, effectively unbounded frame, lays its children out top-down, then shrinks to the
/// height they used.
///
/// Never probe with `CGFloat.greatestFiniteMagnitude` instead. AppKit reports any view height above
/// 2^45 as an `Invalid view geometry` runtime issue — which fails `scripts/test.sh` — and clamps the
/// frame to 2^45, so a "still probing" check against the huge value accepts the clamped frame as a
/// real height. Ten million points matches TextKit's own unbounded-container clamp; no transcript
/// content comes near it.
///
/// Shrink the probed view to its measured height before the pass returns, including when the probe
/// runs from a size getter rather than `layout()`: a view left at this height renders blank.
enum AppKitLayoutProbe {
    static let height: CGFloat = 10_000_000

    /// Whether `height` is a laid-out result rather than an unmeasured (`0`) or still-probing frame.
    /// Measurement can re-enter mid-probe through a child's height invalidation, so callers fall back
    /// to an estimate when this is `false`.
    static func isMeasured(_ height: CGFloat) -> Bool {
        height > 0 && height < Self.height
    }
}
