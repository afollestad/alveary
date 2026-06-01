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

@MainActor
final class AppKitTranscriptDetailMarkdownView: NSView {
    struct Configuration: Equatable {
        let title: String
        let content: String
        let taskStateScope: String
        let typography: TranscriptTypography

        init(
            title: String,
            content: String,
            taskStateScope: String,
            typography: TranscriptTypography = TranscriptTypography()
        ) {
            self.title = title
            self.content = content
            self.taskStateScope = taskStateScope
            self.typography = typography
        }
    }

    var onHeightInvalidated: (() -> Void)?
    var onOpenMarkdownLink: ((URL) -> Void)? {
        didSet {
            markdownView?.onOpenLink = onOpenMarkdownLink
        }
    }

    private let titleField = NSTextField(labelWithString: "")
    private let chromeView = AppKitFlippedDynamicColorView()
    private var markdownView: AppKitMarkdownView?
    private var document: AppMarkdownDocument?
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
        titleField.textColor = .secondaryLabelColor

        markdownView?.removeFromSuperview()
        let document = AppMarkdownDocumentCache.document(
            markdown: configuration.content,
            context: AppMarkdownDocumentCacheContext(
                baseURL: nil,
                inlineCodeStyle: .standard,
                composerChipMode: .none,
                taskStateScope: configuration.taskStateScope
            )
        ) {
            AppMarkdownParser().documentPreservingSource(for: configuration.content)
        }
        self.document = document
        let markdownView = AppKitMarkdownView(
            document: document,
            inlineCodeStyle: .standard,
            typography: configuration.typography.appKitMarkdownTypography,
            onOpenLink: onOpenMarkdownLink
        )
        markdownView.translatesAutoresizingMaskIntoConstraints = true
        markdownView.onHeightInvalidated = { [weak self] in
            self?.invalidateTranscriptHeight(force: true)
        }
        chromeView.addSubview(markdownView)
        self.markdownView = markdownView
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
        titleField.translatesAutoresizingMaskIntoConstraints = true
        chromeView.translatesAutoresizingMaskIntoConstraints = true
        chromeView.wantsLayer = true
        chromeView.layer?.cornerRadius = 8
        chromeView.layer?.borderWidth = 1
        addSubview(titleField)
        addSubview(chromeView)
        updateAppearance()
    }

    private func layoutContent() {
        let width = max(bounds.width, 0)
        let titleHeight = ceil(titleField.fittingSize.height)
        titleField.frame = NSRect(x: 0, y: 0, width: width, height: titleHeight)

        guard let markdownView else {
            chromeView.frame = .zero
            return
        }
        chromeView.frame = NSRect(
            x: 0,
            y: titleHeight + 6,
            width: width,
            height: 0
        )
        let markdownHeight = measuredMarkdownHeight(width: width - 24)
        markdownView.frame = NSRect(
            x: 12,
            y: 10,
            width: max(width - 24, 0),
            height: markdownHeight
        )
        markdownView.layoutSubtreeIfNeeded()
        chromeView.frame.size.height = markdownHeight + 20
    }

    private func updateAppearance() {
        chromeView.setLayerFillColor(provider: { AppMarkdownCodeBlockPalette.fillNSColor(for: $0) })
        chromeView.setLayerStrokeColor(provider: { AppMarkdownCodeBlockPalette.borderNSColor(for: $0) })
    }

    private func measuredHeight() -> CGFloat {
        let markdownHeight = measuredMarkdownHeight(width: bounds.width - 24)
        return ceil(titleField.fittingSize.height) + 6 + markdownHeight + 20
    }

    private func measuredMarkdownHeight(width: CGFloat) -> CGFloat {
        guard let document,
              let configuration else {
            return markdownView?.intrinsicContentSize.height ?? 0
        }
        return AppKitMarkdownLayoutMeasurer(
            document: document,
            inlineCodeStyle: .standard,
            typography: configuration.typography.appKitMarkdownTypography
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

enum TranscriptResultPresentation {
    static func prefersMarkdown(_ content: String) -> Bool {
        let nonEmptyLines = content
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !nonEmptyLines.isEmpty else {
            return false
        }
        if content.contains("```") || content.contains("](") || content.contains("![") {
            return true
        }
        if let first = nonEmptyLines.first,
           nonEmptyLines.count > 1,
           isMarkdownHeading(first) {
            return true
        }
        if nonEmptyLines.contains(where: isMarkdownTableDelimiter) {
            return true
        }
        if nonEmptyLines.filter(isMarkdownListItem).count >= 2 {
            return true
        }
        if nonEmptyLines.filter({ $0.hasPrefix("> ") }).count >= 2 {
            return true
        }
        return false
    }

    private static func isMarkdownHeading(_ line: String) -> Bool {
        let count = line.prefix { $0 == "#" }.count
        guard (1...6).contains(count) else {
            return false
        }
        let suffix = line.dropFirst(count)
        return suffix.first == " " && !suffix.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private static func isMarkdownTableDelimiter(_ line: String) -> Bool {
        line.contains("|") && line.contains("---")
    }

    private static func isMarkdownListItem(_ line: String) -> Bool {
        if line.hasPrefix("- ") || line.hasPrefix("* ") || line.hasPrefix("+ ") ||
            line.hasPrefix("- [ ] ") || line.hasPrefix("- [x] ") {
            return true
        }
        return line.range(of: #"^\d+[\.)]\s+"#, options: .regularExpression) != nil
    }
}
