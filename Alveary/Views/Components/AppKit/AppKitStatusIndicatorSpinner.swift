@preconcurrency import AppKit

/// AppKit twin of the SwiftUI `StatusIndicatorSpinner` ring for AppKit-owned
/// surfaces such as transcript tool rows and task-list rows. Draws a faint
/// full-circle track plus a clearer trimmed arc and spins via a presentation-only
/// `CABasicAnimation`, so the model layer stays static and snapshot renders stay
/// deterministic without a test hook.
///
/// Colors resolve through the shared dynamic-color helpers on appearance and
/// window changes; the spin restarts on window attach because Core Animation
/// drops animations when a layer leaves its window.
final class AppKitStatusIndicatorSpinner: NSView {
    private static let spinAnimationKey = "statusIndicatorSpin"

    private let spinLayer = CALayer()
    private let trackLayer = CAShapeLayer()
    private let arcLayer = CAShapeLayer()
    private let color: NSColor
    private let lineWidth: CGFloat
    private let preservesResolvedColorAlpha: Bool

    init(
        frame frameRect: NSRect = .zero,
        lineWidth: CGFloat = 2,
        color: NSColor = .secondaryLabelColor,
        preservesResolvedColorAlpha: Bool = false
    ) {
        self.color = color
        self.lineWidth = lineWidth
        self.preservesResolvedColorAlpha = preservesResolvedColorAlpha
        super.init(frame: frameRect)
        wantsLayer = true
        for shape in [trackLayer, arcLayer] {
            shape.fillColor = nil
            shape.lineCap = .round
            spinLayer.addSublayer(shape)
        }
        arcLayer.strokeEnd = 0.7
        layer?.addSublayer(spinLayer)
        setAccessibilityRole(.progressIndicator)
        refreshColors()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        spinLayer.frame = bounds
        trackLayer.frame = spinLayer.bounds
        arcLayer.frame = spinLayer.bounds
        // Inset by half the stroke so the ring renders fully inside the bounds.
        let path = CGPath(ellipseIn: bounds.insetBy(dx: lineWidth / 2, dy: lineWidth / 2), transform: nil)
        trackLayer.path = path
        arcLayer.path = path
        CATransaction.commit()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshColors()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        refreshColors()
        // Defer the spin start to a fresh top-level transaction. Window attach (and
        // the layout that follows) can run inside an ancestor's NSAnimationContext
        // group; adding an infinite-repeat animation into that transaction blocks
        // the group's completion handler from ever firing.
        DispatchQueue.main.async { [weak self] in
            self?.restartSpinIfNeeded()
        }
    }

    private func refreshColors() {
        let resolved = preservesResolvedColorAlpha ?
            color.resolved(for: appKitRenderingAppearance) :
            color.appKitResolvedColor(in: self)
        let trackAlpha = preservesResolvedColorAlpha ? resolved.alphaComponent * 0.25 : 0.25
        trackLayer.strokeColor = resolved.withAlphaComponent(trackAlpha).cgColor
        arcLayer.strokeColor = resolved.cgColor
        trackLayer.lineWidth = lineWidth
        arcLayer.lineWidth = lineWidth
    }

    private func restartSpinIfNeeded() {
        guard window != nil, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            spinLayer.removeAnimation(forKey: Self.spinAnimationKey)
            return
        }
        guard spinLayer.animation(forKey: Self.spinAnimationKey) == nil else {
            return
        }
        let rotation = CABasicAnimation(keyPath: "transform.rotation.z")
        rotation.fromValue = 0
        // Negative z-rotation spins clockwise in AppKit's unflipped layer space,
        // matching the SwiftUI spinner's direction.
        rotation.toValue = -2 * Double.pi
        rotation.duration = 0.9
        rotation.repeatCount = .infinity
        rotation.isRemovedOnCompletion = false
        spinLayer.add(rotation, forKey: Self.spinAnimationKey)
    }
}

#if DEBUG
extension AppKitStatusIndicatorSpinner {
    var trackStrokeColorForTesting: NSColor? {
        guard let strokeColor = trackLayer.strokeColor else {
            return nil
        }
        return NSColor(cgColor: strokeColor)
    }

    var arcStrokeColorForTesting: NSColor? {
        guard let strokeColor = arcLayer.strokeColor else {
            return nil
        }
        return NSColor(cgColor: strokeColor)
    }
}
#endif
