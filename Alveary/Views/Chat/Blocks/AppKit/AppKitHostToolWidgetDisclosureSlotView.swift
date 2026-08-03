import AppKit

/// The card's trailing affordance: a chevron, or Alveary's ring spinner while the pull request
/// it opens is being fetched.
///
/// One square slot holds both, so the swap cannot resize the card, and the slot publishes its own
/// first baseline because the header stack aligns on one and neither a symbol nor a ring has one —
/// bottom-aligning to the text baseline instead rides the glyph high and grows the row. The
/// spinner is inserted only while waiting, so a resolved card owns no repeating animation.
@MainActor
final class AppKitHostToolWidgetDisclosureSlotView: NSView {
    private let chevronView = AppKitDynamicTintImageView()
    private var spinner: AppKitStatusIndicatorSpinner?
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
        spinner?.frame = bounds
    }

    func configure(size: CGFloat, capHeight: CGFloat, isWaiting: Bool) {
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
        chevronView.isHidden = isWaiting
        updateSpinner(isWaiting: isWaiting)
    }

    private func updateSpinner(isWaiting: Bool) {
        guard isWaiting else {
            spinner?.removeFromSuperview()
            spinner = nil
            return
        }
        guard spinner == nil else {
            return
        }
        // Preserving the resolved alpha is what keeps the ring as light as the chevron it
        // replaces; the default flattens a semantic label color to fully opaque.
        let spinner = AppKitStatusIndicatorSpinner(
            lineWidth: 1.5,
            color: transcriptInlineToolRowColor,
            preservesResolvedColorAlpha: true
        )
        spinner.translatesAutoresizingMaskIntoConstraints = true
        spinner.frame = bounds
        addSubview(spinner)
        self.spinner = spinner
    }
}
