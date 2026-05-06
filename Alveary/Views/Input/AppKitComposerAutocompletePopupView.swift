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

/// Native autocomplete popup configured by the AppKit composer body and legacy
/// SwiftUI composer host.
///
/// Rendering the popup as AppKit lets the chat surface route hit testing into
/// rows that visually float above the composer panel instead of relying on
/// SwiftUI overlay bounds. The popup exposes pointer and wheel routing for its
/// bounds so the chat surface can keep non-row chrome from forwarding events
/// back into the transcript responder chain.
@MainActor
final class AppKitComposerAutocompletePopupView: NSView {
    private var autocomplete: ComposerAutocompleteState?
    private var rowViews: [AppKitComposerAutocompleteRowView] = []
    private let loadingIndicator = NSProgressIndicator()
    private let loadingField = NSTextField(labelWithString: "Loading suggestions...")
    private let emptyField = NSTextField(labelWithString: "No matches yet")
    private let chromeEventCaptureView = AutocompletePopupChromeEventCaptureView()
    private let scrollbarView = NSView()
    private var scrollbarHideTask: Task<Void, Never>?
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

    override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if routeMouseMoved(at: point, event: event) {
            return
        }
        super.mouseMoved(with: event)
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if routeMouseDown(at: point, event: event) {
            return
        }
        super.mouseDown(with: event)
    }

    override func scrollWheel(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if routeScrollWheel(at: point, event: event) {
            return
        }
        super.scrollWheel(with: event)
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

    var isScrollbarVisibleForTesting: Bool {
        !scrollbarView.isHidden && scrollbarView.alphaValue > 0
    }

    var scrollbarFrameForTesting: NSRect {
        scrollbarView.frame
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
        updateScrollbarColor()
        needsDisplay = true
    }

    override func layout() {
        super.layout()
        let contentWidth = max(0, bounds.width - 16)
        chromeEventCaptureView.frame = bounds
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
        updateScrollbarFrame()
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
        return chromeEventCaptureView
    }

    @discardableResult
    func routeMouseMoved(at point: NSPoint, event: NSEvent) -> Bool {
        guard !isHidden, bounds.contains(point) else {
            return false
        }
        if let row = row(at: point) {
            row.mouseMoved(with: event)
            return true
        }
        return true
    }

    @discardableResult
    func routeMouseDown(at point: NSPoint, event: NSEvent) -> Bool {
        guard !isHidden, bounds.contains(point) else {
            return false
        }
        guard let row = row(at: point) else {
            return true
        }
        row.mouseDown(with: event)
        return true
    }

    @discardableResult
    func routeScrollWheel(at point: NSPoint, event: NSEvent) -> Bool {
        guard !isHidden, bounds.contains(point) else {
            return false
        }
        scrollVisibleSuggestions(deltaY: event.scrollingDeltaY)
        return true
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

    private func row(at point: NSPoint) -> AppKitComposerAutocompleteRowView? {
        rowViews.reversed().first { row in
            let rowPoint = row.convert(point, from: self)
            return row.bounds.contains(rowPoint)
        }
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

        scrollbarView.wantsLayer = true
        scrollbarView.layer?.cornerRadius = 1.5
        scrollbarView.alphaValue = 0
        scrollbarView.isHidden = true
        updateScrollbarColor()

        chromeEventCaptureView.configure(popup: self)

        [chromeEventCaptureView, loadingIndicator, loadingField, emptyField, scrollbarView].forEach(addSubview)
        loadingIndicator.startAnimation(nil)
    }

    private func updateScrollbarColor() {
        scrollbarView.layer?.backgroundColor = NSColor.secondaryLabelColor
            .withAlphaComponent(0.42)
            .appKitResolvedColor(in: self)
            .cgColor
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
            hideScrollbarImmediately()
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
            rowViews = visibleSuggestionRows(for: autocomplete, anchorHighlightedSuggestion: true).map { index, suggestion in
                makeRow(autocomplete: autocomplete, index: index, suggestion: suggestion)
            }
        }

        invalidateIntrinsicContentSize()
        needsLayout = true
        needsDisplay = true
    }

    private func scrollVisibleSuggestions(deltaY: CGFloat) {
        guard let autocomplete,
              autocomplete.suggestions.count > autocompleteMaxVisibleRows,
              deltaY != 0 else {
            return
        }

        let maximumStartIndex = max(0, autocomplete.suggestions.count - autocompleteMaxVisibleRows)
        let direction = deltaY < 0 ? 1 : -1
        let nextStartIndex = min(max(0, visibleStartIndex + direction), maximumStartIndex)
        showScrollbarIfNeeded()
        guard nextStartIndex != visibleStartIndex else {
            return
        }

        visibleStartIndex = nextStartIndex
        rowViews.forEach { $0.removeFromSuperview() }
        rowViews = visibleSuggestionRows(for: autocomplete, anchorHighlightedSuggestion: false).map { index, suggestion in
            makeRow(autocomplete: autocomplete, index: index, suggestion: suggestion)
        }
        updateScrollbarFrame()
        needsLayout = true
        needsDisplay = true
    }

    private func showScrollbarIfNeeded() {
        guard let autocomplete,
              autocomplete.suggestions.count > autocompleteMaxVisibleRows else {
            hideScrollbarImmediately()
            return
        }
        updateScrollbarFrame()
        scrollbarView.isHidden = false
        scrollbarView.alphaValue = 1
        scrollbarHideTask?.cancel()
        scrollbarHideTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 900_000_000)
            guard !Task.isCancelled else {
                return
            }
            await MainActor.run {
                self?.scrollbarView.alphaValue = 0
            }
        }
    }

    private func hideScrollbarImmediately() {
        scrollbarHideTask?.cancel()
        scrollbarHideTask = nil
        scrollbarView.alphaValue = 0
        scrollbarView.isHidden = true
    }

    private func updateScrollbarFrame() {
        guard let autocomplete,
              autocomplete.suggestions.count > autocompleteMaxVisibleRows,
              bounds.height > 0 else {
            scrollbarView.frame = .zero
            return
        }

        let totalRows = CGFloat(autocomplete.suggestions.count)
        let visibleRows = CGFloat(autocompleteMaxVisibleRows)
        let trackInset: CGFloat = 8
        let trackHeight = max(0, bounds.height - trackInset * 2)
        let thumbHeight = max(28, floor(trackHeight * min(1, visibleRows / totalRows)))
        let maximumStartIndex = max(1, autocomplete.suggestions.count - autocompleteMaxVisibleRows)
        let progress = CGFloat(visibleStartIndex) / CGFloat(maximumStartIndex)
        let thumbY = trackInset + floor((trackHeight - thumbHeight) * progress)
        scrollbarView.frame = NSRect(x: bounds.width - 7, y: thumbY, width: 3, height: thumbHeight)
    }

    private func makeRow(
        autocomplete: ComposerAutocompleteState,
        index: Int,
        suggestion: ComposerAutocompleteSuggestion
    ) -> AppKitComposerAutocompleteRowView {
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
        addSubview(row, positioned: .below, relativeTo: scrollbarView)
        return row
    }

    private func visibleSuggestionRows(
        for autocomplete: ComposerAutocompleteState,
        anchorHighlightedSuggestion: Bool
    ) -> ArraySlice<(Int, ComposerAutocompleteSuggestion)> {
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
        if anchorHighlightedSuggestion {
            if autocomplete.highlightedIndex < visibleStartIndex {
                visibleStartIndex = autocomplete.highlightedIndex
            } else if autocomplete.highlightedIndex >= visibleStartIndex + autocompleteMaxVisibleRows {
                visibleStartIndex = autocomplete.highlightedIndex - autocompleteMaxVisibleRows + 1
            }
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
