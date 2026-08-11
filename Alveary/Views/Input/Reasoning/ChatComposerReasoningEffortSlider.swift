import AppKit
enum ComposerReasoningEffortSliderMetrics {
    static let controlHeight: CGFloat = 33
    static let trackHeight: CGFloat = 21
    static let thumbDiameter: CGFloat = 25.5
    static let dotDiameter: CGFloat = 5.25
    static let dotAlpha: CGFloat = 0.72
    static let endpointCenterInset: CGFloat = thumbDiameter / 2
    static let dragDirectionRevealDistance: CGFloat = 3
    static let dragDirectionRevealDelay: TimeInterval = 0.15
}
@MainActor
final class ComposerReasoningEffortSlider: NSSlider {
    typealias IndexHandler = (Int) -> Void

    private enum CanonicalSelection: Equatable {
        case option(Int)
        case unmatched(fallbackIndex: Int)

        var visualIndex: Int {
            switch self {
            case .option(let index), .unmatched(let index):
                index
            }
        }

        var isRepresented: Bool {
            if case .option = self {
                return true
            }
            return false
        }
    }

    private(set) var effortTitles: [String] = []
    private(set) var displayedIndex = 0
    private var canonicalSelection = CanonicalSelection.unmatched(fallbackIndex: 0)
    private var configurationIsEnabled = true
    private var interactionStartSelection: CanonicalSelection?
    private var lastPreviewedIndex: Int?
    private var onPreview: IndexHandler?
    private var onCommit: IndexHandler?
    private var onCancel: (() -> Void)?
    private var onDragDirectionVisibilityChanged: ((Bool) -> Void)?
    private var trackingStartPoint: NSPoint?
    private var dragDirectionRevealTimer: Timer?
    private var dragDirectionsAreVisible = false
    private(set) var isPressed = false
    var canonicalIndex: Int { canonicalSelection.visualIndex }
    var isTrackingInteraction: Bool { interactionStartSelection != nil }
    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: ComposerReasoningEffortSliderMetrics.controlHeight)
    }
    override var acceptsFirstResponder: Bool {
        isInteractive
    }
    override var focusRingType: NSFocusRingType {
        get { .none }
        set {}
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    // swiftlint:disable:next function_parameter_count
    func configure(
        effortTitles: [String],
        selectedIndex: Int?,
        fallbackIndex: Int = 0,
        isEnabled: Bool,
        onPreview: @escaping IndexHandler,
        onCommit: @escaping IndexHandler,
        onCancel: @escaping () -> Void,
        onDragDirectionVisibilityChanged: @escaping (Bool) -> Void = { _ in }
    ) {
        let normalizedFallbackIndex = Self.normalizedIndex(fallbackIndex, count: effortTitles.count)
        let nextCanonicalSelection = selectedIndex.map {
            CanonicalSelection.option(Self.normalizedIndex($0, count: effortTitles.count))
        } ?? .unmatched(fallbackIndex: normalizedFallbackIndex)
        let optionsChanged = effortTitles != self.effortTitles
        let canonicalChanged = nextCanonicalSelection != canonicalSelection
        let availabilityChanged = isEnabled != configurationIsEnabled
        let preservesActivePreview = !optionsChanged && !canonicalChanged && !availabilityChanged

        if !preservesActivePreview {
            cancelInteraction(notify: false)
        }
        self.effortTitles = effortTitles
        canonicalSelection = nextCanonicalSelection
        configurationIsEnabled = isEnabled
        self.onPreview = onPreview
        self.onCommit = onCommit
        self.onCancel = onCancel
        self.onDragDirectionVisibilityChanged = onDragDirectionVisibilityChanged
        minValue = 0
        maxValue = Double(max(0, effortTitles.count - 1))
        altIncrementValue = 1
        numberOfTickMarks = effortTitles.count
        allowsTickMarkValuesOnly = true
        isContinuous = true
        isHidden = effortTitles.isEmpty
        setAccessibilityElement(!effortTitles.isEmpty)
        refreshAvailability()
        if !preservesActivePreview || interactionStartSelection == nil {
            setDisplayedIndex(nextCanonicalSelection.visualIndex)
        } else {
            doubleValue = Double(displayedIndex)
            refreshAccessibilityValue()
        }
        needsDisplay = true
    }

    /// Restores the configured value without persisting it. Controllers use this when
    /// the popover closes or an authoritative configuration supersedes a live preview.
    func cancelInteraction(notify: Bool = true) {
        let hadInteraction = interactionStartSelection != nil || displayedIndex != canonicalIndex
        interactionStartSelection = nil
        lastPreviewedIndex = nil
        resetDragDirectionPresentation()
        setDisplayedIndex(canonicalIndex)
        isPressed = false
        needsDisplay = true
        if notify, hadInteraction {
            onCancel?()
        }
    }

    /// Begins the transaction used by native mouse tracking. Kept internal so tests can
    /// exercise drag semantics without presenting a window or synthesizing an event loop.
    func beginTrackingInteraction(
        at startPoint: NSPoint? = nil,
        schedulesDragDirectionReveal: Bool = false
    ) {
        guard isInteractive, interactionStartSelection == nil else {
            return
        }
        interactionStartSelection = canonicalSelection
        lastPreviewedIndex = canonicalSelection.isRepresented ? displayedIndex : nil
        trackingStartPoint = startPoint
        dragDirectionsAreVisible = false
        isPressed = true
        needsDisplay = true
        if schedulesDragDirectionReveal {
            scheduleDragDirectionReveal()
        }
    }

    func updateTrackingInteraction(to index: Int, trackingPoint: NSPoint? = nil) {
        guard interactionStartSelection != nil, isInteractive else {
            return
        }
        if let trackingPoint {
            updateDragDirectionPresentation(for: trackingPoint)
        }
        setDisplayedIndex(index)
        guard lastPreviewedIndex != displayedIndex else {
            return
        }
        lastPreviewedIndex = displayedIndex
        onPreview?(displayedIndex)
    }

    /// Ends a drag and returns whether it produced a commit.
    @discardableResult
    func endTrackingInteraction(commit: Bool) -> Bool {
        guard let startSelection = interactionStartSelection else {
            return false
        }
        let selectedAnOption = lastPreviewedIndex != nil
        interactionStartSelection = nil
        lastPreviewedIndex = nil
        resetDragDirectionPresentation()
        isPressed = false
        needsDisplay = true
        guard commit else {
            setDisplayedIndex(startSelection.visualIndex)
            onCancel?()
            return false
        }
        guard selectedAnOption, startSelection != .option(displayedIndex) else {
            return false
        }
        let visualValueChanged = startSelection.visualIndex != displayedIndex
        canonicalSelection = .option(displayedIndex)
        refreshAvailability()
        if !visualValueChanged {
            NSAccessibility.post(element: self, notification: .valueChanged)
        }
        onCommit?(displayedIndex)
        return true
    }

    /// Performs one preview-and-commit transaction for keyboard and accessibility input.
    @discardableResult
    func performDiscreteStep(by delta: Int) -> Bool {
        guard isInteractive else {
            return false
        }
        let destination = normalizedIndex(displayedIndex + delta)
        guard canonicalSelection != .option(destination) else {
            return false
        }
        if interactionStartSelection != nil {
            cancelInteraction(notify: false)
        }
        let visualValueChanged = destination != displayedIndex
        setDisplayedIndex(destination)
        canonicalSelection = .option(destination)
        refreshAvailability()
        if !visualValueChanged {
            NSAccessibility.post(element: self, notification: .valueChanged)
        }
        onPreview?(destination)
        onCommit?(destination)
        return true
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }
    override func becomeFirstResponder() -> Bool {
        guard isInteractive else {
            return false
        }
        needsDisplay = true
        return true
    }

    override func resignFirstResponder() -> Bool {
        needsDisplay = true
        return true
    }
    override func mouseDown(with event: NSEvent) {
        guard isInteractive else {
            return
        }
        window?.makeFirstResponder(self)
        beginTrackingInteraction(
            at: convert(event.locationInWindow, from: nil),
            schedulesDragDirectionReveal: true
        )
        super.mouseDown(with: event)
        if interactionStartSelection != nil {
            endTrackingInteraction(commit: true)
        }
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 123:
            performDiscreteStep(by: -1)
        case 124:
            performDiscreteStep(by: 1)
        case 53:
            let hadInteraction = interactionStartSelection != nil || displayedIndex != canonicalIndex
            cancelInteraction(notify: false)
            if hadInteraction || !effortTitles.isEmpty {
                onCancel?()
            }
        default:
            super.keyDown(with: event)
        }
    }

    override func accessibilityPerformIncrement() -> Bool {
        performDiscreteStep(by: 1)
    }

    override func accessibilityPerformDecrement() -> Bool {
        performDiscreteStep(by: -1)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }
    #if DEBUG
    var debugTrackRect: NSRect { effortCell.barRect(flipped: isFlipped) }
    var debugKnobRect: NSRect { effortCell.knobRect(flipped: isFlipped) }
    var debugTickCenters: [NSPoint] { (0 ..< effortTitles.count).map(tickCenter(at:)) }
    var debugSelectedIndex: Int { displayedIndex }
    var debugTrackingStartIndex: Int? { interactionStartSelection?.visualIndex }
    var debugIsTracking: Bool { interactionStartSelection != nil }
    var debugCanonicalValueIsRepresented: Bool { canonicalSelection.isRepresented }
    var debugDotDiameter: CGFloat { ComposerReasoningEffortSliderMetrics.dotDiameter }
    var debugAccessibilityValueDescription: String? {
        effortTitles.indices.contains(displayedIndex) ? effortTitles[displayedIndex] : nil
    }
    var debugAccessibilityHelp: String { "Adjust reasoning effort" }
    var debugHasPendingDragDirectionReveal: Bool { dragDirectionRevealTimer != nil }
    var debugShowsDragDirections: Bool { dragDirectionsAreVisible }
    var debugResolvedColors: ComposerReasoningEffortSliderCell.ResolvedColors {
        effortCell.resolvedColors(for: self)
    }
    func fireDragDirectionRevealDelayForTesting() {
        guard dragDirectionRevealTimer != nil else {
            return
        }
        dragDirectionRevealTimer?.invalidate()
        dragDirectionRevealTimer = nil
        revealDragDirectionsIfTracking()
    }
    #endif
    func index(at point: NSPoint) -> Int {
        guard effortTitles.count > 1 else {
            return 0
        }
        let firstCenterX = bounds.minX + ComposerReasoningEffortSliderMetrics.endpointCenterInset
        let lastCenterX = bounds.maxX - ComposerReasoningEffortSliderMetrics.endpointCenterInset
        let progress = (point.x - firstCenterX) / max(1, lastCenterX - firstCenterX)
        return normalizedIndex(Int((progress * CGFloat(effortTitles.count - 1)).rounded()))
    }

    func tickCenter(at index: Int) -> NSPoint {
        let centerY = bounds.midY
        guard effortTitles.count > 1 else {
            return NSPoint(x: bounds.midX, y: centerY)
        }
        let firstCenterX = bounds.minX + ComposerReasoningEffortSliderMetrics.endpointCenterInset
        let lastCenterX = bounds.maxX - ComposerReasoningEffortSliderMetrics.endpointCenterInset
        let progress = CGFloat(normalizedIndex(index)) / CGFloat(effortTitles.count - 1)
        return NSPoint(x: firstCenterX + (lastCenterX - firstCenterX) * progress, y: centerY)
    }

    private var effortCell: ComposerReasoningEffortSliderCell {
        guard let effortCell = cell as? ComposerReasoningEffortSliderCell else {
            preconditionFailure("ComposerReasoningEffortSlider requires its custom cell")
        }
        return effortCell
    }
    private var isInteractive: Bool {
        configurationIsEnabled && effortTitles.count > 1
    }

    private var displayAlpha: CGFloat {
        guard configurationIsEnabled else {
            return 0.55
        }
        return effortTitles.count == 1 && !isInteractive ? 0.72 : 1
    }
    private func refreshAvailability() {
        super.isEnabled = isInteractive
        alphaValue = displayAlpha
        setAccessibilityEnabled(isInteractive)
        if !isInteractive, window?.firstResponder === self {
            window?.makeFirstResponder(nil)
        }
    }
    private func scheduleDragDirectionReveal() {
        dragDirectionRevealTimer?.invalidate()
        let timer = Timer(
            timeInterval: ComposerReasoningEffortSliderMetrics.dragDirectionRevealDelay,
            repeats: false
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.dragDirectionRevealTimer = nil
                self?.revealDragDirectionsIfTracking()
            }
        }
        dragDirectionRevealTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }
    private func updateDragDirectionPresentation(for point: NSPoint) {
        guard let trackingStartPoint else {
            self.trackingStartPoint = point
            return
        }
        let distance = hypot(point.x - trackingStartPoint.x, point.y - trackingStartPoint.y)
        guard distance >= ComposerReasoningEffortSliderMetrics.dragDirectionRevealDistance else {
            return
        }
        revealDragDirectionsIfTracking()
    }
    private func revealDragDirectionsIfTracking() {
        guard interactionStartSelection != nil, !dragDirectionsAreVisible else {
            return
        }
        dragDirectionRevealTimer?.invalidate()
        dragDirectionRevealTimer = nil
        dragDirectionsAreVisible = true
        onDragDirectionVisibilityChanged?(true)
    }
    private func resetDragDirectionPresentation() {
        dragDirectionRevealTimer?.invalidate()
        dragDirectionRevealTimer = nil
        trackingStartPoint = nil
        guard dragDirectionsAreVisible else {
            return
        }
        dragDirectionsAreVisible = false
        onDragDirectionVisibilityChanged?(false)
    }
    private func setup() {
        cell = ComposerReasoningEffortSliderCell()
        sliderType = .linear
        isVertical = false
        isContinuous = true
        focusRingType = .none
        setAccessibilityElement(true)
        setAccessibilityRole(.slider)
        setAccessibilityLabel("Reasoning effort")
        setAccessibilityHelp("Adjust reasoning effort")
        setContentCompressionResistancePriority(.required, for: .vertical)
        setContentHuggingPriority(.required, for: .vertical)
    }

    private func normalizedIndex(_ index: Int) -> Int {
        Self.normalizedIndex(index, count: effortTitles.count)
    }
    private static func normalizedIndex(_ index: Int, count: Int) -> Int {
        guard count > 0 else {
            return 0
        }
        return min(max(0, index), count - 1)
    }

    private func setDisplayedIndex(_ index: Int) {
        let normalizedIndex = normalizedIndex(index)
        let changed = normalizedIndex != displayedIndex
        displayedIndex = normalizedIndex
        doubleValue = Double(normalizedIndex)
        refreshAccessibilityValue()
        needsDisplay = true
        guard changed else {
            return
        }
        NSAccessibility.post(element: self, notification: .valueChanged)
    }

    private func refreshAccessibilityValue() {
        let valueDescription = effortTitles.indices.contains(displayedIndex)
            ? effortTitles[displayedIndex]
            : nil
        setAccessibilityValueDescription(valueDescription)
    }
}
