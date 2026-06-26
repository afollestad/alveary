@preconcurrency import AppKit
import BlockInputKit
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
    var onUserInitiatedHeightChange: (() -> Void)? {
        didSet {
            applyUserInitiatedHeightChangeHandler()
        }
    }
    var onOpenMarkdownLink: ((URL) -> Void)? {
        didSet {
            applyMarkdownLinkHandler()
        }
    }
    var onOpenMarkdownImage: ((BlockInputImage, URL?) -> Void)? {
        didSet {
            applyMarkdownImageHandler()
        }
    }
    var onOpenToolImage: ((ToolEntry) -> Void)? {
        didSet {
            applyToolImageHandler()
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
        if let fileChange = CodexFileChangePresentation.extract(from: tool) {
            return fileChangeViews(for: fileChange, tool: tool, typography: typography)
        }

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
                views.append(imagePreviewButton(for: tool, typography: typography))
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

    private func fileChangeViews(
        for fileChange: CodexFileChangePresentation,
        tool: ToolEntry,
        typography: TranscriptTypography
    ) -> [NSView] {
        if tool.isError,
           let output = tool.output,
           !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let surface = AppKitTranscriptCodeSurfaceView()
            surface.configure(.plain(content: output, tint: .systemRed, typography: typography))
            return [surface]
        }

        return fileChange.changes.map { change in
            let block = AppKitTranscriptDetailCodeBlockView()
            block.configure(
                .init(
                    title: change.detailTitle,
                    content: change.diff,
                    language: change.contentLanguage,
                    typography: typography
                )
            )
            return block
        }
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
            return [imagePreviewButton(for: tool, typography: typography)]
        }

        guard let content = snapshot.content,
              !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return tool.noOutputExpected ? [] : [messageLabel("No output", typography: typography)]
        }

        if snapshot.language == "markdown" {
            let markdown = tool.name == "Read"
                ? ReadToolContent.strippingLineNumberPrefixes(from: content)
                : content
            return [
                AppKitTranscriptMarkdownToolContentView(
                    taskStateScope: tool.id,
                    markdown: markdown,
                    baseURL: snapshot.baseURL,
                    typography: typography,
                    onOpenMarkdownLink: onOpenMarkdownLink,
                    onOpenMarkdownImage: onOpenMarkdownImage
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

    private func imagePreviewButton(for tool: ToolEntry, typography: TranscriptTypography) -> NSButton {
        let button = AppKitTranscriptToolImagePreviewButton()
        button.configure(tool: tool, typography: typography)
        button.onOpenToolImage = onOpenToolImage
        return button
    }

    private func attachInvalidationHandler(to view: NSView) {
        if let view = view as? AppKitTranscriptDetailCodeBlockView {
            view.onHeightInvalidated = { [weak self] in self?.childHeightInvalidated() }
        } else if let view = view as? AppKitTranscriptToolOutputView {
            view.onUserInitiatedHeightChange = onUserInitiatedHeightChange
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

    private func applyMarkdownImageHandler() {
        contentViews.compactMap { $0 as? AppKitTranscriptMarkdownToolContentView }
            .forEach { $0.onOpenMarkdownImage = onOpenMarkdownImage }
    }

    private func applyToolImageHandler() {
        contentViews.compactMap { $0 as? AppKitTranscriptToolImagePreviewButton }
            .forEach { $0.onOpenToolImage = onOpenToolImage }
    }

    private func applyUserInitiatedHeightChangeHandler() {
        contentViews.compactMap { $0 as? AppKitTranscriptToolOutputView }
            .forEach { $0.onUserInitiatedHeightChange = onUserInitiatedHeightChange }
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
    private let document: AppMarkdownDocument
    private let typography: TranscriptTypography
    private var lastMeasuredHeight: CGFloat = -1

    var onOpenMarkdownLink: ((URL) -> Void)? {
        didSet {
            markdownView.onOpenLink = onOpenMarkdownLink
        }
    }
    var onOpenMarkdownImage: ((BlockInputImage, URL?) -> Void)? {
        didSet {
            markdownView.onOpenImage = onOpenMarkdownImage
        }
    }

    init(
        taskStateScope: String,
        markdown: String,
        baseURL: URL?,
        typography: TranscriptTypography,
        onOpenMarkdownLink: ((URL) -> Void)? = nil,
        onOpenMarkdownImage: ((BlockInputImage, URL?) -> Void)? = nil
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
        self.document = document
        self.typography = typography
        markdownView = AppKitMarkdownView(
            document: document,
            inlineCodeStyle: .standard,
            typography: typography.appKitMarkdownTypography,
            imageBaseURL: baseURL,
            onOpenLink: onOpenMarkdownLink,
            onOpenImage: onOpenMarkdownImage
        )
        self.onOpenMarkdownLink = onOpenMarkdownLink
        self.onOpenMarkdownImage = onOpenMarkdownImage
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
        let markdownWidth = max(bounds.width - 24, 0)
        let markdownHeight = measuredMarkdownHeight(width: markdownWidth)
        markdownView.frame = NSRect(
            x: 12,
            y: 10,
            width: markdownWidth,
            height: markdownHeight
        )
        markdownView.layoutSubtreeIfNeeded()
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
        clipsToBounds = true
        layer?.cornerRadius = 8
        layer?.borderWidth = 1
        layer?.masksToBounds = true
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
        ceil(measuredMarkdownHeight(width: bounds.width - 24) + 20)
    }

    private func measuredMarkdownHeight(width: CGFloat) -> CGFloat {
        AppKitMarkdownLayoutMeasurer(
            document: document,
            inlineCodeStyle: .standard,
            typography: typography.appKitMarkdownTypography
        )
        .measure(width: max(width, 0))
        .contentHeight
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

@MainActor
private final class AppKitTranscriptToolImagePreviewButton: NSButton {
    private var tool: ToolEntry?
    var onOpenToolImage: ((ToolEntry) -> Void)? {
        didSet {
            updateEnabledState()
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(tool: ToolEntry, typography: TranscriptTypography) {
        self.tool = tool
        title = "Preview image"
        font = typography.nsFont(.caption, weight: .semibold)
        updateEnabledState()
    }

    private func setup() {
        controlSize = .small
        bezelStyle = .rounded
        target = self
        action = #selector(openImage)
        setAccessibilityLabel("Preview image output")
    }

    @objc private func openImage() {
        guard let tool else {
            return
        }
        onOpenToolImage?(tool)
    }

    private func updateEnabledState() {
        let hasPayload = tool?.output?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        isEnabled = hasPayload && onOpenToolImage != nil
    }
}
