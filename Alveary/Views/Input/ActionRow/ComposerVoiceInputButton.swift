@preconcurrency import AppKit

@MainActor
struct ComposerVoiceInputConfiguration {
    let phase: ChatVoiceInputPhase
    let isEnabled: Bool
    let shortcutDisplay: String?
    let unavailableHelp: String?
    var canActivate: () -> Bool = { true }
    var reducesMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    var increasesContrast = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
    let onPress: () -> Bool
    let onRelease: (Bool) -> Bool
    let onAccessibilityToggle: () -> Void
    let onAccessibilityCancel: () -> Bool
}

/// Dedicated 30×30 press-and-hold microphone control. It owns mouse tracking;
/// recognition and latch semantics remain in `ChatVoiceInputCoordinator`.
@MainActor
final class ComposerVoiceInputButton: NSButton {
    private let progressIndicator = NSProgressIndicator()
    private var configuration: ComposerVoiceInputConfiguration?
    private var mouseEventMonitor: Any?
    private var mouseFocusRestoreTarget: NSResponder?
    private var isTrackingMousePress = false
    private var isHovering = false
    private var symbolName = "mic"
    private var trackingArea: NSTrackingArea?
    private var accessibilityDisplayOptionsObserver: NSObjectProtocol?
    #if DEBUG
    private var mouseEventMonitorRemovalObserver: (() -> Void)?
    private var debugFocusAppearanceOverride = false
    #endif
    private var accessibilityDisplayOptionsProvider: () -> (reducesMotion: Bool, increasesContrast: Bool) = {
        (
            NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
            NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
        )
    }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { isEnabled || isTrackingMousePress }
    override var focusRingType: NSFocusRingType {
        get { .none }
        set {}
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: 30, height: 30)
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    isolated deinit {
        removeMouseEventMonitor()
        if let accessibilityDisplayOptionsObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(accessibilityDisplayOptionsObserver)
        }
    }

    func configure(_ configuration: ComposerVoiceInputConfiguration) {
        self.configuration = configuration
        isEnabled = configuration.isEnabled
        setAccessibilityEnabled(configuration.isEnabled || configuration.phase == .finalizing)
        let shortcutSuffix = configuration.shortcutDisplay.map { " (\($0))" } ?? ""
        toolTip = configuration.unavailableHelp ?? "Dictate a message\(shortcutSuffix)"
        let accessibilityShortcut = configuration.shortcutDisplay.map { ", shortcut \($0)" } ?? ""
        setAccessibilityLabel(accessibilityLabel(for: configuration.phase) + accessibilityShortcut)
        setAccessibilityHelp(toolTip)
        switch configuration.phase {
        case .recording, .finalizing:
            setAccessibilityCustomActions([
                NSAccessibilityCustomAction(name: "Cancel Dictation") { [weak self] in
                    self?.configuration?.onAccessibilityCancel() ?? false
                }
            ])
        case .unavailable, .idle, .preparing, .ready, .starting, .cancelling, .cleanup:
            setAccessibilityCustomActions([])
        }
        applyVisualState(configuration.phase)
        if !configuration.isEnabled, !isTrackingMousePress {
            restoreMouseFocusIfNeeded()
        }
    }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled, configuration?.canActivate() == true else { return }
        claimTemporaryMouseFocus()
        beginMouseTracking()
        guard configuration?.onPress() == true else {
            abandonMouseTracking()
            return
        }
    }

    override func mouseEntered(with event: NSEvent) {
        guard isEnabled else { return }
        isHovering = true
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovering = false
        if isTrackingMousePress {
            finishMouseTracking(forced: true)
            return
        }
        needsDisplay = true
    }

    override func keyDown(with event: NSEvent) {
        guard isEnabled, configuration?.canActivate() == true else { return }
        switch event.keyCode {
        case 36, 49:
            guard !event.isARepeat,
                  PhysicalKeyboardShortcutModifiers(event.modifierFlags).isEmpty else {
                super.keyDown(with: event)
                return
            }
            configuration?.onAccessibilityToggle()
        default:
            super.keyDown(with: event)
        }
    }

    override func becomeFirstResponder() -> Bool {
        needsDisplay = true
        return true
    }

    override func resignFirstResponder() -> Bool {
        needsDisplay = true
        return true
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self
        )
        trackingArea = area
        addTrackingArea(area)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil {
            forceMouseRelease()
        }
        super.viewWillMove(toWindow: newWindow)
    }

    func forceMouseRelease() {
        finishMouseTracking(forced: true)
    }

    private func beginMouseTracking() {
        guard !isTrackingMousePress else { return }
        isTrackingMousePress = true
        isHighlighted = true
        mouseEventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseUp, .leftMouseDragged]) { [weak self] event in
            guard let self else { return event }
            switch event.type {
            case .leftMouseDragged:
                guard event.window === self.window else {
                    self.finishMouseTracking(forced: true)
                    return nil
                }
                let point = self.convert(event.locationInWindow, from: nil)
                if !self.bounds.insetBy(dx: -2, dy: -2).contains(point) {
                    self.finishMouseTracking(forced: true)
                }
                return nil
            case .leftMouseUp:
                self.finishMouseTracking(forced: false)
                return nil
            default:
                return event
            }
        }
    }

    private func finishMouseTracking(forced: Bool) {
        guard isTrackingMousePress else { return }
        clearMouseTrackingState()
        _ = configuration?.onRelease(forced)
        restoreMouseFocusIfNeeded()
    }

    private func abandonMouseTracking() {
        clearMouseTrackingState()
        restoreMouseFocusIfNeeded()
    }

    private func clearMouseTrackingState() {
        isTrackingMousePress = false
        isHighlighted = false
        removeMouseEventMonitor()
        needsDisplay = true
    }

    private func removeMouseEventMonitor() {
        if let mouseEventMonitor {
            NSEvent.removeMonitor(mouseEventMonitor)
            self.mouseEventMonitor = nil
            #if DEBUG
            mouseEventMonitorRemovalObserver?()
            #endif
        }
    }

    override func accessibilityPerformPress() -> Bool {
        guard isEnabled, configuration?.canActivate() == true else {
            return false
        }
        configuration?.onAccessibilityToggle()
        return true
    }

    override func layout() {
        super.layout()
        progressIndicator.frame = NSRect(
            x: floor((bounds.width - 16) / 2),
            y: floor((bounds.height - 16) / 2),
            width: 16,
            height: 16
        )
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let circleRect = NSRect(
            x: floor((bounds.width - min(bounds.width, bounds.height)) / 2),
            y: floor((bounds.height - min(bounds.width, bounds.height)) / 2),
            width: min(bounds.width, bounds.height),
            height: min(bounds.width, bounds.height)
        )
        let circlePath = NSBezierPath(ovalIn: circleRect)
        backgroundColor.setFill()
        circlePath.fill()
        drawFocusAndContrastBorder(circlePath)
        guard progressIndicator.isHidden, let image = symbolImage else { return }
        image.draw(
            in: centeredSymbolRect(for: image),
            from: .zero,
            operation: .sourceOver,
            fraction: 1,
            respectFlipped: true,
            hints: nil
        )
    }

    private func setup() {
        translatesAutoresizingMaskIntoConstraints = false
        isBordered = false
        title = ""
        setButtonType(.momentaryChange)

        progressIndicator.style = .spinning
        progressIndicator.controlSize = .small
        progressIndicator.isDisplayedWhenStopped = false
        progressIndicator.isHidden = true
        progressIndicator.setAccessibilityElement(false)
        addSubview(progressIndicator)

        accessibilityDisplayOptionsObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.refreshAccessibilityDisplayOptions()
            }
        }
    }

    private func refreshAccessibilityDisplayOptions() {
        guard var configuration else { return }
        let options = accessibilityDisplayOptionsProvider()
        configuration.reducesMotion = options.reducesMotion
        configuration.increasesContrast = options.increasesContrast
        self.configuration = configuration
        applyVisualState(configuration.phase)
    }

    private func applyVisualState(_ phase: ChatVoiceInputPhase) {
        if phase.showsSpinner, configuration?.reducesMotion == false {
            progressIndicator.isHidden = false
            progressIndicator.startAnimation(nil)
        } else {
            progressIndicator.stopAnimation(nil)
            progressIndicator.isHidden = true
            switch phase {
            case .recording:
                symbolName = "mic.fill"
            case .preparing, .starting, .finalizing, .cancelling, .cleanup:
                symbolName = "hourglass"
            case .unavailable, .idle, .ready:
                symbolName = "mic"
            }
        }
        needsDisplay = true
    }

    private func claimTemporaryMouseFocus() {
        mouseFocusRestoreTarget = window?.firstResponder === self ? nil : window?.firstResponder
        window?.makeFirstResponder(self)
    }

    private func restoreMouseFocusIfNeeded() {
        defer { mouseFocusRestoreTarget = nil }
        guard let window else { return }
        let currentResponder = window.firstResponder
        guard currentResponder === self || currentResponder === window else { return }
        if let target = mouseFocusRestoreTarget,
           window.makeFirstResponder(target) {
            return
        }
        window.makeFirstResponder(nil)
    }

    private var phase: ChatVoiceInputPhase {
        configuration?.phase ?? .unavailable
    }

    private var backgroundColor: NSColor {
        if phase == .recording {
            return NSColor.systemRed.appKitResolvedColor(in: self, alpha: isHighlighted ? 0.84 : 1)
        }
        let alpha: CGFloat
        if isHighlighted {
            alpha = 0.18
        } else if isHovering || showsFocusAppearance {
            alpha = 0.13
        } else {
            alpha = 0
        }
        return NSColor.labelColor.appKitResolvedColor(in: self, alpha: interactionIsEnabled ? alpha : 0)
    }

    private var foregroundColor: NSColor {
        if phase == .recording {
            return .white
        }
        return interactionIsEnabled ? .labelColor : .disabledControlTextColor
    }

    private var interactionIsEnabled: Bool {
        isEnabled || isTrackingMousePress
    }

    private var showsFocusAppearance: Bool {
        #if DEBUG
        if debugFocusAppearanceOverride {
            return true
        }
        #endif
        return window?.firstResponder === self
    }

    private var symbolImage: NSImage? {
        let symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 15, weight: .regular)
            .applying(.init(hierarchicalColor: foregroundColor.appKitResolvedColor(in: self)))
        return NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?
            .withSymbolConfiguration(symbolConfiguration)
    }

    private func centeredSymbolRect(for image: NSImage) -> NSRect {
        NSRect(
            x: (bounds.width - image.size.width) / 2,
            y: (bounds.height - image.size.height) / 2,
            width: image.size.width,
            height: image.size.height
        )
    }

    private func drawFocusAndContrastBorder(_ circlePath: NSBezierPath) {
        if showsFocusAppearance, interactionIsEnabled {
            AppAccentFill.primaryNSColor.appKitResolvedColor(in: self, alpha: 0.22).setStroke()
            circlePath.lineWidth = 1.5
            circlePath.stroke()
        } else if configuration?.increasesContrast == true {
            foregroundColor.appKitResolvedColor(in: self, alpha: 0.9).setStroke()
            circlePath.lineWidth = 1
            circlePath.stroke()
        }
    }

    #if DEBUG
    var debugSymbolRect: NSRect? {
        symbolImage.map(centeredSymbolRect(for:))
    }

    var debugBackgroundAlpha: CGFloat {
        backgroundColor.alphaComponent
    }

    var debugMouseFocusRestoreTarget: NSResponder? {
        mouseFocusRestoreTarget
    }

    var debugShowsSpinner: Bool {
        !progressIndicator.isHidden
    }

    var debugSpinnerIsAccessibilityElement: Bool {
        progressIndicator.isAccessibilityElement()
    }

    var debugIncreasesContrast: Bool {
        configuration?.increasesContrast == true
    }

    func debugSetAccessibilityDisplayOptionsProvider(
        _ provider: @escaping () -> (reducesMotion: Bool, increasesContrast: Bool)
    ) {
        accessibilityDisplayOptionsProvider = provider
    }

    func debugObserveMouseEventMonitorRemoval(_ observer: @escaping () -> Void) {
        mouseEventMonitorRemovalObserver = observer
    }

    func debugSetFocusAppearance(_ isFocused: Bool) {
        debugFocusAppearanceOverride = isFocused
        needsDisplay = true
    }
    #endif

    private func accessibilityLabel(for phase: ChatVoiceInputPhase) -> String {
        switch phase {
        case .recording:
            "Stop Dictation"
        case .preparing:
            "Preparing Voice Input"
        case .starting:
            "Starting Dictation"
        case .finalizing:
            "Finalizing Dictation"
        case .cancelling:
            "Cancelling Dictation"
        case .cleanup:
            "Cleaning Up Voice Input"
        case .unavailable, .idle, .ready:
            "Start Dictation"
        }
    }
}
