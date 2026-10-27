import AppKit

/// A reviewer's harness badge ("Cl", "Cx"), or a symbol for the team as a whole, shared by the
/// card's reviewer rows and the transcript's reviewer messages so both identify a reviewer alike.
@MainActor
final class AppKitReviewTeamMonogramView: AppKitDynamicColorView {
    private let label = NSTextField(labelWithString: "")
    private let symbol = AppKitDynamicTintImageView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = AppCornerRadius.standard
        setLayerFillColor(.secondaryLabelColor, alpha: 0.09)
        setAccessibilityElement(false)
        label.textColor = .secondaryLabelColor
        label.alignment = .center
        label.setAccessibilityElement(false)
        symbol.setDynamicContentTintColor(.secondaryLabelColor)
        symbol.setAccessibilityElement(false)
        addSubview(label)
        addSubview(symbol)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isFlipped: Bool { true }

    func configure(harness: String, typography: TranscriptTypography) {
        switch harness {
        case "codex": label.stringValue = "Cx"
        case "claude": label.stringValue = "Cl"
        default: label.stringValue = String(harness.prefix(2)).uppercased()
        }
        label.font = typography.nsFont(.caption, weight: .medium)
        label.isHidden = false
        symbol.isHidden = true
        needsLayout = true
    }

    func configure(symbolName: String, typography: TranscriptTypography) {
        symbol.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)
        symbol.symbolConfiguration = .init(pointSize: typography.size(for: .caption), weight: .medium)
        label.isHidden = true
        symbol.isHidden = false
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let labelHeight = ceil(label.fittingSize.height)
        label.frame = NSRect(x: 0, y: (bounds.height - labelHeight) / 2, width: bounds.width, height: labelHeight)
        symbol.frame = bounds.insetBy(dx: 3, dy: 3)
    }
}
