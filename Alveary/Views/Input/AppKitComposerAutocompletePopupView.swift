import AppKit
import SwiftUI

let autocompleteRowCornerRadius: CGFloat = 14
let autocompleteListSpacing: CGFloat = 6

private let autocompletePopupCornerRadius: CGFloat = 18
private let autocompleteMaxVisibleRows = 6

/// Testing-only geometry exported from the native popup so regressions in
/// loading/empty placeholder vertical alignment are caught without pixel math.
struct AutocompletePlaceholderMetrics {
    let popupMidY: CGFloat
    let loadingIndicatorMidY: CGFloat
    let loadingTextMidY: CGFloat
    let emptyTextMidY: CGFloat
}

/// Native autocomplete popup shared by the transitional SwiftUI composer host.
///
/// Rendering the popup as AppKit lets the chat surface route hit testing into
/// rows that visually float above the composer panel instead of relying on
/// SwiftUI overlay bounds.
@MainActor
final class AppKitComposerAutocompletePopupView: NSView {
    private var autocomplete: ComposerAutocompleteState?
    private var rowViews: [AppKitComposerAutocompleteRowView] = []
    private let loadingIndicator = NSProgressIndicator()
    private let loadingField = NSTextField(labelWithString: "Loading suggestions...")
    private let emptyField = NSTextField(labelWithString: "No matches yet")
    private var visibleStartIndex = 0
    private var visibleWindowSessionID: UUID?
    private var visibleWindowSuggestionIDs: [String] = []
    private var onSelect: (ComposerAutocompleteSuggestion) -> Void = { _ in }
    private var onHighlight: (Int) -> Void = { _ in }

    override var isFlipped: Bool {
        true
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: Self.measuredHeight(for: autocomplete))
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    var visibleSuggestionTitlesForTesting: [String] {
        rowViews.map(\.titleForTesting)
    }

    var visibleRowLayoutMetricsForTesting: [AutocompleteRowLayoutMetrics] {
        rowViews.map {
            AutocompleteRowLayoutMetrics(
                title: $0.titleForTesting,
                titleWidth: $0.titleFrameForTesting.width,
                titleIntrinsicWidth: $0.titleIntrinsicWidthForTesting,
                detailMinX: $0.detailFrameForTesting.minX,
                trailingText: $0.trailingTextForTesting,
                trailingWidth: $0.trailingFrameForTesting.width,
                trailingIntrinsicWidth: $0.trailingIntrinsicWidthForTesting,
                trailingMaxX: $0.trailingFrameForTesting.maxX,
                titleMidY: $0.titleFrameForTesting.midY,
                detailMidY: $0.detailFrameForTesting.midY,
                trailingMidY: $0.trailingFrameForTesting.midY
            )
        }
    }

    var placeholderLayoutMetricsForTesting: AutocompletePlaceholderMetrics {
        AutocompletePlaceholderMetrics(
            popupMidY: bounds.midY,
            loadingIndicatorMidY: loadingIndicator.frame.midY,
            loadingTextMidY: loadingField.frame.midY,
            emptyTextMidY: emptyField.frame.midY
        )
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
        autocomplete: ComposerAutocompleteState?,
        onSelect: @escaping (ComposerAutocompleteSuggestion) -> Void,
        onHighlight: @escaping (Int) -> Void
    ) {
        self.autocomplete = autocomplete
        self.onSelect = onSelect
        self.onHighlight = onHighlight
        rebuild()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        rowViews.forEach { $0.updateImages() }
        needsDisplay = true
    }

    override func layout() {
        super.layout()
        let contentWidth = max(0, bounds.width - 16)
        let indicatorSize = NSSize(width: 16, height: 16)
        loadingIndicator.frame = centeredFrame(
            leadingX: 20,
            size: indicatorSize
        )
        loadingField.frame = centeredFrame(
            leadingX: loadingIndicator.frame.maxX + 12,
            size: NSSize(width: max(0, contentWidth - 60), height: loadingField.intrinsicContentSize.height)
        )
        emptyField.frame = centeredFrame(
            leadingX: 20,
            size: NSSize(width: max(0, contentWidth - 24), height: emptyField.intrinsicContentSize.height)
        )

        var nextY: CGFloat = 8
        for row in rowViews {
            row.frame = NSRect(x: 8, y: nextY, width: contentWidth, height: 40)
            nextY += 40 + autocompleteListSpacing
        }
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard !isHidden, bounds.contains(point) else {
            return nil
        }
        for row in rowViews.reversed() {
            let rowPoint = row.convert(point, from: self)
            if row.bounds.contains(rowPoint) {
                return row
            }
        }
        return self
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard autocomplete != nil else {
            return
        }

        appKitComposerAutocompleteFillColor(in: self).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: autocompletePopupCornerRadius, yRadius: autocompletePopupCornerRadius)
            .fill()

        appKitComposerSecondaryColor(in: self, opacity: 0.18).setStroke()
        let stroke = NSBezierPath(
            roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5),
            xRadius: autocompletePopupCornerRadius,
            yRadius: autocompletePopupCornerRadius
        )
        stroke.lineWidth = 1
        stroke.stroke()
    }

    static func measuredHeight(for autocomplete: ComposerAutocompleteState?) -> CGFloat {
        guard let autocomplete else {
            return 0
        }
        if autocomplete.isLoading || autocomplete.suggestions.isEmpty {
            return 48
        }
        let visibleRows = min(autocompleteMaxVisibleRows, autocomplete.suggestions.count)
        return CGFloat(visibleRows) * 40 + CGFloat(max(0, visibleRows - 1)) * autocompleteListSpacing + 16
    }

    private func setup() {
        wantsLayer = true
        shadow = NSShadow()
        shadow?.shadowColor = NSColor.black.withAlphaComponent(0.16)
        shadow?.shadowBlurRadius = 18
        shadow?.shadowOffset = NSSize(width: 0, height: -8)

        loadingIndicator.style = .spinning
        loadingIndicator.controlSize = .small
        loadingIndicator.isIndeterminate = true

        [loadingField, emptyField].forEach {
            $0.font = .preferredFont(forTextStyle: .subheadline)
            $0.textColor = .secondaryLabelColor
        }

        [loadingIndicator, loadingField, emptyField].forEach(addSubview)
        loadingIndicator.startAnimation(nil)
    }

    private func centeredFrame(leadingX: CGFloat, size: NSSize) -> NSRect {
        NSRect(
            x: leadingX,
            y: floor((bounds.height - size.height) / 2),
            width: size.width,
            height: size.height
        )
    }

    private func rebuild() {
        rowViews.forEach { $0.removeFromSuperview() }
        rowViews = []

        guard let autocomplete else {
            loadingIndicator.isHidden = true
            loadingField.isHidden = true
            emptyField.isHidden = true
            isHidden = true
            visibleStartIndex = 0
            visibleWindowSessionID = nil
            visibleWindowSuggestionIDs = []
            return
        }

        isHidden = false
        loadingIndicator.isHidden = !autocomplete.isLoading
        loadingField.isHidden = !autocomplete.isLoading
        emptyField.isHidden = autocomplete.isLoading || !autocomplete.suggestions.isEmpty

        if !autocomplete.isLoading {
            rowViews = visibleSuggestionRows(for: autocomplete).map { index, suggestion in
                let row = AppKitComposerAutocompleteRowView()
                row.configure(
                    AutocompleteRowConfiguration(
                        kind: autocomplete.kind,
                        suggestion: suggestion,
                        index: index,
                        query: autocomplete.query,
                        isHighlighted: index == autocomplete.highlightedIndex
                    ),
                    onSelect: { [weak self] in self?.onSelect(suggestion) },
                    onHighlight: { [weak self] index in self?.onHighlight(index) }
                )
                addSubview(row)
                return row
            }
        }

        invalidateIntrinsicContentSize()
        needsLayout = true
        needsDisplay = true
    }

    private func visibleSuggestionRows(for autocomplete: ComposerAutocompleteState) -> ArraySlice<(Int, ComposerAutocompleteSuggestion)> {
        let indexedSuggestions = autocomplete.suggestions.enumerated().map { ($0.offset, $0.element) }
        let suggestionIDs = autocomplete.suggestions.map(\.id)
        if visibleWindowSessionID != autocomplete.sessionID || visibleWindowSuggestionIDs != suggestionIDs {
            visibleStartIndex = 0
            visibleWindowSessionID = autocomplete.sessionID
            visibleWindowSuggestionIDs = suggestionIDs
        }

        guard indexedSuggestions.count > autocompleteMaxVisibleRows else {
            visibleStartIndex = 0
            return indexedSuggestions[...]
        }

        let maximumStartIndex = max(0, indexedSuggestions.count - autocompleteMaxVisibleRows)
        if autocomplete.highlightedIndex < visibleStartIndex {
            visibleStartIndex = autocomplete.highlightedIndex
        } else if autocomplete.highlightedIndex >= visibleStartIndex + autocompleteMaxVisibleRows {
            visibleStartIndex = autocomplete.highlightedIndex - autocompleteMaxVisibleRows + 1
        }
        visibleStartIndex = min(max(0, visibleStartIndex), maximumStartIndex)
        return indexedSuggestions[visibleStartIndex..<(visibleStartIndex + autocompleteMaxVisibleRows)]
    }
}

struct AppKitAutocompletePopupRepresentable: NSViewRepresentable {
    let autocomplete: ComposerAutocompleteState
    let onSelect: (ComposerAutocompleteSuggestion) -> Void
    let onHighlight: (Int) -> Void

    func makeNSView(context: Context) -> AppKitComposerAutocompletePopupView {
        let view = AppKitComposerAutocompletePopupView()
        view.configure(autocomplete: autocomplete, onSelect: onSelect, onHighlight: onHighlight)
        return view
    }

    func updateNSView(_ nsView: AppKitComposerAutocompletePopupView, context: Context) {
        nsView.configure(autocomplete: autocomplete, onSelect: onSelect, onHighlight: onHighlight)
    }
}

@MainActor
private func appKitComposerAutocompleteFillColor(in view: NSView) -> NSColor {
    switch view.appKitRenderingAppearance.bestMatch(from: [.darkAqua, .aqua]) {
    case .darkAqua:
        return NSColor(calibratedRed: 0.16, green: 0.16, blue: 0.17, alpha: 1)
    default:
        return NSColor(calibratedRed: 0.93, green: 0.93, blue: 0.94, alpha: 1)
    }
}
