@preconcurrency import AppKit
import Foundation

@MainActor
final class AppKitTranscriptNoteView: NSView {
    struct Configuration: Equatable {
        let kind: TranscriptNoteKind
        let typography: TranscriptTypography

        init(kind: TranscriptNoteKind, typography: TranscriptTypography = TranscriptTypography()) {
            self.kind = kind
            self.typography = typography
        }
    }

    var onHeightInvalidated: (() -> Void)?

    private let textField = NSTextField(labelWithString: "")
    private var configuration: Configuration?
    private var lastMeasuredHeight: CGFloat = -1

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isFlipped: Bool {
        true
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: measuredHeight())
    }

    func configure(_ configuration: Configuration) {
        guard self.configuration != configuration else {
            return
        }
        self.configuration = configuration
        textField.alignment = textAlignment(for: configuration.kind.alignment)
        textField.setAccessibilityLabel(configuration.kind.text)
        updateAppearance()
        needsLayout = true
        invalidateTranscriptHeight(force: true)
    }

    override func layout() {
        layoutContent()
        super.layout()
        invalidateTranscriptHeight(force: false)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateAppearance()
    }

    private func setup() {
        translatesAutoresizingMaskIntoConstraints = false

        textField.translatesAutoresizingMaskIntoConstraints = true
        textField.lineBreakMode = .byWordWrapping
        textField.maximumNumberOfLines = 0
        addSubview(textField)
    }

    private func layoutContent() {
        let naturalTextWidth = textNaturalWidth()
        let textHorizontalInset = transcriptNoteTextHorizontalInset(naturalTextWidth: naturalTextWidth)
        let textLeadingInset = textHorizontalInset / 2
        let textMaxWidth = max(bounds.width, 0)
        let textWidth = min(naturalTextWidth, textMaxWidth)
        textField.frame = NSRect(x: 0, y: 0, width: textWidth, height: textHeight(for: textWidth))
        textField.frame.origin = NSPoint(
            x: textOriginX(
                alignment: configuration?.kind.alignment ?? .centered,
                textWidth: textWidth,
                textLeadingInset: textLeadingInset
            ),
            y: transcriptNoteVerticalPadding(for: configuration?.kind.alignment ?? .centered)
        )
    }

    private func updateAppearance() {
        guard let configuration else {
            return
        }
        textField.textColor = transcriptInlineToolRowColor
        textField.attributedStringValue = TranscriptToolSummaryFormatter.nsAttributedString(
            configuration.kind.text,
            typography: configuration.typography,
            foregroundColor: transcriptInlineToolRowColor
        )
    }

    private func measuredHeight() -> CGFloat {
        let verticalPadding = transcriptNoteVerticalPadding(for: configuration?.kind.alignment ?? .centered)
        if textField.frame.height > 0 {
            return ceil((verticalPadding * 2) + textField.frame.height)
        }
        return ceil((verticalPadding * 2) + textHeight(for: textNaturalWidth()))
    }

    private func textNaturalWidth() -> CGFloat {
        let unconstrainedBounds = NSRect(
            x: 0,
            y: 0,
            width: CGFloat.greatestFiniteMagnitude / 2,
            height: CGFloat.greatestFiniteMagnitude / 2
        )
        // Ask the field cell for its single-line width, including internal cell
        // padding. Plain attributed-string width is a few points too narrow and
        // can wrap "Session handed off" after the first word, clipping trailing text.
        return ceil(textField.cell?.cellSize(forBounds: unconstrainedBounds).width ?? textField.fittingSize.width)
    }

    private func transcriptNoteTextHorizontalInset(naturalTextWidth: CGFloat) -> CGFloat {
        max(naturalTextWidth - attributedTextNaturalWidth(), 0)
    }

    private func attributedTextNaturalWidth() -> CGFloat {
        let rect = textField.attributedStringValue.boundingRect(
            with: NSSize(width: CGFloat.greatestFiniteMagnitude / 2, height: CGFloat.greatestFiniteMagnitude / 2),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        )
        return ceil(rect.width)
    }

    private func textHeight(for width: CGFloat) -> CGFloat {
        guard width > 0 else {
            return textField.fittingSize.height
        }
        let rect = textField.attributedStringValue.boundingRect(
            with: NSSize(width: width, height: CGFloat.greatestFiniteMagnitude / 2),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        )
        return ceil(rect.height)
    }

    private func textOriginX(
        alignment: TranscriptNoteAlignment,
        textWidth: CGFloat,
        textLeadingInset: CGFloat
    ) -> CGFloat {
        switch alignment {
        case .centered:
            return (bounds.width - textWidth) / 2
        case .toolUsageLeading:
            return -textLeadingInset
        case .userBubbleTrailing:
            return bounds.width - textWidth + textLeadingInset
        }
    }

    private func textAlignment(for alignment: TranscriptNoteAlignment) -> NSTextAlignment {
        switch alignment {
        case .centered:
            return .center
        case .toolUsageLeading:
            return .left
        case .userBubbleTrailing:
            return .right
        }
    }

    private func invalidateTranscriptHeight(force: Bool) {
        let newHeight = measuredHeight()
        guard force || abs(newHeight - lastMeasuredHeight) > 0.5 else {
            return
        }
        lastMeasuredHeight = newHeight
        invalidateIntrinsicContentSize()
        onHeightInvalidated?()
    }
}

private let centeredTranscriptNoteVerticalPadding: CGFloat = transcriptInlineToolRowVerticalPadding * 2

private func transcriptNoteVerticalPadding(for alignment: TranscriptNoteAlignment) -> CGFloat {
    switch alignment {
    case .centered:
        return centeredTranscriptNoteVerticalPadding
    case .toolUsageLeading, .userBubbleTrailing:
        return transcriptInlineToolRowVerticalPadding
    }
}
