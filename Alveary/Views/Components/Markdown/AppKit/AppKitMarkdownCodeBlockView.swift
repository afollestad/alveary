@preconcurrency import AppKit
import Foundation
import SwiftUI

final class AppKitMarkdownCodeBlockView: AppKitDynamicColorView {
    private let scrollView = AppKitHorizontalOverflowScrollView()
    private let code: String
    private let languageHint: String?
    private let codeFont: NSFont
    private weak var textView: AppKitMarkdownTextView?
    private weak var diffView: AppKitDiffCodeBlockView?

    init(
        code: String,
        languageHint: String?,
        codeFont: NSFont = .monospacedSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
    ) {
        self.code = code
        self.languageHint = languageHint
        self.codeFont = codeFont
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
        let documentSize = documentSize()
        return NSSize(
            width: NSView.noIntrinsicMetric,
            height: documentSize.height + horizontalScrollbarReserve(forDocumentWidth: documentSize.width)
        )
    }

    override func layout() {
        super.layout()
        // NSScrollView does not reliably size an AppKit document view from our
        // transcript probe frames; commit the code document size explicitly so
        // code text remains visible while bubble height is recalculated.
        let documentSize = documentSize()
        scrollView.documentView?.frame = NSRect(origin: .zero, size: documentSize)
        scrollView.clampHorizontalScrollOffset()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateLayerColors()
        textView?.textStorage?.setAttributedString(attributedCode())
    }

    private func setup() {
        wantsLayer = true
        layer?.borderWidth = 1
        layer?.cornerRadius = AppKitMarkdownMetrics.codeCornerRadius
        updateLayerColors()
        setupScrollView(documentView: diffRows.map(diffDocumentView(rows:)) ?? plainDocumentView())
    }

    /// A diff draws its own gutter and washes; every other language is highlighted text.
    private var diffRows: [DiffCodeHighlighting.Row]? {
        guard AppKitMarkdownCodeBlockView.rendersAsDiff(code: code, languageHint: languageHint) else {
            return nil
        }
        return DiffCodeHighlighting.rows(in: appKitCodeDisplayContent(code))
    }

    static func rendersAsDiff(code: String, languageHint: String?) -> Bool {
        let language = SyntaxHighlighter.normalizedLanguage(languageHint ?? "")
        return DiffCodeHighlighting.rendersAsDiff(
            language: language,
            isRecognizedLanguage: SyntaxHighlighter.recognizesLanguage(language),
            source: appKitCodeDisplayContent(code)
        )
    }

    private func diffDocumentView(rows: [DiffCodeHighlighting.Row]) -> NSView {
        let view = AppKitDiffCodeBlockView()
        view.onHeightInvalidated = { [weak self] in
            self?.invalidateIntrinsicContentSize()
        }
        view.configure(rows: rows, font: codeFont)
        diffView = view
        return view
    }

    private func plainDocumentView() -> NSView {
        let textView = AppKitMarkdownTextView(
            content: attributedCode(),
            wrapsToContainerWidth: false,
            heightInvalidationHandler: { }
        )
        self.textView = textView
        textView.textContainer?.widthTracksTextView = false
        textView.textContainer?.containerSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.textContainerInset = NSSize(width: 12, height: 10)
        textView.translatesAutoresizingMaskIntoConstraints = true
        return textView
    }

    private func setupScrollView(documentView: NSView) {
        scrollView.borderType = .noBorder
        scrollView.hasHorizontalScroller = true
        scrollView.hasVerticalScroller = false
        scrollView.drawsBackground = false
        scrollView.documentView = documentView
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    private func attributedCode() -> NSAttributedString {
        let colorScheme = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? ColorScheme.dark : .light
        return AppKitMarkdownAttributedStringBuilder.syntaxHighlightedCode(
            appKitCodeDisplayContent(code),
            language: languageHint ?? "",
            colorScheme: colorScheme,
            font: codeFont
        )
    }

    private func documentSize() -> NSSize {
        if let diffView {
            let size = diffView.intrinsicContentSize
            return NSSize(width: max(bounds.width, size.width), height: size.height)
        }
        guard let textView,
              let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else {
            return .zero
        }
        layoutManager.ensureLayout(for: textContainer)
        let usedRect = layoutManager.usedRect(for: textContainer)
        return NSSize(
            width: max(bounds.width, ceil(textView.measuredContentWidth() + textView.textContainerInset.width * 2)),
            height: ceil(usedRect.height + textView.textContainerInset.height * 2)
        )
    }

    private func horizontalScrollbarReserve(forDocumentWidth documentWidth: CGFloat) -> CGFloat {
        documentWidth > bounds.width + 0.5 ? appKitHorizontalOverflowScrollbarReserve : 0
    }

    private func updateLayerColors() {
        setLayerFillColor(provider: { AppMarkdownCodeBlockPalette.fillNSColor(for: $0) })
        setLayerStrokeColor(provider: { AppMarkdownCodeBlockPalette.borderNSColor(for: $0) })
    }
}
