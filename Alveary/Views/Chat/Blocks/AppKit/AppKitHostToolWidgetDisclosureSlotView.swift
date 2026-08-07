import AppKit
import QuartzCore

/// The card's trailing affordance: a chevron in a square slot.
///
/// The slot publishes its own first baseline because the header stack aligns on one and a symbol
/// has none — bottom-aligning to the text baseline instead rides the glyph high and grows the row.
@MainActor
final class AppKitHostToolWidgetDisclosureSlotView: NSView {
    private let chevronView = AppKitDynamicTintImageView()
    private var size: CGFloat = 0
    private var capHeight: CGFloat = 0
    private var isExpanded = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        // The chevron restates what the summary line already says, so it stays decorative.
        setAccessibilityElement(false)
        chevronView.translatesAutoresizingMaskIntoConstraints = true
        chevronView.wantsLayer = true
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
        positionChevronLayer()
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

    /// A card that expands in place rotates the caret down while it opens, the counterpart to the
    /// navigating card's fixed rightward chevron. Same glyph, rotation, and timing as the inline
    /// tool rows' disclosure, so the two affordances read as one.
    func setExpanded(_ expanded: Bool, animated: Bool) {
        guard isExpanded != expanded else {
            return
        }
        let previousRotation = rotation
        isExpanded = expanded
        positionChevronLayer()
        guard animated,
              !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
              let layer = chevronView.layer else {
            return
        }
        let animation = CABasicAnimation(keyPath: "transform.rotation.z")
        animation.fromValue = previousRotation
        animation.toValue = rotation
        animation.duration = 0.16
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        layer.add(animation, forKey: "hostToolDisclosureRotation")
    }

    private var rotation: CGFloat {
        // Positive, where the tool rows' indicator uses negative: this slot is flipped, which
        // inverts the layer rotation's visual direction, and the caret must point down when open.
        isExpanded ? CGFloat.pi / 2 : 0
    }

    // Keep the view-backed layer centered while rotating, the way the tool rows' status
    // indicator does; otherwise the glyph drifts out of its slot during expand/collapse.
    private func positionChevronLayer() {
        guard let layer = chevronView.layer else {
            return
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        layer.bounds = CGRect(origin: .zero, size: chevronView.bounds.size)
        layer.position = CGPoint(x: chevronView.frame.midX, y: chevronView.frame.midY)
        layer.setAffineTransform(CGAffineTransform(rotationAngle: rotation))
        CATransaction.commit()
    }
}
