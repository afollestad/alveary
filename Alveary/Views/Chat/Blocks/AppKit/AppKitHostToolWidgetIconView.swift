import AppKit

/// The card's leading glyph, optically centered on the summary line it labels.
///
/// `NSImageView` publishes its baseline at the bottom of its alignment rect. That is right for an
/// SF Symbol, which is drawn to sit on a text baseline, but wrong for the fixed-canvas octicon
/// artwork these cards use: the whole square then hangs above the baseline and the glyph rides high
/// over its own summary. Centering on the summary's cap height instead puts it on the same optical
/// center as the trailing `AppKitHostToolWidgetDisclosureSlotView`, so the two ends of the header
/// line up with the text and with each other.
@MainActor
final class AppKitHostToolWidgetIconView: AppKitDynamicTintImageView {
    /// Cap height of the summary this glyph labels; `0` restores AppKit's own baseline.
    var summaryCapHeight: CGFloat = 0 {
        didSet {
            guard summaryCapHeight != oldValue else {
                return
            }
            invalidateIntrinsicContentSize()
        }
    }

    /// `intrinsicContentSize` is already stated in alignment-rect terms, the same space the
    /// baseline offset is measured in, so it works for symbol and artwork glyphs alike.
    override var firstBaselineOffsetFromTop: CGFloat {
        let height = intrinsicContentSize.height
        guard summaryCapHeight > 0, height > 0 else {
            return super.firstBaselineOffsetFromTop
        }
        return (height + summaryCapHeight) / 2
    }
}
