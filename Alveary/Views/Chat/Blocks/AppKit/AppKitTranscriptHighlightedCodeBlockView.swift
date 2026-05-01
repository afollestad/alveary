@preconcurrency import AppKit
import Foundation

@MainActor
final class AppKitTranscriptHighlightedCodeBlockView: NSView {
    struct Configuration: Equatable {
        let content: String
        let language: String
        let preservesLeadingLineNumberPrefixes: Bool
        let typography: TranscriptTypography

        init(
            content: String,
            language: String,
            preservesLeadingLineNumberPrefixes: Bool = false,
            typography: TranscriptTypography = TranscriptTypography()
        ) {
            self.content = content
            self.language = language
            self.preservesLeadingLineNumberPrefixes = preservesLeadingLineNumberPrefixes
            self.typography = typography
        }
    }

    var onHeightInvalidated: (() -> Void)?

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
        codeView.configure(
            .highlighted(
                content: configuration.content,
                language: configuration.language,
                preservesLeadingLineNumberPrefixes: configuration.preservesLeadingLineNumberPrefixes,
                typography: configuration.typography
            )
        )
        needsLayout = true
        invalidateTranscriptHeight(force: true)
    }

    override func layout() {
        codeView.frame = NSRect(x: 0, y: 0, width: max(bounds.width, 0), height: CGFloat.greatestFiniteMagnitude / 2)
        codeView.layoutSubtreeIfNeeded()
        codeView.frame.size.height = codeView.intrinsicContentSize.height
        super.layout()
        invalidateTranscriptHeight(force: false)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        codeView.refreshAppearance()
    }

    private func setup() {
        translatesAutoresizingMaskIntoConstraints = false
        codeView.translatesAutoresizingMaskIntoConstraints = true
        codeView.onHeightInvalidated = { [weak self] in
            self?.invalidateTranscriptHeight(force: true)
        }
        addSubview(codeView)
    }

    private func measuredHeight() -> CGFloat {
        codeView.intrinsicContentSize.height
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
