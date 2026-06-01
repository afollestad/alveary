@preconcurrency import AppKit
import Foundation
import SwiftUI

final class AppKitMarkdownCodeBlockView: AppKitDynamicColorView {
    private let scrollView = AppKitHorizontalOverflowScrollView()
    private let code: String
    private let languageHint: String?
    private let codeFont: NSFont
    private weak var textView: AppKitMarkdownTextView?

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
        let documentSize = codeDocumentSize()
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
        let documentSize = codeDocumentSize()
        textView?.frame = NSRect(origin: .zero, size: documentSize)
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

        scrollView.borderType = .noBorder
        scrollView.hasHorizontalScroller = true
        scrollView.hasVerticalScroller = false
        scrollView.drawsBackground = false
        scrollView.documentView = textView
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

    private func codeDocumentSize() -> NSSize {
        guard let textView,
              let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else {
            return .zero
        }
        layoutManager.ensureLayout(for: textContainer)
        let usedRect = layoutManager.usedRect(for: textContainer)
        return NSSize(
            width: max(bounds.width, ceil(usedRect.width + textView.textContainerInset.width * 2)),
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
