@preconcurrency import AppKit
import Foundation

final class AppKitMarkdownTextView: NSTextView, NSTextViewDelegate {
    var onOpenLink: ((URL) -> Void)?

    private var heightInvalidationHandler: () -> Void = { }
    private var lastMeasuredHeight: CGFloat = 0
    private let wrapsToContainerWidth: Bool
    private var linkTrackingArea: NSTrackingArea?
    private var isForwardingVerticalScrollSequence = false
    private var verticalScrollSequenceToken = UUID()

    init(
        content: NSAttributedString,
        wrapsToContainerWidth: Bool = true,
        onOpenLink: ((URL) -> Void)? = nil,
        heightInvalidationHandler: @escaping () -> Void
    ) {
        let textStorage = NSTextStorage(attributedString: content)
        let layoutManager = NSLayoutManager()
        let textContainer = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        textStorage.addLayoutManager(layoutManager)
        layoutManager.addTextContainer(textContainer)
        self.wrapsToContainerWidth = wrapsToContainerWidth
        self.onOpenLink = onOpenLink
        self.heightInvalidationHandler = heightInvalidationHandler
        super.init(frame: .zero, textContainer: textContainer)
        setup()
    }

    override init(frame frameRect: NSRect, textContainer container: NSTextContainer?) {
        wrapsToContainerWidth = true
        super.init(frame: frameRect, textContainer: container)
        setup()
    }

    private func setup() {
        isEditable = false
        isSelectable = true
        delegate = self
        drawsBackground = false
        linkTextAttributes = [:]
        textContainerInset = .zero
        textContainer?.lineFragmentPadding = 0
        textContainer?.widthTracksTextView = wrapsToContainerWidth
        translatesAutoresizingMaskIntoConstraints = false
        setContentHuggingPriority(.defaultLow, for: .horizontal)
        setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: measuredHeight())
    }

    override func layout() {
        super.layout()
        if wrapsToContainerWidth {
            textContainer?.containerSize = NSSize(width: bounds.width, height: .greatestFiniteMagnitude)
        }
        let newHeight = measuredHeight()
        guard abs(newHeight - lastMeasuredHeight) > 0.5 else {
            return
        }
        lastMeasuredHeight = newHeight
        invalidateIntrinsicContentSize()
        heightInvalidationHandler()
    }

    override func updateTrackingAreas() {
        if let linkTrackingArea {
            removeTrackingArea(linkTrackingArea)
        }
        super.updateTrackingAreas()
        let trackingArea = NSTrackingArea(
            rect: .zero,
            options: [.activeInKeyWindow, .inVisibleRect, .mouseMoved],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
        linkTrackingArea = trackingArea
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        // NSTextView's selectable text rects use the I-beam cursor by default;
        // add link rects after `super` so links keep the pointing-hand cursor.
        for rect in linkCursorRects() {
            addCursorRect(rect, cursor: .pointingHand)
        }
    }

    override func mouseMoved(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        if linkURL(at: location) != nil {
            NSCursor.pointingHand.set()
        } else {
            super.mouseMoved(with: event)
        }
    }

    override func scrollWheel(with event: NSEvent) {
        if shouldForwardVerticalScroll(event),
           let ancestorScrollView = verticalAncestorScrollView {
            isForwardingVerticalScrollSequence = true
            schedulePhaseLessVerticalScrollSequenceResetIfNeeded(for: event)
            ancestorScrollView.scrollWheel(with: event)
            updateVerticalScrollSequenceState(after: event)
            return
        }
        if isForwardingVerticalScrollSequence,
           let ancestorScrollView = verticalAncestorScrollView {
            ancestorScrollView.scrollWheel(with: event)
            schedulePhaseLessVerticalScrollSequenceResetIfNeeded(for: event)
            updateVerticalScrollSequenceState(after: event)
            return
        }
        updateVerticalScrollSequenceState(after: event)
        super.scrollWheel(with: event)
    }

    private func measuredHeight() -> CGFloat {
        guard let layoutManager, let textContainer else {
            return 0
        }
        layoutManager.ensureLayout(for: textContainer)
        return ceil(layoutManager.usedRect(for: textContainer).height)
    }

    private func shouldForwardVerticalScroll(_ event: NSEvent) -> Bool {
        let deltaY = abs(event.scrollingDeltaY)
        return deltaY > 0 && deltaY >= abs(event.scrollingDeltaX)
    }

    private func updateVerticalScrollSequenceState(after event: NSEvent) {
        if event.phase.contains(.ended) || event.phase.contains(.cancelled) ||
            event.momentumPhase.contains(.ended) || event.momentumPhase.contains(.cancelled) {
            isForwardingVerticalScrollSequence = false
            verticalScrollSequenceToken = UUID()
        }
    }

    private func schedulePhaseLessVerticalScrollSequenceResetIfNeeded(for event: NSEvent) {
        guard event.phase == [], event.momentumPhase == [] else {
            return
        }
        let token = UUID()
        verticalScrollSequenceToken = token
        DispatchQueue.main.async { [weak self] in
            guard self?.verticalScrollSequenceToken == token else {
                return
            }
            self?.isForwardingVerticalScrollSequence = false
        }
    }

    private var verticalAncestorScrollView: NSScrollView? {
        var candidate = superview
        while let view = candidate {
            if let scrollView = view as? NSScrollView, scrollView.hasVerticalScroller {
                return scrollView
            }
            candidate = view.superview
        }
        return nil
    }

    func cursorURLForTesting(at point: NSPoint) -> URL? {
        linkURL(at: point)
    }

    var linkCursorRectsForTesting: [NSRect] {
        linkCursorRects()
    }

    func textView(
        _ textView: NSTextView,
        clickedOnLink link: Any,
        at charIndex: Int
    ) -> Bool {
        guard let url = markdownLinkURL(from: link),
              let onOpenLink else {
            return false
        }
        onOpenLink(url)
        return true
    }

    private func markdownLinkURL(from link: Any) -> URL? {
        if let url = link as? URL {
            return url
        }
        if let string = link as? String {
            return URL(string: string)
        }
        return nil
    }

    private func linkURL(at point: NSPoint) -> URL? {
        guard let textStorage else {
            return nil
        }
        for linkRange in linkRanges(in: textStorage) {
            if linkCursorRects(for: linkRange).contains(where: { $0.contains(point) }),
               let link = textStorage.attribute(.link, at: linkRange.location, effectiveRange: nil) {
                return markdownLinkURL(from: link)
            }
        }
        return nil
    }

    private func linkCursorRects() -> [NSRect] {
        guard let textStorage else {
            return []
        }
        return linkRanges(in: textStorage).flatMap(linkCursorRects(for:))
    }

    private func linkRanges(in textStorage: NSTextStorage) -> [NSRange] {
        guard textStorage.length > 0 else {
            return []
        }
        var ranges: [NSRange] = []
        textStorage.enumerateAttribute(
            .link,
            in: NSRange(location: 0, length: textStorage.length),
            options: []
        ) { value, range, _ in
            if value != nil {
                ranges.append(range)
            }
        }
        return ranges
    }

    private func linkCursorRects(for characterRange: NSRange) -> [NSRect] {
        guard let layoutManager, let textContainer, characterRange.length > 0 else {
            return []
        }
        layoutManager.ensureLayout(for: textContainer)
        let glyphRange = layoutManager.glyphRange(forCharacterRange: characterRange, actualCharacterRange: nil)
        guard glyphRange.length > 0 else {
            return []
        }
        var rects: [NSRect] = []
        let textOrigin = textContainerOrigin
        layoutManager.enumerateEnclosingRects(
            forGlyphRange: glyphRange,
            withinSelectedGlyphRange: NSRange(location: NSNotFound, length: 0),
            in: textContainer
        ) { rect, _ in
            rects.append(rect.offsetBy(dx: textOrigin.x, dy: textOrigin.y))
        }
        return rects
    }
}

final class AppKitMarkdownMarkerLabel: NSTextField {
    init(text: String, font: NSFont, color: NSColor = .secondaryLabelColor) {
        super.init(frame: .zero)
        stringValue = text
        isEditable = false
        isSelectable = false
        isBordered = false
        drawsBackground = false
        alignment = .right
        textColor = color
        // List markers are part of transcript text, so they must consume the
        // renderer typography instead of AppKit defaults. Otherwise chat
        // font-size changes resize list bodies while bullets/numbers lag behind.
        self.font = font
        translatesAutoresizingMaskIntoConstraints = false
        setContentHuggingPriority(.defaultLow, for: .horizontal)
        setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

final class AppKitMarkdownMarkerColumnView: NSView {
    private let contentView: NSView

    init(contentView: NSView) {
        self.contentView = contentView
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        addSubview(contentView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: contentView.intrinsicContentSize.height)
    }

    override func layout() {
        super.layout()
        contentView.frame = bounds
    }
}

final class AppKitMarkdownBulletMarkerView: NSView {
    let color: NSColor

    private let font: NSFont

    var bulletDiameterForTesting: CGFloat {
        bulletDiameter
    }

    var bulletRectForTesting: NSRect {
        bulletRect(in: bounds)
    }

    init(font: NSFont, color: NSColor = .secondaryLabelColor) {
        self.font = font
        self.color = color
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: ceil(font.ascender - font.descender + font.leading))
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        color.setFill()
        NSBezierPath(ovalIn: bulletRect(in: bounds)).fill()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    private var bulletDiameter: CGFloat {
        ceil(font.pointSize * AppKitMarkdownMetrics.unorderedBulletDiameterScale)
    }

    private func bulletRect(in bounds: NSRect) -> NSRect {
        let diameter = bulletDiameter
        return NSRect(
            x: min(AppKitMarkdownMetrics.unorderedBulletLeadingInset, max(bounds.width - diameter, 0)),
            y: max((bounds.height - diameter) / 2, 0),
            width: diameter,
            height: diameter
        )
    }
}
