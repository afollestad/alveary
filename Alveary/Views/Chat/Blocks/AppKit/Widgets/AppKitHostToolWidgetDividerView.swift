import AppKit

/// A soft rule between widget sections; window separator colors are too strong against a bubble.
final class AppKitHostToolWidgetDividerView: AppKitDynamicColorView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        setLayerFillColor(.secondaryLabelColor, alpha: 0.18)
        heightAnchor.constraint(equalToConstant: 1).isActive = true
        setAccessibilityElement(false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isFlipped: Bool {
        true
    }
}
