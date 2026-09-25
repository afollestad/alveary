@preconcurrency import AppKit
import Foundation

private let streamingRevealFrameInterval: TimeInterval = 1.0 / 60.0
private let streamingRevealCatchUpFrameCount = 45
private let streamingRevealMaximumStepCharacterCount = 12
/// Zero-width sentinel appended after the displayed text so TextKit reports the insertion
/// location at the end of the stream; final glyph ink or line-used rects can lag behind the
/// actual caret position for side bearings and spaces.
private let streamingCaretSentinel = "\u{200B}"

/// AppKit row for the live assistant bubble shown before the final assistant
/// message is persisted into the transcript.
///
/// The row deliberately owns its own reveal timer and layout interpolation.
/// Harness deltas arrive in uneven batches, and replacing the whole string on
/// each batch makes the AppKit transcript feel like it refreshes every few
/// seconds instead of growing continuously like the prior SwiftUI surface.
/// Keep this row free of delayed frame animations: reveal ticks happen faster
/// than AppKit frame animations complete, and replaying old frames makes the
/// bubble, text, and caret appear to rewind.
///
/// Every reveal tick costs one TextKit layout of the appended characters, and the row tells the
/// transcript container about it only when its height actually changed: one persistent text
/// storage measures natural width, wrapped height, and caret position together, so a tick that
/// adds a word mid-line touches nothing outside this view. Anything else made a 60Hz tick a full
/// document pass over every row in the transcript.
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
    private let textStorage = NSTextStorage()
    private let layoutManager = NSLayoutManager()
    private let textContainer = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
    private var configuration: Configuration?
    private var targetText = ""
    private var displayedText = ""
    private var revealStepCharacterCount = 1
    private var revealTimer: Timer?
    private var lastReportedHeight: CGFloat = -1
    /// Layout of the displayed text at one available width; dropped whenever the text, font, or
    /// width cap changes so `layout()` and `intrinsicContentSize` share a single TextKit pass.
    private var cachedMetrics: StreamingBubbleMetrics?

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
        if previousConfiguration?.typography != configuration.typography {
            applyFont(configuration.typography.nsFont(.body))
        }
        cachedMetrics = nil
        updateTargetText(configuration.text, isInitialConfiguration: previousConfiguration == nil)
        updateAppearance()
        needsLayout = true
        invalidateTranscriptHeight(force: false)
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
        } else if targetText.utf8.count != displayedText.utf8.count {
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

        textContainer.lineFragmentPadding = 0
        textContainer.lineBreakMode = .byWordWrapping
        layoutManager.addTextContainer(textContainer)
        textStorage.addLayoutManager(layoutManager)
        textStorage.setAttributedString(NSAttributedString(
            string: streamingCaretSentinel,
            attributes: [.font: textField.font ?? NSFont.systemFont(ofSize: NSFont.systemFontSize)]
        ))

        cursorView.wantsLayer = true
        bubbleView.addSubview(cursorView)
        updateAppearance()
    }

    private func applyFont(_ font: NSFont) {
        textField.font = font
        textStorage.addAttribute(.font, value: font, range: NSRange(location: 0, length: textStorage.length))
    }

    private func layoutContent() {
        guard let metrics = metrics(forAvailableWidth: bounds.width) else {
            return
        }
        bubbleView.frame = NSRect(x: 0, y: 0, width: metrics.bubbleWidth, height: metrics.bubbleHeight)
        textField.frame = NSRect(
            x: chatBubbleHorizontalPadding,
            y: chatBubbleVerticalPadding,
            width: metrics.textWidth,
            height: metrics.textHeight
        )
        cursorView.frame = NSRect(
            x: min(
                chatBubbleHorizontalPadding + metrics.caretOrigin.x + 2,
                metrics.bubbleWidth - chatBubbleHorizontalPadding - 2
            ),
            y: chatBubbleVerticalPadding + metrics.caretOrigin.y,
            width: 2,
            height: metrics.caretHeight
        )
    }

    private func updateAppearance() {
        bubbleView.setLayerFillColor(.secondaryLabelColor, alpha: 0.08)
        textField.textColor = .labelColor
        cursorView.isHidden = false
        cursorView.setLayerFillColor(.labelColor, alpha: 0.65)
    }

    private func updateTargetText(_ text: String, isInitialConfiguration: Bool) {
        // SwiftUI can deliver an older transient value after a newer one during
        // bridge updates. The streaming row must stay monotonic within a turn so
        // any stale shorter value cannot make the bubble visibly rewind.
        let textLength = text.utf8.count
        if !isInitialConfiguration,
           textLength < max(targetText.utf8.count, displayedText.utf8.count) {
            return
        }

        targetText = text
        guard !isInitialConfiguration else {
            setDisplayedText(text)
            return
        }

        let displayedLength = displayedText.utf8.count
        guard window != nil,
              textLength > displayedLength,
              text.utf8.starts(with: displayedText.utf8) else {
            stopRevealTimer()
            revealStepCharacterCount = 1
            setDisplayedText(text)
            return
        }

        // Harness partials can arrive in coarse bursts. SwiftUI made those bursts feel
        // continuous by diffing text layout over frames; the AppKit row needs an explicit
        // reveal loop so long assistant responses do not visibly refresh in whole chunks.
        let appendedCount = textLength - displayedLength
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
            // Timers added to the main run loop fire on the main thread; hopping through a
            // `Task` here queued a second main-actor job for every frame.
            MainActor.assumeIsolated {
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

    /// The displayed text is a byte prefix of the target whenever the timer runs
    /// (`updateTargetText` replaces it outright otherwise), so the next reveal position is an
    /// index offset from the displayed length rather than a walk over the whole string.
    private func advanceStreamingReveal() {
        let signpost = AppKitTranscriptSignposts.begin("streaming.tick")
        defer { AppKitTranscriptSignposts.end(signpost) }
        let targetUTF8 = targetText.utf8
        let displayedLength = displayedText.utf8.count
        guard displayedLength < targetUTF8.count else {
            stopRevealTimer()
            return
        }

        let revealedEnd = targetUTF8.index(targetUTF8.startIndex, offsetBy: displayedLength)
        let nextEnd = targetText.index(revealedEnd, offsetBy: revealStepCharacterCount, limitedBy: targetText.endIndex)
            ?? targetText.endIndex
        if nextEnd == targetText.endIndex {
            setDisplayedText(targetText)
            stopRevealTimer()
        } else {
            setDisplayedText(String(targetText[..<nextEnd]))
        }
    }

    private func setDisplayedText(_ text: String) {
        guard text.utf8.count != displayedText.utf8.count || text != displayedText else {
            return
        }
        let previousText = displayedText
        displayedText = text
        textField.stringValue = text
        replaceStorageText(from: previousText, to: text)
        cachedMetrics = nil
        needsLayout = true
        invalidateTranscriptHeight(force: false)
    }

    /// Appends only the new suffix when the text grew, the steady state of a reveal tick;
    /// TextKit then relays out the affected lines instead of the whole bubble.
    private func replaceStorageText(from previousText: String, to text: String) {
        let previousLength = previousText.utf8.count
        let textLength = text.utf8.count
        textStorage.beginEditing()
        defer { textStorage.endEditing() }
        let sentinelLength = (streamingCaretSentinel as NSString).length
        let previousUTF16Length = textStorage.length - sentinelLength
        if textLength > previousLength, text.utf8.starts(with: previousText.utf8) {
            let appendedStart = text.utf8.index(text.utf8.startIndex, offsetBy: previousLength)
            textStorage.replaceCharacters(
                in: NSRange(location: previousUTF16Length, length: 0),
                with: String(text[appendedStart...])
            )
        } else {
            textStorage.replaceCharacters(in: NSRange(location: 0, length: previousUTF16Length), with: text)
        }
    }

    // Streaming text grows outside normal AppKit controls, so the row reports
    // height changes directly to keep the transcript container anchored.
    private func invalidateTranscriptHeight(force: Bool) {
        let newHeight = measuredHeight()
        guard force || abs(newHeight - lastReportedHeight) > 0.5 else {
            return
        }
        lastReportedHeight = newHeight
        invalidateIntrinsicContentSize()
        onHeightInvalidated?()
    }

    private func measuredHeight() -> CGFloat {
        if let metrics = metrics(forAvailableWidth: bounds.width) {
            return metrics.bubbleHeight
        }
        let lineHeight = textField.font.map { layoutManager.defaultLineHeight(for: $0) } ?? 0
        return ceil(max(lineHeight, 16) + (chatBubbleVerticalPadding * 2))
    }

    private func metrics(forAvailableWidth availableWidth: CGFloat) -> StreamingBubbleMetrics? {
        guard let configuration, availableWidth > 0 else {
            return nil
        }
        if let cachedMetrics, abs(cachedMetrics.availableWidth - availableWidth) < 0.5 {
            return cachedMetrics
        }
        let cap = configuration.bubbleMaxWidth.isFinite ? configuration.bubbleMaxWidth : availableWidth
        let maxBubbleWidth = min(max(cap, 0), availableWidth)
        let maxTextWidth = max(maxBubbleWidth - (chatBubbleHorizontalPadding * 2) - 4, 0)
        let textLayout = layoutText(width: maxTextWidth)
        let bubbleWidth = min(max(textLayout.naturalWidth + (chatBubbleHorizontalPadding * 2) + 6, 0), maxBubbleWidth)
        let textWidth = max(bubbleWidth - (chatBubbleHorizontalPadding * 2) - 4, 0)
        let metrics = StreamingBubbleMetrics(
            availableWidth: availableWidth,
            bubbleWidth: bubbleWidth,
            bubbleHeight: ceil(max(textLayout.height, 16) + (chatBubbleVerticalPadding * 2)),
            textWidth: textWidth,
            textHeight: textLayout.height,
            caretOrigin: CGPoint(x: min(max(textLayout.caretOrigin.x, 0), textWidth), y: textLayout.caretOrigin.y),
            caretHeight: textLayout.caretHeight
        )
        cachedMetrics = metrics
        return metrics
    }

    /// One layout at the widest text width the bubble may use yields everything the row needs.
    /// Text that wrapped at that width fills the cap; otherwise the widest line, hard line breaks
    /// included, is the natural width the bubble hugs. Laying the same text out again at the
    /// hugged width would produce identical lines, so the caret and height carry over.
    private func layoutText(width: CGFloat) -> StreamingTextLayout {
        guard width > 0, !displayedText.isEmpty else {
            return StreamingTextLayout(naturalWidth: 0, height: 0, caretOrigin: .zero, caretHeight: 16)
        }
        textContainer.size = NSSize(width: width, height: CGFloat.greatestFiniteMagnitude)
        layoutManager.ensureLayout(for: textContainer)

        let usedRect = layoutManager.usedRect(for: textContainer)
        let glyphIndex = layoutManager.glyphIndexForCharacter(at: textStorage.length - 1)
        let glyphLocation = layoutManager.location(forGlyphAt: glyphIndex)
        let lineRect = layoutManager.lineFragmentUsedRect(forGlyphAt: glyphIndex, effectiveRange: nil)
        let caretHeight = min(18, max(14, ceil(lineRect.height)))
        let caretY = lineRect.minY + max(0, (lineRect.height - caretHeight) / 2)
        return StreamingTextLayout(
            naturalWidth: layoutWrapsSoftly() ? width : ceil(usedRect.width),
            height: ceil(usedRect.height),
            caretOrigin: CGPoint(x: glyphLocation.x, y: caretY),
            caretHeight: caretHeight
        )
    }

    /// A line fragment that ends anywhere but at a line break was wrapped by the container width,
    /// so the text is wider than the bubble can hug. The sentinel's own line is the last one and
    /// never ends a fragment early, so it is skipped.
    private func layoutWrapsSoftly() -> Bool {
        // The proxy reads the backing store in place; bridging `string` would copy the whole text.
        let string = textStorage.mutableString
        let contentLength = textStorage.length - (streamingCaretSentinel as NSString).length
        var wrapsSoftly = false
        let glyphRange = NSRange(location: 0, length: layoutManager.numberOfGlyphs)
        layoutManager.enumerateLineFragments(forGlyphRange: glyphRange) { [layoutManager] _, _, _, lineGlyphRange, stop in
            let lineEnd = NSMaxRange(layoutManager.characterRange(forGlyphRange: lineGlyphRange, actualGlyphRange: nil))
            guard lineEnd > 0, lineEnd <= contentLength else {
                return
            }
            if !Self.isLineBreak(string.character(at: lineEnd - 1)) {
                wrapsSoftly = true
                stop.pointee = true
            }
        }
        return wrapsSoftly
    }

    private static func isLineBreak(_ character: unichar) -> Bool {
        switch character {
        case 0x0A, 0x0B, 0x0C, 0x0D, 0x85, 0x2028, 0x2029:
            return true
        default:
            return false
        }
    }
}

private struct StreamingTextLayout {
    let naturalWidth: CGFloat
    let height: CGFloat
    let caretOrigin: CGPoint
    let caretHeight: CGFloat
}

private struct StreamingBubbleMetrics {
    let availableWidth: CGFloat
    let bubbleWidth: CGFloat
    let bubbleHeight: CGFloat
    let textWidth: CGFloat
    let textHeight: CGFloat
    let caretOrigin: CGPoint
    let caretHeight: CGFloat
}

#if DEBUG
extension AppKitTranscriptStreamingBubbleView {
    var displayedTextForTesting: String {
        displayedText
    }

    var cursorFrameForTesting: NSRect {
        cursorView.frame
    }

    var cursorIsHiddenForTesting: Bool {
        cursorView.isHidden
    }

    func advanceStreamingRevealForTesting() {
        advanceStreamingReveal()
    }
}
#endif
