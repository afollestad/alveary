@preconcurrency import AppKit
import Foundation

@MainActor
final class AppKitTranscriptCenteredNoteView: NSView {
    struct Configuration: Equatable {
        let kind: CenteredTranscriptNoteKind
        let typography: TranscriptTypography

        init(kind: CenteredTranscriptNoteKind, typography: TranscriptTypography = TranscriptTypography()) {
            self.kind = kind
            self.typography = typography
        }
    }

    var onHeightInvalidated: (() -> Void)?

    private let iconView = AppKitDynamicTintImageView()
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
        textField.stringValue = configuration.kind.text
        textField.font = configuration.typography.nsFont(.body, weight: .medium)
        textField.setAccessibilityLabel(configuration.kind.text)
        updateIconSymbolConfiguration()
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
        iconView.translatesAutoresizingMaskIntoConstraints = true
        iconView.image = NSImage(systemSymbolName: "info.circle", accessibilityDescription: nil)
        iconView.setAccessibilityElement(false)
        addSubview(iconView)

        textField.translatesAutoresizingMaskIntoConstraints = true
        textField.lineBreakMode = .byWordWrapping
        textField.maximumNumberOfLines = 0
        addSubview(textField)
        updateAppearance()
    }

    private func layoutContent() {
        let iconSize = centeredNoteIconSize()
        let textMaxWidth = max(bounds.width - iconSize - centeredNoteSpacing, 0)
        let textWidth = min(textNaturalWidth(), textMaxWidth)
        textField.frame = NSRect(x: 0, y: 0, width: textWidth, height: textHeight(for: textWidth))

        iconView.frame = NSRect(x: 0, y: 0, width: iconSize, height: iconSize)
        let contentWidth = iconSize + centeredNoteSpacing + textField.frame.width
        let originX = max((bounds.width - contentWidth) / 2, 0)
        let contentHeight = max(iconSize, textField.frame.height)
        let originY = centeredNoteVerticalPadding + max((contentHeight - iconSize) / 2, 0)
        iconView.frame.origin = NSPoint(x: originX, y: originY)
        textField.frame.origin = NSPoint(
            x: iconView.frame.maxX + centeredNoteSpacing,
            y: centeredNoteVerticalPadding + max((contentHeight - textField.frame.height) / 2, 0)
        )
    }

    private func updateAppearance() {
        textField.textColor = centeredNoteForegroundColor()
        updateIconSymbolConfiguration()
    }

    private func updateIconSymbolConfiguration() {
        let pointSize = configuration?.typography.size(for: .body) ?? TranscriptTypography().size(for: .body)
        let iconColor = textField.textColor ?? centeredNoteForegroundColor()
        // SwiftUI applies `.transcriptFont(.body, weight: .medium)` and
        // `.foregroundStyle(.secondary)` to both the label and `info.circle`.
        // AppKit's template tint alone can leave SF Symbols brighter in dark
        // mode, so also pin the symbol hierarchy to the label's resolved color.
        iconView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .medium, scale: .medium)
            .applying(.init(hierarchicalColor: iconColor))
        iconView.setDynamicContentTintColor(.labelColor, alpha: centeredNoteForegroundAlpha)
    }

    private func centeredNoteForegroundColor() -> NSColor {
        NSColor.labelColor.appKitResolvedColor(in: self, alpha: centeredNoteForegroundAlpha)
    }

    private func measuredHeight() -> CGFloat {
        let iconSize = centeredNoteIconSize()
        if textField.frame.height > 0 {
            return ceil((centeredNoteVerticalPadding * 2) + max(iconSize, textField.frame.height))
        }
        return ceil((centeredNoteVerticalPadding * 2) + max(iconSize, textHeight(for: textNaturalWidth())))
    }

    private func centeredNoteIconSize() -> CGFloat {
        let pointSize = configuration?.typography.size(for: .body) ?? TranscriptTypography().size(for: .body)
        let configuration = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .medium, scale: .medium)
        let imageSize = NSImage(systemSymbolName: "info.circle", accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration)?
            .size
        return ceil(max(imageSize?.width ?? pointSize, imageSize?.height ?? pointSize))
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
        // can wrap "Session handoff" after the first word, clipping "handoff".
        return ceil(textField.cell?.cellSize(forBounds: unconstrainedBounds).width ?? textField.fittingSize.width)
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

private let centeredNoteSpacing: CGFloat = 8
private let centeredNoteVerticalPadding: CGFloat = 16
private let centeredNoteForegroundAlpha: CGFloat = 0.62
