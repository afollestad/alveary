@preconcurrency import AppKit
import Foundation
import SwiftUI

@MainActor
final class AppKitTranscriptCodeSurfaceView: AppKitDynamicColorView {
    enum Configuration {
        case plain(content: String, tint: NSColor, typography: TranscriptTypography)
        case highlighted(
            content: String,
            language: String,
            preservesLeadingLineNumberPrefixes: Bool,
            typography: TranscriptTypography
        )
    }

    var onHeightInvalidated: (() -> Void)?

    private let scrollView = AppKitHorizontalOverflowScrollView()
    private var textView: AppKitMarkdownTextView?
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
        guard !configuration.matches(self.configuration) else {
            return
        }
        self.configuration = configuration
        rebuildTextView()
        refreshAppearance()
        needsLayout = true
        invalidateTranscriptHeight(force: true)
    }

    override func layout() {
        let textSize = measuredTextSize()
        let height = ceil(textSize.height)
        scrollView.frame = NSRect(x: 0, y: 0, width: max(bounds.width, 0), height: height)
        if let textView {
            textView.frame = NSRect(x: 0, y: 0, width: max(textSize.width, bounds.width), height: ceil(textSize.height))
        }
        super.layout()
        invalidateTranscriptHeight(force: false)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshAppearance()
    }

    func refreshAppearance() {
        guard let configuration else {
            return
        }
        switch configuration {
        case .plain(_, let tint, _):
            setLayerFillColor(tint, alpha: 0.08)
            setLayerStrokeColor(tint, alpha: 0.12)
        case .highlighted:
            setLayerFillColor(provider: { AppMarkdownCodeBlockPalette.fillNSColor(for: $0) })
            setLayerStrokeColor(provider: { AppMarkdownCodeBlockPalette.borderNSColor(for: $0) })
        }
        textView?.textStorage?.setAttributedString(attributedContent(for: configuration))
    }

    private func setup() {
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.borderWidth = 1

        scrollView.borderType = .noBorder
        // Tool output matches SwiftUI's horizontal ScrollView treatment: long
        // lines can pan horizontally with an overlay scroller, but the scroller
        // does not reserve permanent vertical space in short command output.
        scrollView.hasHorizontalScroller = true
        scrollView.hasVerticalScroller = false
        scrollView.drawsBackground = false
        addSubview(scrollView)
    }

    private func rebuildTextView() {
        guard let configuration else {
            return
        }
        let textView = AppKitMarkdownTextView(
            content: attributedContent(for: configuration),
            wrapsToContainerWidth: false,
            heightInvalidationHandler: { [weak self] in
                self?.invalidateTranscriptHeight(force: true)
            }
        )
        textView.textContainer?.widthTracksTextView = false
        textView.textContainer?.containerSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.textContainerInset = NSSize(width: 12, height: 10)
        scrollView.documentView = textView
        self.textView = textView
    }

    private func attributedContent(for configuration: Configuration) -> NSAttributedString {
        switch configuration {
        case .plain(let content, _, let typography):
            return NSAttributedString(
                string: appKitCodeDisplayContent(content),
                attributes: [
                    .font: typography.codeNSFont,
                    .foregroundColor: NSColor.labelColor
                ]
            )
        case .highlighted(let content, let language, let preservesPrefixes, let typography):
            return AppKitMarkdownAttributedStringBuilder.syntaxHighlightedCode(
                appKitCodeDisplayContent(content),
                language: language,
                colorScheme: effectiveColorScheme,
                font: typography.codeNSFont,
                preserveLineNumberPrefixes: preservesPrefixes
            )
        }
    }

    private var effectiveColorScheme: ColorScheme {
        appKitRenderingAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? .dark : .light
    }

    private func measuredHeight() -> CGFloat {
        ceil(measuredTextSize().height)
    }

    private func measuredTextSize() -> NSSize {
        guard let textView else {
            return .zero
        }
        textView.layoutSubtreeIfNeeded()
        // Unwrapped code has no useful intrinsic width; ask AppKit's layout
        // manager for the used rect so horizontal scrolling keeps long lines intact.
        guard let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else {
            return .zero
        }
        layoutManager.ensureLayout(for: textContainer)
        let usedRect = layoutManager.usedRect(for: textContainer)
        return NSSize(
            width: ceil(usedRect.width + (textView.textContainerInset.width * 2)),
            height: ceil(usedRect.height + (textView.textContainerInset.height * 2))
        )
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

private extension AppKitTranscriptCodeSurfaceView.Configuration {
    func matches(_ other: AppKitTranscriptCodeSurfaceView.Configuration?) -> Bool {
        switch (self, other) {
        case (.plain(let lhsContent, let lhsTint, let lhsTypography), .plain(let rhsContent, let rhsTint, let rhsTypography)):
            return lhsContent == rhsContent && lhsTint == rhsTint && lhsTypography == rhsTypography
        case (
            .highlighted(let lhsContent, let lhsLanguage, let lhsPreservesPrefixes, let lhsTypography),
            .highlighted(let rhsContent, let rhsLanguage, let rhsPreservesPrefixes, let rhsTypography)
        ):
            return lhsContent == rhsContent
                && lhsLanguage == rhsLanguage
                && lhsPreservesPrefixes == rhsPreservesPrefixes
                && lhsTypography == rhsTypography
        default:
            return false
        }
    }
}
