@preconcurrency import AppKit
import Foundation

private struct StreamingCaretLayout {
    let origin: CGPoint
    let height: CGFloat
}

private let streamingRevealFrameInterval: TimeInterval = 1.0 / 60.0
private let streamingRevealCatchUpFrameCount = 45
private let streamingRevealMaximumStepCharacterCount = 12

/// AppKit row for the live assistant bubble shown before the final assistant
/// message is persisted into the transcript.
///
/// The row deliberately owns its own reveal timer and layout interpolation.
/// Provider deltas arrive in uneven batches, and replacing the whole string on
/// each batch makes the AppKit transcript feel like it refreshes every few
/// seconds instead of growing continuously like the prior SwiftUI surface.
/// Keep this row free of delayed frame animations: reveal ticks happen faster
/// than AppKit frame animations complete, and replaying old frames makes the
/// bubble, text, and caret appear to rewind.
@MainActor
final class AppKitTranscriptStreamingBubbleView: NSView {
    struct Configuration: Equatable {
        let text: String
        let bubbleMaxWidth: CGFloat
        let typography: TranscriptTypography

        init(
            text: String,
            bubbleMaxWidth: CGFloat = .infinity,
            typography: TranscriptTypography = TranscriptTypography()
        ) {
            self.text = text
            self.bubbleMaxWidth = bubbleMaxWidth
            self.typography = typography
        }
    }

    var onHeightInvalidated: (() -> Void)?

    private let bubbleView = AppKitFlippedDynamicColorView()
    private let textField = NSTextField(labelWithString: "")
    private let cursorView = AppKitDynamicColorView()
    private var configuration: Configuration?
    private var targetText = ""
    private var displayedText = ""
    private var revealStepCharacterCount = 1
    private var revealTimer: Timer?
    private var lastMeasuredHeight: CGFloat = -1

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    deinit {
        MainActor.assumeIsolated {
            revealTimer?.invalidate()
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isFlipped: Bool { true }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: measuredHeight())
    }

    func configure(_ configuration: Configuration) {
        guard self.configuration != configuration else {
            return
        }
        let previousConfiguration = self.configuration
        self.configuration = configuration
        textField.font = configuration.typography.nsFont(.body)
        updateTargetText(configuration.text, isInitialConfiguration: previousConfiguration == nil)
        updateAppearance()
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

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            stopRevealTimer()
        } else if targetText != displayedText {
            startRevealTimer()
        }
    }

    private func setup() {
        translatesAutoresizingMaskIntoConstraints = false
        bubbleView.wantsLayer = true
        bubbleView.layer?.cornerRadius = chatBubbleCornerRadius
        addSubview(bubbleView)

        textField.translatesAutoresizingMaskIntoConstraints = true
        textField.lineBreakMode = .byWordWrapping
        textField.maximumNumberOfLines = 0
        textField.isSelectable = true
        bubbleView.addSubview(textField)

        cursorView.wantsLayer = true
        bubbleView.addSubview(cursorView)
        updateAppearance()
    }

    private func layoutContent() {
        guard let configuration, bounds.width > 0 else {
            return
        }

        let width = bubbleWidth(for: configuration, fitting: fittingTextWidth())
        let textWidth = max(width - (chatBubbleHorizontalPadding * 2) - 4, 0)
        let textHeight = measuredTextHeight(width: textWidth)
        let height = max(textHeight, 16) + (chatBubbleVerticalPadding * 2)
        let caretLayout = streamingCaretLayout(textWidth: textWidth)
        bubbleView.frame = NSRect(x: 0, y: 0, width: width, height: height)
        textField.frame = NSRect(
            x: chatBubbleHorizontalPadding,
            y: chatBubbleVerticalPadding,
            width: textWidth,
            height: textHeight
        )
        cursorView.frame = NSRect(
            x: min(
                chatBubbleHorizontalPadding + caretLayout.origin.x + 2,
                width - chatBubbleHorizontalPadding - 2
            ),
            y: chatBubbleVerticalPadding + caretLayout.origin.y,
            width: 2,
            height: caretLayout.height
        )
    }

    private func bubbleWidth(for configuration: Configuration, fitting textWidth: CGFloat) -> CGFloat {
        let availableWidth = max(bounds.width, 0)
        let cap = configuration.bubbleMaxWidth.isFinite ? configuration.bubbleMaxWidth : availableWidth
        let maxWidth = min(max(cap, 0), availableWidth)
        let contentWidth = textWidth + (chatBubbleHorizontalPadding * 2) + 6
        return min(max(contentWidth, 0), maxWidth)
    }

    private func updateAppearance() {
        bubbleView.setLayerFillColor(.secondaryLabelColor, alpha: 0.08)
        cursorView.setLayerFillColor(.labelColor, alpha: 0.65)
    }

    private func updateTargetText(_ text: String, isInitialConfiguration: Bool) {
        // SwiftUI can deliver an older transient value after a newer one during
        // bridge updates. The streaming row must stay monotonic within a turn so
        // any stale shorter value cannot make the bubble visibly rewind.
        if !isInitialConfiguration,
           text.count < max(targetText.count, displayedText.count) {
            return
        }

        targetText = text
        guard !isInitialConfiguration else {
            setDisplayedText(text)
            return
        }

        guard window != nil,
              text.hasPrefix(displayedText),
              text.count > displayedText.count else {
            stopRevealTimer()
            revealStepCharacterCount = 1
            setDisplayedText(text)
            return
        }

        // Provider partials can arrive in coarse bursts. SwiftUI made those bursts feel
        // continuous by diffing text layout over frames; the AppKit row needs an explicit
        // reveal loop so long assistant responses do not visibly refresh in whole chunks.
        let appendedCount = text.count - displayedText.count
        revealStepCharacterCount = min(
            streamingRevealMaximumStepCharacterCount,
            max(1, Int(ceil(Double(appendedCount) / Double(streamingRevealCatchUpFrameCount))))
        )
        startRevealTimer()
    }

    private func startRevealTimer() {
        guard revealTimer == nil else {
            return
        }
        let timer = Timer(timeInterval: streamingRevealFrameInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.advanceStreamingReveal()
            }
        }
        revealTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func stopRevealTimer() {
        revealTimer?.invalidate()
        revealTimer = nil
    }

    private func advanceStreamingReveal() {
        guard targetText != displayedText else {
            stopRevealTimer()
            return
        }

        guard targetText.hasPrefix(displayedText) else {
            stopRevealTimer()
            setDisplayedText(targetText)
            return
        }

        let nextCount = min(targetText.count, displayedText.count + revealStepCharacterCount)
        setDisplayedText(String(targetText.prefix(nextCount)))

        if displayedText == targetText {
            stopRevealTimer()
        }
    }

    private func setDisplayedText(_ text: String) {
        guard displayedText != text else {
            return
        }
        displayedText = text
        textField.stringValue = text
        needsLayout = true
        invalidateTranscriptHeight(force: true)
    }

    // Streaming text grows outside normal AppKit controls, so the row reports
    // height changes directly to keep the transcript container anchored.
    private func invalidateTranscriptHeight(force: Bool) {
        let newHeight = measuredHeight()
        guard force || abs(newHeight - lastMeasuredHeight) > 0.5 else {
            return
        }
        lastMeasuredHeight = newHeight
        invalidateIntrinsicContentSize()
        onHeightInvalidated?()
    }

    private func measuredHeight() -> CGFloat {
        if bubbleView.frame.height > 0 {
            return ceil(bubbleView.frame.height)
        }
        return ceil(max(measuredTextHeight(width: textField.frame.width), 16) + (chatBubbleVerticalPadding * 2))
    }

    private func measuredTextHeight(width: CGFloat) -> CGFloat {
        guard let font = textField.font,
              width > 0 else {
            return textField.fittingSize.height
        }
        let boundingRect = (textField.stringValue as NSString).boundingRect(
            with: CGSize(width: width, height: CGFloat.greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font]
        )
        return ceil(boundingRect.height)
    }

    private func fittingTextWidth() -> CGFloat {
        guard let font = textField.font else {
            return textField.fittingSize.width
        }
        let boundingRect = (textField.stringValue as NSString).boundingRect(
            with: CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font]
        )
        return ceil(boundingRect.width)
    }

    private func streamingCaretLayout(textWidth: CGFloat) -> StreamingCaretLayout {
        // The caret should track the end of the laid-out text, not the full
        // wrapping line width. NSTextField does not expose that geometry, so use
        // the same TextKit layout primitives AppKit uses for wrapping.
        guard let font = textField.font,
              textWidth > 0,
              !displayedText.isEmpty else {
            return StreamingCaretLayout(origin: CGPoint(x: 0, y: 0), height: 16)
        }

        let caretSentinel = "\u{200B}"
        let textStorage = NSTextStorage(string: displayedText + caretSentinel, attributes: [.font: font])
        let layoutManager = NSLayoutManager()
        let textContainer = NSTextContainer(size: NSSize(width: textWidth, height: CGFloat.greatestFiniteMagnitude))
        textContainer.lineFragmentPadding = 0
        textContainer.lineBreakMode = .byWordWrapping
        layoutManager.addTextContainer(textContainer)
        textStorage.addLayoutManager(layoutManager)
        layoutManager.ensureLayout(for: textContainer)

        let glyphIndex = layoutManager.glyphIndexForCharacter(at: textStorage.length - 1)
        let glyphLocation = layoutManager.location(forGlyphAt: glyphIndex)
        let lineRect = layoutManager.lineFragmentUsedRect(forGlyphAt: glyphIndex, effectiveRange: nil)
        let caretHeight = min(18, max(14, ceil(lineRect.height)))
        let caretY = lineRect.minY + max(0, (lineRect.height - caretHeight) / 2)
        return StreamingCaretLayout(
            // A zero-width sentinel gives TextKit's insertion location for the
            // end of the stream; final glyph ink or line-used rects can lag
            // behind the actual caret position for side bearings and spaces.
            origin: CGPoint(x: min(max(glyphLocation.x, 0), textWidth), y: caretY),
            height: caretHeight
        )
    }

}

#if DEBUG
extension AppKitTranscriptStreamingBubbleView {
    var displayedTextForTesting: String {
        displayedText
    }

    var cursorFrameForTesting: NSRect {
        cursorView.frame
    }

    func advanceStreamingRevealForTesting() {
        advanceStreamingReveal()
    }
}
#endif
