@preconcurrency import AppKit
import Foundation

@MainActor
final class AppKitTranscriptDetailCodeBlockView: NSView {
    struct Configuration: Equatable {
        let title: String
        let content: String
        let tint: Tint
        let typography: TranscriptTypography

        init(
            title: String,
            content: String,
            tint: Tint = .secondary,
            typography: TranscriptTypography = TranscriptTypography()
        ) {
            self.title = title
            self.content = content
            self.tint = tint
            self.typography = typography
        }
    }

    enum Tint: Equatable {
        case secondary
        case orange

        var color: NSColor {
            switch self {
            case .secondary:
                return .secondaryLabelColor
            case .orange:
                return .systemOrange
            }
        }

        var usesCodeChrome: Bool {
            self == .secondary
        }
    }

    var onHeightInvalidated: (() -> Void)?

    private let titleField = NSTextField(labelWithString: "")
    private let codeView = AppKitTranscriptCodeSurfaceView()
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
        titleField.stringValue = configuration.title
        titleField.font = configuration.typography.nsFont(.caption, weight: .semibold)
        titleField.textColor = configuration.tint.color
        if configuration.tint.usesCodeChrome {
            codeView.configure(
                .highlighted(
                    content: configuration.content,
                    language: "",
                    preservesLeadingLineNumberPrefixes: false,
                    typography: configuration.typography
                )
            )
        } else {
            codeView.configure(
                .plain(content: configuration.content, tint: configuration.tint.color, typography: configuration.typography)
            )
        }
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
        codeView.refreshAppearance()
    }

    private func setup() {
        translatesAutoresizingMaskIntoConstraints = false
        titleField.translatesAutoresizingMaskIntoConstraints = true
        codeView.translatesAutoresizingMaskIntoConstraints = true
        codeView.onHeightInvalidated = { [weak self] in
            self?.invalidateTranscriptHeight(force: true)
        }
        addSubview(titleField)
        addSubview(codeView)
    }

    private func layoutContent() {
        let width = max(bounds.width, 0)
        let titleHeight = ceil(titleField.fittingSize.height)
        titleField.frame = NSRect(x: 0, y: 0, width: width, height: titleHeight)

        codeView.frame = NSRect(
            x: 0,
            y: titleHeight + 6,
            width: width,
            height: CGFloat.greatestFiniteMagnitude / 2
        )
        codeView.layoutSubtreeIfNeeded()
        codeView.frame.size.height = codeView.intrinsicContentSize.height
    }

    private func measuredHeight() -> CGFloat {
        ceil(titleField.fittingSize.height) + 6 + codeView.intrinsicContentSize.height
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
