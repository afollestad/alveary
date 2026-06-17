@preconcurrency import AppKit
import QuartzCore

/// Lightweight AppKit equivalent of SwiftUI's active-turn thinking indicator.
@MainActor
final class AppKitTranscriptThinkingIndicatorView: NSView {
    struct Configuration: Equatable {
        let bubbleMaxWidth: CGFloat
        let typography: TranscriptTypography
        let isAnimated: Bool

        init(
            bubbleMaxWidth: CGFloat = .infinity,
            typography: TranscriptTypography = TranscriptTypography(),
            isAnimated: Bool = true
        ) {
            self.bubbleMaxWidth = bubbleMaxWidth
            self.typography = typography
            self.isAnimated = isAnimated
        }
    }

    private let dotViews = (0..<3).map { _ in AppKitDynamicColorView() }
    private var isAnimated = true
    private var isAnimating = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isFlipped: Bool { true }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: 7 + (chatVerticalPadding * 2))
    }

    func configure(_ configuration: Configuration) {
        isAnimated = configuration.isAnimated
        needsLayout = true
        updateAnimationState()
    }

    override func layout() {
        super.layout()
        // Align standalone dots with assistant bubble chrome at the row leading edge.
        let startX: CGFloat = 0
        let centerY = chatVerticalPadding + 3.5
        for (index, dotView) in dotViews.enumerated() {
            dotView.frame = NSRect(x: startX + CGFloat(index) * 13, y: centerY - 3.5, width: 7, height: 7)
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateAppearance()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateAnimationState()
    }

    private func setup() {
        translatesAutoresizingMaskIntoConstraints = false
        setAccessibilityElement(true)
        setAccessibilityLabel("Assistant is thinking")

        for dotView in dotViews {
            dotView.wantsLayer = true
            dotView.layer?.cornerRadius = 3.5
            addSubview(dotView)
        }
        updateAppearance()
        updateAnimationState()
    }

    private func updateAppearance() {
        for (index, dotView) in dotViews.enumerated() {
            dotView.setLayerFillColor(.secondaryLabelColor, alpha: 0.28 + CGFloat(index) * 0.18)
        }
    }

    private func updateAnimationState() {
        guard window != nil, isAnimated else {
            stopAnimatingDots()
            return
        }
        startAnimatingDots()
    }

    private func startAnimatingDots() {
        guard !isAnimating else {
            return
        }
        isAnimating = true
        for (index, dotView) in dotViews.enumerated() {
            let beginTime = CACurrentMediaTime() + (Double(index) * 0.22)
            addDotAnimation(
                to: dotView,
                keyPath: "opacity",
                values: [0.28, 0.85, 0.28],
                beginTime: beginTime
            )
            addDotAnimation(
                to: dotView,
                keyPath: "transform.scale",
                values: [0.72, 1.0, 0.72],
                beginTime: beginTime
            )
        }
    }

    private func addDotAnimation(to dotView: NSView, keyPath: String, values: [CGFloat], beginTime: CFTimeInterval) {
        let animation = CAKeyframeAnimation(keyPath: keyPath)
        animation.values = values
        animation.keyTimes = [0, 0.5, 1]
        animation.duration = 1.1
        animation.beginTime = beginTime
        animation.repeatCount = .infinity
        animation.isRemovedOnCompletion = false
        dotView.layer?.add(animation, forKey: keyPath)
    }

    private func stopAnimatingDots() {
        guard isAnimating else {
            return
        }
        isAnimating = false
        for dotView in dotViews {
            dotView.layer?.removeAnimation(forKey: "opacity")
            dotView.layer?.removeAnimation(forKey: "transform.scale")
        }
    }
}

#if DEBUG
extension AppKitTranscriptThinkingIndicatorView {
    var dotFramesForTesting: [CGRect] {
        dotViews.map(\.frame)
    }
}
#endif
