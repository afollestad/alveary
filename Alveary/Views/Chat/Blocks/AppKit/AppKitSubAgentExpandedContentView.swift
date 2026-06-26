@preconcurrency import AppKit
import BlockInputKit

@MainActor
final class AppKitSubAgentExpandedContentView: NSView {
    struct Configuration: Equatable {
        let agent: SubAgentEntry
        let typography: TranscriptTypography
        let directContentLeadingInset: CGFloat
    }

    var onHeightInvalidated: (() -> Void)?
    var onUserInitiatedHeightChange: (() -> Void)? {
        didSet {
            toolsView.onUserInitiatedHeightChange = onUserInitiatedHeightChange
        }
    }
    var onOpenMarkdownLink: ((URL) -> Void)? {
        didSet {
            toolsView.onOpenMarkdownLink = onOpenMarkdownLink
            resultMarkdownView.onOpenMarkdownLink = onOpenMarkdownLink
        }
    }
    var onOpenMarkdownImage: ((BlockInputImage, URL?) -> Void)? {
        didSet {
            toolsView.onOpenMarkdownImage = onOpenMarkdownImage
            resultMarkdownView.onOpenMarkdownImage = onOpenMarkdownImage
        }
    }
    var onOpenToolImage: ((ToolEntry) -> Void)? {
        didSet {
            toolsView.onOpenToolImage = onOpenToolImage
        }
    }

    private let toolsView = AppKitTranscriptNestedToolRowsView()
    private let resultCodeView = AppKitTranscriptDetailCodeBlockView()
    private let resultMarkdownView = AppKitTranscriptDetailMarkdownView()
    private weak var activeResultView: NSView?
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
        rebuild()
        needsLayout = true
        invalidateTranscriptHeight(force: true)
    }

    override func layout() {
        layoutContent()
        super.layout()
        invalidateTranscriptHeight(force: false)
    }

    private func setup() {
        translatesAutoresizingMaskIntoConstraints = false
        toolsView.translatesAutoresizingMaskIntoConstraints = true
        resultCodeView.translatesAutoresizingMaskIntoConstraints = true
        resultMarkdownView.translatesAutoresizingMaskIntoConstraints = true
        toolsView.onHeightInvalidated = { [weak self] in self?.childHeightInvalidated() }
        resultCodeView.onHeightInvalidated = { [weak self] in self?.childHeightInvalidated() }
        resultMarkdownView.onHeightInvalidated = { [weak self] in self?.childHeightInvalidated() }
        toolsView.onUserInitiatedHeightChange = onUserInitiatedHeightChange
        toolsView.onOpenMarkdownLink = onOpenMarkdownLink
        toolsView.onOpenMarkdownImage = onOpenMarkdownImage
        toolsView.onOpenToolImage = onOpenToolImage
        resultMarkdownView.onOpenMarkdownLink = onOpenMarkdownLink
        resultMarkdownView.onOpenMarkdownImage = onOpenMarkdownImage
    }

    private func rebuild() {
        guard let configuration else {
            return
        }

        toolsView.removeFromSuperview()
        resultCodeView.removeFromSuperview()
        resultMarkdownView.removeFromSuperview()
        activeResultView = nil
        if !configuration.agent.tools.isEmpty {
            addSubview(toolsView)
            toolsView.onOpenMarkdownLink = onOpenMarkdownLink
            toolsView.onOpenMarkdownImage = onOpenMarkdownImage
            toolsView.onOpenToolImage = onOpenToolImage
            toolsView.onUserInitiatedHeightChange = onUserInitiatedHeightChange
            toolsView.configure(.init(tools: configuration.agent.tools, typography: configuration.typography))
        }

        if let result = configuration.agent.result,
           !result.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if TranscriptResultPresentation.prefersMarkdown(result) {
                addSubview(resultMarkdownView)
                resultMarkdownView.configure(.init(
                    title: "Result",
                    content: result,
                    taskStateScope: configuration.agent.id,
                    typography: configuration.typography
                ))
                activeResultView = resultMarkdownView
            } else {
                addSubview(resultCodeView)
                resultCodeView.configure(.init(title: "Result", content: result, typography: configuration.typography))
                activeResultView = resultCodeView
            }
        }
    }

    private func layoutContent() {
        guard let configuration else {
            return
        }
        var currentY: CGFloat = 0
        let width = max(bounds.width, 0)

        if toolsView.superview != nil {
            toolsView.frame = NSRect(x: 0, y: currentY, width: width, height: CGFloat.greatestFiniteMagnitude / 2)
            toolsView.layoutSubtreeIfNeeded()
            toolsView.frame.size.height = toolsView.intrinsicContentSize.height
            currentY = toolsView.frame.maxY + 12
        }

        if let resultView = activeResultView,
           resultView.superview != nil {
            let resultTopSpacing = configuration.agent.tools.isEmpty ? transcriptToolExpandedContentTopSpacing : 0
            let leadingInset = configuration.directContentLeadingInset
            resultView.frame = NSRect(
                x: leadingInset,
                y: currentY + resultTopSpacing,
                width: max(width - leadingInset, 0),
                height: CGFloat.greatestFiniteMagnitude / 2
            )
            resultView.layoutSubtreeIfNeeded()
            resultView.frame.size.height = resultView.intrinsicContentSize.height
        }
    }

    private func measuredHeight() -> CGFloat {
        guard let configuration else {
            return 0
        }
        var height: CGFloat = 0
        if toolsView.superview != nil {
            height += toolsView.intrinsicContentSize.height
        }
        if let resultView = activeResultView,
           resultView.superview != nil {
            if height > 0 {
                height += 12
            } else if configuration.agent.tools.isEmpty {
                height += transcriptToolExpandedContentTopSpacing
            }
            height += resultView.intrinsicContentSize.height
            height += toolExpandedContentBottomSpacing
        }
        return ceil(height)
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

    private func childHeightInvalidated() {
        needsLayout = true
        invalidateTranscriptHeight(force: true)
    }
}
