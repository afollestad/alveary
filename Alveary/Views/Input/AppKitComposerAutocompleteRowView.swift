import AppKit

struct AutocompleteRowLayoutMetrics {
    let title: String
    let titleWidth: CGFloat
    let titleIntrinsicWidth: CGFloat
    let detailMinX: CGFloat
    let trailingText: String
    let trailingWidth: CGFloat
    let trailingIntrinsicWidth: CGFloat
    let trailingMaxX: CGFloat
    let titleMidY: CGFloat
    let detailMidY: CGFloat
    let trailingMidY: CGFloat
}

struct AutocompleteRowConfiguration {
    let kind: ComposerAutocompleteKind
    let suggestion: ComposerAutocompleteSuggestion
    let index: Int
    let query: String
    let isHighlighted: Bool
}

/// Native autocomplete row that preserves the SwiftUI popup's truncation rules.
///
/// Skill rows have three competing text regions. The title gets first claim,
/// trailing scope text stays bounded on the right, and the description takes
/// whatever middle space remains.
final class AppKitComposerAutocompleteRowView: NSView {
    private let iconView = NSImageView()
    private let titleField = NSTextField(labelWithString: "")
    private let detailField = NSTextField(labelWithString: "")
    private let trailingField = NSTextField(labelWithString: "")
    private var trackingArea: NSTrackingArea?
    private var kind = ComposerAutocompleteKind.file
    private var index = 0
    private var query = ""
    private var isHighlighted = false
    private var symbolName = "doc.text"
    private var onSelect: () -> Void = {}
    private var onHighlight: (Int) -> Void = { _ in }

    override var isFlipped: Bool {
        true
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    var titleForTesting: String {
        titleField.stringValue
    }

    var titleFrameForTesting: NSRect {
        titleField.frame
    }

    var detailFrameForTesting: NSRect {
        detailField.frame
    }

    var trailingTextForTesting: String {
        trailingField.stringValue
    }

    var trailingFrameForTesting: NSRect {
        trailingField.frame
    }

    var titleIntrinsicWidthForTesting: CGFloat {
        naturalTitleWidth
    }

    var trailingIntrinsicWidthForTesting: CGFloat {
        naturalTrailingWidth
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    func configure(
        _ configuration: AutocompleteRowConfiguration,
        onSelect: @escaping () -> Void,
        onHighlight: @escaping (Int) -> Void
    ) {
        kind = configuration.kind
        index = configuration.index
        query = configuration.query
        isHighlighted = configuration.isHighlighted
        symbolName = configuration.suggestion.symbolName
        self.onSelect = onSelect
        self.onHighlight = onHighlight

        updateImages()
        titleField.attributedStringValue = highlightedTitle(configuration.suggestion.title)
        detailField.stringValue = configuration.suggestion.subtitle ?? ""
        trailingField.stringValue = configuration.suggestion.trailingText ?? ""
        titleField.lineBreakMode = configuration.kind == .file ? .byTruncatingMiddle : .byTruncatingTail
        detailField.isHidden = configuration.kind == .file || detailField.stringValue.isEmpty
        trailingField.isHidden = configuration.kind == .file || trailingField.stringValue.isEmpty
        setAccessibilityLabel(accessibilityLabel(for: configuration.suggestion))
        needsLayout = true
        needsDisplay = true
    }

    override func layout() {
        super.layout()
        let iconSize: CGFloat = 14
        let iconY = floor((bounds.height - iconSize) / 2)
        let textHeight = max(
            ceil(titleField.intrinsicContentSize.height),
            ceil(detailField.intrinsicContentSize.height),
            ceil(trailingField.intrinsicContentSize.height)
        )
        let textY = floor((bounds.height - textHeight) / 2)
        let trailingPadding: CGFloat = 12
        let itemSpacing: CGFloat = 6
        iconView.frame = NSRect(x: 12, y: iconY, width: iconSize, height: iconSize)

        let contentX: CGFloat = 38
        let contentWidth = max(0, bounds.width - contentX - trailingPadding)
        if kind == .file {
            titleField.frame = NSRect(x: contentX, y: textY, width: contentWidth, height: textHeight)
            detailField.frame = NSRect(x: bounds.maxX - trailingPadding, y: textY, width: 0, height: textHeight)
            trailingField.frame = detailField.frame
        } else {
            layoutSkillRow(contentX: contentX, contentWidth: contentWidth, textY: textY, textHeight: textHeight, itemSpacing: itemSpacing)
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeInKeyWindow, .inVisibleRect],
            owner: self
        )
        trackingArea = area
        addTrackingArea(area)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateImages()
        needsDisplay = true
    }

    override func mouseEntered(with event: NSEvent) {
        highlightPointerRow()
    }

    override func mouseMoved(with event: NSEvent) {
        highlightPointerRow()
    }

    override func mouseDown(with event: NSEvent) {
        highlightPointerRow()
        onSelect()
    }

    override func scrollWheel(with event: NSEvent) {
        guard let popup = enclosingAutocompletePopup else {
            super.scrollWheel(with: event)
            return
        }
        let eventPoint = popup.convert(event.locationInWindow, from: nil)
        let popupPoint = popup.bounds.contains(eventPoint) ?
            eventPoint :
            popup.convert(NSPoint(x: bounds.midX, y: bounds.midY), from: self)
        if popup.routeScrollWheel(at: popupPoint, event: event) {
            return
        }
        super.scrollWheel(with: event)
    }

    override func accessibilityPerformPress() -> Bool {
        highlightPointerRow()
        onSelect()
        return true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        if isHighlighted {
            appKitComposerPrimaryColor(in: self, opacity: 0.1).setFill()
            NSBezierPath(roundedRect: bounds, xRadius: autocompleteRowCornerRadius, yRadius: autocompleteRowCornerRadius).fill()
        }
    }

    func updateImages() {
        iconView.image = symbolImage(named: symbolName, color: .secondaryLabelColor)
    }

    private func setup() {
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        [iconView, titleField, detailField, trailingField].forEach(addSubview)

        titleField.font = Self.titleFont
        titleField.textColor = .labelColor
        titleField.lineBreakMode = .byTruncatingMiddle
        detailField.font = Self.detailFont
        detailField.textColor = .secondaryLabelColor
        detailField.lineBreakMode = .byTruncatingTail
        trailingField.font = Self.detailFont
        trailingField.textColor = .secondaryLabelColor
        trailingField.lineBreakMode = .byTruncatingTail
    }

    private func highlightPointerRow() {
        guard !isHighlighted else {
            return
        }
        isHighlighted = true
        onHighlight(index)
        needsDisplay = true
    }

    private var enclosingAutocompletePopup: AppKitComposerAutocompletePopupView? {
        var candidate = superview
        while let view = candidate {
            if let popup = view as? AppKitComposerAutocompletePopupView {
                return popup
            }
            candidate = view.superview
        }
        return nil
    }

    private func layoutSkillRow(
        contentX: CGFloat,
        contentWidth: CGFloat,
        textY: CGFloat,
        textHeight: CGFloat,
        itemSpacing: CGFloat
    ) {
        let trailingCap = trailingField.isHidden ? 0 : min(naturalTrailingWidth, min(160, contentWidth * 0.30))
        let trailingReserve = trailingCap > 0 ? trailingCap + itemSpacing : 0
        let titleWidth = min(naturalTitleWidth, max(0, contentWidth - trailingReserve))
        let remainingAfterTitle = max(0, contentWidth - titleWidth)
        let trailingWidth = trailingField.isHidden ? 0 : min(trailingCap, max(0, remainingAfterTitle - itemSpacing))
        let trailingX = contentX + contentWidth - trailingWidth

        titleField.frame = NSRect(x: contentX, y: textY, width: titleWidth, height: textHeight)
        trailingField.frame = NSRect(x: trailingX, y: textY, width: trailingWidth, height: textHeight)

        let detailX = titleField.frame.maxX + itemSpacing
        let detailMaxX = trailingWidth > 0 ? trailingField.frame.minX - itemSpacing : contentX + contentWidth
        detailField.frame = NSRect(x: detailX, y: textY, width: max(0, detailMaxX - detailX), height: textHeight)
    }

    private var naturalTitleWidth: CGFloat {
        ceil((titleField.stringValue as NSString).size(withAttributes: [.font: Self.titleFont]).width) + 8
    }

    private var naturalTrailingWidth: CGFloat {
        ceil((trailingField.stringValue as NSString).size(withAttributes: [.font: Self.detailFont]).width) + 8
    }

    private func highlightedTitle(_ value: String) -> NSAttributedString {
        composerAutocompleteHighlightedText(
            value,
            query: query,
            regularFont: Self.titleFont,
            highlightedFont: Self.highlightedTitleFont,
            color: .labelColor
        )
    }

    private func accessibilityLabel(for suggestion: ComposerAutocompleteSuggestion) -> String {
        [suggestion.title, suggestion.subtitle, suggestion.trailingText]
            .compactMap { value in
                guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    return nil
                }
                return value
            }
            .joined(separator: ", ")
    }

    private func symbolImage(named name: String, color: NSColor) -> NSImage? {
        let configuration = NSImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
            .applying(.init(hierarchicalColor: color.appKitResolvedColor(in: self)))
        return NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration)
    }

    private static var titleFont: NSFont {
        .preferredFont(forTextStyle: .subheadline)
    }

    private static var detailFont: NSFont {
        .preferredFont(forTextStyle: .subheadline)
    }

    private static var highlightedTitleFont: NSFont {
        .systemFont(ofSize: titleFont.pointSize, weight: .semibold)
    }
}

private func composerAutocompleteHighlightedText(
    _ value: String,
    query: String,
    regularFont: NSFont,
    highlightedFont: NSFont,
    color: NSColor
) -> NSAttributedString {
    guard !query.isEmpty else {
        return NSAttributedString(string: value, attributes: [.font: regularFont, .foregroundColor: color])
    }

    let directRange = (value as NSString).range(of: query, options: [.caseInsensitive, .diacriticInsensitive])
    if directRange.location != NSNotFound {
        let result = NSMutableAttributedString(string: value, attributes: [.font: regularFont, .foregroundColor: color])
        result.addAttribute(.font, value: highlightedFont, range: directRange)
        return result
    }

    let normalizedQuery = query.lowercased()
    var queryIndex = normalizedQuery.startIndex
    let result = NSMutableAttributedString()

    for character in value {
        let characterString = String(character)
        let isMatch = queryIndex < normalizedQuery.endIndex &&
            characterString.lowercased() == String(normalizedQuery[queryIndex])
        result.append(NSAttributedString(
            string: characterString,
            attributes: [.font: isMatch ? highlightedFont : regularFont, .foregroundColor: color]
        ))
        if isMatch {
            queryIndex = normalizedQuery.index(after: queryIndex)
        }
    }

    return result
}
