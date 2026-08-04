import AppKit

/// The card's trailing affordance: a chevron in a square slot.
///
/// The slot publishes its own first baseline because the header stack aligns on one and a symbol
/// has none — bottom-aligning to the text baseline instead rides the glyph high and grows the row.
@MainActor
final class AppKitHostToolWidgetDisclosureSlotView: NSView {
    private let chevronView = AppKitDynamicTintImageView()
    private var size: CGFloat = 0
    private var capHeight: CGFloat = 0

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        // The chevron restates what the summary line already says, so it stays decorative.
        setAccessibilityElement(false)
        chevronView.translatesAutoresizingMaskIntoConstraints = true
        chevronView.setAccessibilityElement(false)
        chevronView.image = NSImage(systemSymbolName: "chevron.right", accessibilityDescription: nil)
        addSubview(chevronView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isFlipped: Bool {
        true
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: size, height: size)
    }

    /// Centers the square on the summary's optical center rather than its baseline.
    override var firstBaselineOffsetFromTop: CGFloat {
        (size + capHeight) / 2
    }

    override func layout() {
        super.layout()
        chevronView.frame = bounds
    }

    func configure(size: CGFloat, capHeight: CGFloat) {
        if self.size != size || self.capHeight != capHeight {
            self.size = size
            self.capHeight = capHeight
            // The transcript's other chevron is the tool row's disclosure glyph; same weight, so
            // one affordance does not read heavier than the other.
            chevronView.symbolConfiguration = .init(pointSize: size, weight: .regular)
            invalidateIntrinsicContentSize()
            needsLayout = true
        }
        chevronView.setDynamicContentTintColorPreservingAlpha(transcriptInlineToolRowColor)
    }
}
