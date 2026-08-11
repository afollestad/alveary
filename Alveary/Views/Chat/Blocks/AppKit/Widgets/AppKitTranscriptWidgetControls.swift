import AppKit

/// Shared leaf controls for host-tool transcript widgets.
enum AppKitTranscriptWidgetPalette {
    static func statusColor(for state: ScheduledTaskState) -> NSColor {
        switch state {
        case .active:
            .systemGreen
        case .paused:
            .systemOrange
        case .completed:
            .secondaryLabelColor
        }
    }
}

/// Filled circle matching the transcript's shared status-color mapping.
@MainActor
final class AppKitTranscriptWidgetStatusDotView: NSView {
    private var tint: NSColor = .secondaryLabelColor

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = 3
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 6),
            heightAnchor.constraint(equalToConstant: 6)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(tint: NSColor) {
        self.tint = tint
        applyAppearance()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyAppearance()
    }

    private func applyAppearance() {
        layer?.backgroundColor = tint.resolved(for: effectiveAppearance).cgColor
    }
}

@MainActor
enum AppKitTranscriptWidgetLabelFactory {
    static func label(
        _ text: String,
        level: TranscriptFontLevel,
        color: NSColor,
        typography: TranscriptTypography,
        wraps: Bool = false
    ) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.translatesAutoresizingMaskIntoConstraints = false
        field.font = typography.nsFont(level)
        field.textColor = color
        field.lineBreakMode = wraps ? .byWordWrapping : .byTruncatingTail
        field.maximumNumberOfLines = wraps ? 0 : 1
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return field
    }
}

@MainActor
extension NSStackView {
    /// Adds a row that spans the stack's width so wrapping labels resolve a height.
    func addFullWidthArrangedSubview(_ view: NSView) {
        addArrangedSubview(view)
        view.widthAnchor.constraint(equalTo: widthAnchor).isActive = true
    }
}
