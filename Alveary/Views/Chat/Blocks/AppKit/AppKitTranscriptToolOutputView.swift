@preconcurrency import AppKit
import Foundation

@MainActor
final class AppKitTranscriptToolOutputView: NSView {
    struct Configuration: Equatable {
        let toolName: String
        let content: String
        let typography: TranscriptTypography

        init(toolName: String, content: String, typography: TranscriptTypography = TranscriptTypography()) {
            self.toolName = toolName
            self.content = content
            self.typography = typography
        }
    }

    var onHeightInvalidated: (() -> Void)?

    private let codeBlock = AppKitTranscriptDetailCodeBlockView()
    private let showMoreButton = NSButton(title: "", target: nil, action: nil)
    private let lineCountLabel = NSTextField(labelWithString: "")
    private var configuration: Configuration?
    private var visibleTailLines = Int.max
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
        let shouldResetPaging = self.configuration?.toolName != configuration.toolName
        self.configuration = configuration
        if shouldResetPaging {
            visibleTailLines = TranscriptToolOutputPaging.initialTailLineCount(for: configuration.toolName)
        }
        updateRenderedContent()
        needsLayout = true
        invalidateTranscriptHeight(force: true)
    }

    func showMore() {
        guard let configuration, isPaged else {
            return
        }
        visibleTailLines = min(visibleTailLines + pageStep(for: configuration.toolName), totalLineCount)
        updateRenderedContent()
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
        updateRenderedContent()
    }

    private func setup() {
        translatesAutoresizingMaskIntoConstraints = false
        codeBlock.translatesAutoresizingMaskIntoConstraints = true
        codeBlock.onHeightInvalidated = { [weak self] in
            self?.invalidateTranscriptHeight(force: true)
        }
        showMoreButton.bezelStyle = .shadowlessSquare
        showMoreButton.isBordered = false
        showMoreButton.target = self
        showMoreButton.action = #selector(showMoreButtonPressed)
        lineCountLabel.textColor = .secondaryLabelColor
        addSubview(codeBlock)
        addSubview(showMoreButton)
        addSubview(lineCountLabel)
    }

    private func updateRenderedContent() {
        guard let configuration else {
            return
        }
        codeBlock.configure(
            .init(title: outputTitle, content: visibleContent, typography: configuration.typography)
        )

        showMoreButton.isHidden = !isPaged
        lineCountLabel.isHidden = !isPaged
        if isPaged {
            showMoreButton.title = showMoreLabel
            showMoreButton.font = configuration.typography.nsFont(.caption)
            showMoreButton.contentTintColor = NSColor.controlAccentColor.appKitResolvedColor(in: self)
            lineCountLabel.stringValue = "\(visibleTailLines) / \(totalLineCount) lines"
            lineCountLabel.font = configuration.typography.nsFont(.caption)
        }
    }

    private func layoutContent() {
        let width = max(bounds.width, 0)
        codeBlock.frame = NSRect(x: 0, y: 0, width: width, height: CGFloat.greatestFiniteMagnitude / 2)
        codeBlock.layoutSubtreeIfNeeded()
        codeBlock.frame.size.height = codeBlock.intrinsicContentSize.height

        guard isPaged else {
            showMoreButton.frame = .zero
            lineCountLabel.frame = .zero
            return
        }

        let controlsY = codeBlock.frame.maxY + 8
        let buttonSize = showMoreButton.fittingSize
        let labelSize = lineCountLabel.fittingSize
        showMoreButton.frame = NSRect(x: 0, y: controlsY, width: ceil(buttonSize.width), height: ceil(buttonSize.height))
        lineCountLabel.frame = NSRect(
            x: showMoreButton.frame.maxX + 10,
            y: controlsY,
            width: ceil(labelSize.width),
            height: ceil(labelSize.height)
        )
    }

    private var totalLineCount: Int {
        guard !displayContent.isEmpty else {
            return 0
        }
        return displayContent.split(separator: "\n", omittingEmptySubsequences: false).count
    }

    private var isPaged: Bool {
        guard let configuration else {
            return false
        }
        return TranscriptToolOutputPaging.pageStep(for: configuration.toolName) != nil && totalLineCount > visibleTailLines
    }

    private var visibleContent: String {
        if !isPaged {
            return displayContent
        }
        return displayContent
            .split(separator: "\n", omittingEmptySubsequences: false)
            .suffix(visibleTailLines)
            .joined(separator: "\n")
    }

    private var displayContent: String {
        guard let configuration else {
            return ""
        }
        return appMarkdownCodeDisplayContent(configuration.content)
    }

    private var outputTitle: String {
        guard isPaged else {
            return "Output"
        }
        return "Output (showing last \(visibleTailLines) of \(totalLineCount) lines)"
    }

    private var showMoreLabel: String {
        guard let configuration else {
            return ""
        }
        let remaining = totalLineCount - visibleTailLines
        let step = min(pageStep(for: configuration.toolName), remaining)
        return "Show \(step) more"
    }

    private func pageStep(for toolName: String) -> Int {
        TranscriptToolOutputPaging.pageStep(for: toolName) ?? 10
    }

    private func measuredHeight() -> CGFloat {
        guard isPaged else {
            return codeBlock.intrinsicContentSize.height
        }
        return codeBlock.intrinsicContentSize.height + 8 + max(showMoreButton.fittingSize.height, lineCountLabel.fittingSize.height)
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

    @objc
    private func showMoreButtonPressed() {
        showMore()
    }
}
