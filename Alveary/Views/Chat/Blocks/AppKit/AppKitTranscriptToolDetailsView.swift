@preconcurrency import AppKit
import Foundation

@MainActor
final class AppKitTranscriptToolDetailsView: AppKitDynamicColorView {
    struct Configuration: Equatable {
        let tool: ToolEntry
        let typography: TranscriptTypography

        init(tool: ToolEntry, typography: TranscriptTypography = TranscriptTypography()) {
            self.tool = tool
            self.typography = typography
        }
    }

    var onHeightInvalidated: (() -> Void)?
    var onOpenMarkdownLink: ((URL) -> Void)? {
        didSet {
            applyMarkdownLinkHandler()
        }
    }

    private var configuration: Configuration?
    private var contentViews: [NSView] = []
    private var lastMeasuredHeight: CGFloat = -1

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
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
        rebuildContentViews()
        needsLayout = true
        invalidateTranscriptHeight(force: true)
    }

    override func layout() {
        layoutContent()
        super.layout()
        invalidateTranscriptHeight(force: false)
    }

    private func rebuildContentViews() {
        contentViews.forEach { $0.removeFromSuperview() }
        guard let configuration else {
            contentViews = []
            return
        }

        var views = primaryViews(for: configuration.tool, typography: configuration.typography)
        if let stderr = configuration.tool.stderr,
           !stderr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let block = AppKitTranscriptDetailCodeBlockView()
            block.configure(.init(title: "stderr", content: stderr, tint: .orange, typography: configuration.typography))
            views.append(block)
        }

        views.forEach { view in
            view.translatesAutoresizingMaskIntoConstraints = true
            attachInvalidationHandler(to: view)
            addSubview(view)
        }
        contentViews = views
    }

    private func primaryViews(for tool: ToolEntry, typography: TranscriptTypography) -> [NSView] {
        if let snapshot = MinimalToolContent.snapshot(for: tool) {
            return minimalContentViews(for: tool, snapshot: snapshot, typography: typography)
        }

        var views: [NSView] = []
        let inputBlock = AppKitTranscriptDetailCodeBlockView()
        inputBlock.configure(.init(title: "Input", content: prettyPrintedJSON(tool.input), typography: typography))
        views.append(inputBlock)

        if let output = tool.output {
            let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
            if tool.isImage {
                views.append(messageLabel("Image output isn't previewed yet.", typography: typography))
            } else if trimmed.isEmpty {
                if !tool.noOutputExpected {
                    views.append(messageLabel("No output", typography: typography))
                }
            } else {
                let outputView = AppKitTranscriptToolOutputView()
                outputView.configure(.init(toolName: tool.name, content: output, typography: typography))
                views.append(outputView)
            }
        }

        return views
    }

    private func minimalContentViews(
        for tool: ToolEntry,
        snapshot: MinimalToolContent.Snapshot,
        typography: TranscriptTypography
    ) -> [NSView] {
        if tool.isError,
           let output = tool.output,
           !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let surface = AppKitTranscriptCodeSurfaceView()
            surface.configure(.plain(content: output, tint: .systemRed, typography: typography))
            return [surface]
        }

        if tool.isImage {
            return [messageLabel("Image output isn't previewed yet.", typography: typography)]
        }

        guard let content = snapshot.content,
              !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return tool.noOutputExpected ? [] : [messageLabel("No output", typography: typography)]
        }

        if tool.name == "Read", snapshot.language == "markdown" {
            return [
                AppKitTranscriptMarkdownToolContentView(
                    taskStateScope: tool.id,
                    markdown: ReadToolContent.strippingLineNumberPrefixes(from: content),
                    baseURL: ReadToolContent.baseURL(for: tool),
                    typography: typography,
                    onOpenMarkdownLink: onOpenMarkdownLink
                )
            ]
        }

        let block = AppKitTranscriptHighlightedCodeBlockView()
        block.configure(
            .init(
                content: content,
                language: snapshot.language,
                preservesLeadingLineNumberPrefixes: tool.name == "Read",
                typography: typography
            )
        )
        return [block]
    }

    private func messageLabel(_ text: String, typography: TranscriptTypography) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.textColor = .secondaryLabelColor
        label.font = typography.nsFont(.caption)
        label.lineBreakMode = .byTruncatingTail
        return label
    }

    private func attachInvalidationHandler(to view: NSView) {
        if let view = view as? AppKitTranscriptDetailCodeBlockView {
            view.onHeightInvalidated = { [weak self] in self?.childHeightInvalidated() }
        } else if let view = view as? AppKitTranscriptToolOutputView {
            view.onHeightInvalidated = { [weak self] in self?.childHeightInvalidated() }
        } else if let view = view as? AppKitTranscriptHighlightedCodeBlockView {
            view.onHeightInvalidated = { [weak self] in self?.childHeightInvalidated() }
        } else if let view = view as? AppKitTranscriptCodeSurfaceView {
            view.onHeightInvalidated = { [weak self] in self?.childHeightInvalidated() }
        } else if let view = view as? AppKitTranscriptMarkdownToolContentView {
            view.onHeightInvalidated = { [weak self] in self?.childHeightInvalidated() }
        }
    }

    private func applyMarkdownLinkHandler() {
        contentViews.compactMap { $0 as? AppKitTranscriptMarkdownToolContentView }
            .forEach { $0.onOpenMarkdownLink = onOpenMarkdownLink }
    }

    private func layoutContent() {
        var currentY: CGFloat = 0
        let width = max(bounds.width, 0)
        for view in contentViews {
            view.frame = NSRect(x: 0, y: currentY, width: width, height: CGFloat.greatestFiniteMagnitude / 2)
            view.layoutSubtreeIfNeeded()
            let height = ceil(view.intrinsicContentSize.height > 0 ? view.intrinsicContentSize.height : view.fittingSize.height)
            view.frame.size.height = height
            currentY += height + 10
        }
    }

    private func measuredHeight() -> CGFloat {
        guard !contentViews.isEmpty else {
            return 0
        }
        return contentViews.reduce(CGFloat.zero) { partialResult, view in
            let height = view.frame.height > 0 ? view.frame.height : view.intrinsicContentSize.height
            return partialResult + ceil(height)
        } + CGFloat(contentViews.count - 1) * 10
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

@MainActor
private final class AppKitTranscriptMarkdownToolContentView: AppKitDynamicColorView {
    var onHeightInvalidated: (() -> Void)?

    private let markdownView: AppKitMarkdownView
    private var lastMeasuredHeight: CGFloat = -1

    var onOpenMarkdownLink: ((URL) -> Void)? {
        didSet {
            markdownView.onOpenLink = onOpenMarkdownLink
        }
    }

    init(
        taskStateScope: String,
        markdown: String,
        baseURL: URL?,
        typography: TranscriptTypography,
        onOpenMarkdownLink: ((URL) -> Void)? = nil
    ) {
        let document = AppMarkdownDocumentCache.document(
            markdown: markdown,
            context: AppMarkdownDocumentCacheContext(
                baseURL: nil,
                inlineCodeStyle: .standard,
                composerChipMode: .none,
                taskStateScope: taskStateScope
            )
        ) {
            AppMarkdownParser().documentPreservingSource(for: markdown)
        }
        markdownView = AppKitMarkdownView(
            document: document,
            inlineCodeStyle: .standard,
            typography: typography.appKitMarkdownTypography,
            imageBaseURL: baseURL,
            onOpenLink: onOpenMarkdownLink
        )
        self.onOpenMarkdownLink = onOpenMarkdownLink
        super.init(frame: .zero)
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

    override func layout() {
        markdownView.frame = NSRect(
            x: 12,
            y: 10,
            width: max(bounds.width - 24, 0),
            height: CGFloat.greatestFiniteMagnitude / 2
        )
        markdownView.layoutSubtreeIfNeeded()
        markdownView.frame.size.height = markdownView.intrinsicContentSize.height
        super.layout()
        invalidateTranscriptHeight(force: false)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateAppearance()
    }

    private func setup() {
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.borderWidth = 1
        markdownView.translatesAutoresizingMaskIntoConstraints = true
        markdownView.onHeightInvalidated = { [weak self] in
            self?.invalidateTranscriptHeight(force: true)
        }
        addSubview(markdownView)
        updateAppearance()
    }

    private func updateAppearance() {
        setLayerFillColor(provider: { AppMarkdownCodeBlockPalette.fillNSColor(for: $0) })
        setLayerStrokeColor(provider: { AppMarkdownCodeBlockPalette.borderNSColor(for: $0) })
    }

    private func measuredHeight() -> CGFloat {
        ceil((markdownView.frame.height > 0 ? markdownView.frame.height : markdownView.intrinsicContentSize.height) + 20)
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
