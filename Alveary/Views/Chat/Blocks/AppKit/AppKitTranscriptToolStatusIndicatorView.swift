@preconcurrency import AppKit
import Foundation
import QuartzCore

private let appKitToolGroupStatusIndicatorDebounce: Duration = .milliseconds(250)
private let appKitToolDisclosureSymbolName = "chevron.right"
private let appKitToolDisclosureAnimationDuration: CFTimeInterval = 0.16
private let appKitToolDisclosureFadeOutDuration: CFTimeInterval = 0.10
private let appKitToolDisclosureExpandedRotation = -CGFloat.pi / 2

@MainActor
final class AppKitTranscriptToolStatusIndicatorView: NSView {
    private let symbolView = AppKitDynamicTintImageView()
    private var phase: ToolStatusPhase?
    private var displayedPhase: ToolStatusPhase?
    private var symbolSystemName: String?
    private var disclosureExpansionState: Bool?
    private var isDisclosureHovered = false
    private var symbolRotation: CGFloat = 0
    private var typography = TranscriptTypography()
    private var pendingTask: Task<Void, Never>?
    private var pendingPhaseVersion = 0

    var onPress: (() -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    deinit {
        pendingTask?.cancel()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(
        phase: ToolStatusPhase,
        debounceTerminal: Bool = false,
        typography: TranscriptTypography = TranscriptTypography(),
        disclosureExpansionState: Bool? = nil,
        disclosureHovered: Bool = false,
        animateDisclosureChange: Bool = true
    ) {
        let typographyChanged = self.typography != typography
        let normalizedDisclosureHovered = disclosureExpansionState != nil && disclosureHovered
        let disclosureChanged = self.disclosureExpansionState != disclosureExpansionState ||
            self.isDisclosureHovered != normalizedDisclosureHovered
        self.typography = typography
        self.disclosureExpansionState = disclosureExpansionState
        self.isDisclosureHovered = normalizedDisclosureHovered
        updateSymbolConfiguration()

        guard self.phase != phase else {
            if typographyChanged || disclosureChanged {
                renderCurrentState(animated: animateDisclosureChange && disclosureChanged)
                needsLayout = true
            }
            return
        }
        self.phase = phase
        pendingTask?.cancel()
        pendingTask = nil
        pendingPhaseVersion &+= 1
        guard displayedPhase != nil, debounceTerminal, phase.isTerminal else {
            apply(phase: phase)
            return
        }

        let phaseVersion = pendingPhaseVersion
        pendingTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: appKitToolGroupStatusIndicatorDebounce)
            } catch {
                return
            }

            guard let self, phaseVersion == self.pendingPhaseVersion else {
                return
            }
            self.apply(phase: phase)
            self.pendingTask = nil
        }
    }

    override func mouseDown(with event: NSEvent) {
        guard disclosureExpansionState != nil, let onPress else {
            super.mouseDown(with: event)
            return
        }
        onPress()
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let hitView = super.hitTest(point), disclosureExpansionState != nil else {
            return super.hitTest(point)
        }
        return hitView == self || hitView.isDescendant(of: self) ? self : hitView
    }

    override func layout() {
        super.layout()
        symbolView.frame = bounds
        positionSymbolLayer(rotation: symbolRotation)
    }

    private func setup() {
        translatesAutoresizingMaskIntoConstraints = false
        symbolView.wantsLayer = true
        symbolView.translatesAutoresizingMaskIntoConstraints = true
        symbolView.imageAlignment = .alignCenter
        symbolView.imageScaling = .scaleProportionallyDown
        updateSymbolConfiguration()
        addSubview(symbolView)
    }

    private func apply(phase: ToolStatusPhase) {
        displayedPhase = phase
        renderCurrentState(animated: false)
    }

    private func renderCurrentState(animated: Bool) {
        guard displayedPhase != nil else {
            showNoSymbol(animated: false)
            return
        }

        if let isExpanded = disclosureExpansionState, isExpanded || isDisclosureHovered {
            showSymbol(
                systemName: appKitToolDisclosureSymbolName,
                rotation: disclosureRotation(isExpanded: isExpanded),
                animated: animated,
                accessibilityDescription: isExpanded ? "Collapse" : "Expand"
            )
            return
        }

        showNoSymbol(animated: animated && disclosureExpansionState == false && !isDisclosureHovered)
    }

    private func showNoSymbol(animated: Bool) {
        let previousSymbolName = symbolSystemName
        symbolSystemName = nil
        symbolRotation = 0
        symbolView.setAccessibilityLabel(nil)
        positionSymbolLayer(rotation: 0)
        guard !symbolView.isHidden else {
            symbolView.alphaValue = 0
            return
        }
        symbolView.alphaValue = 0
        if animated, isDisclosureSymbol(previousSymbolName) {
            addSymbolFadeOutTransitionIfNeeded()
        } else {
            symbolView.isHidden = true
        }
    }

    private func showSymbol(
        systemName: String,
        rotation: CGFloat,
        animated: Bool,
        accessibilityDescription: String? = nil
    ) {
        let previousSymbolName = symbolSystemName
        let previousRotation = symbolRotation
        let symbolChanged = symbolSystemName != systemName
        let rotationChanged = abs(symbolRotation - rotation) > 0.001
        symbolView.isHidden = false
        symbolView.alphaValue = 1
        symbolView.setAccessibilityLabel(accessibilityDescription)
        if symbolChanged {
            symbolView.image = NSImage(systemSymbolName: systemName, accessibilityDescription: accessibilityDescription)
            symbolSystemName = systemName
        }
        symbolView.setDynamicContentTintColorPreservingAlpha(transcriptInlineToolRowForegroundColor(isHovered: isDisclosureHovered))
        symbolRotation = rotation
        positionSymbolLayer(rotation: rotation)
        addSymbolTransitionIfNeeded(
            .init(
                previousSymbolName: previousSymbolName,
                nextSymbolName: systemName,
                previousRotation: previousRotation,
                nextRotation: rotation,
                symbolChanged: symbolChanged,
                rotationChanged: rotationChanged
            ),
            animated: animated
        )
    }

    private func addSymbolTransitionIfNeeded(_ transition: SymbolTransition, animated: Bool) {
        guard animated,
              !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
              let layer = symbolView.layer else {
            return
        }
        if isDisclosureSymbol(transition.previousSymbolName),
           isDisclosureSymbol(transition.nextSymbolName),
           transition.rotationChanged {
            addSymbolRotationTransition(to: layer, from: transition.previousRotation, to: transition.nextRotation)
        } else if transition.symbolChanged {
            addSymbolFadeTransition(to: layer)
        }
    }

    private func addSymbolRotationTransition(to layer: CALayer, from previousRotation: CGFloat, to nextRotation: CGFloat) {
        let animation = CABasicAnimation(keyPath: "transform.rotation.z")
        animation.fromValue = previousRotation
        animation.toValue = nextRotation
        animation.duration = appKitToolDisclosureAnimationDuration
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        layer.add(animation, forKey: "toolStatusDisclosureRotation")
    }

    private func addSymbolFadeOutTransitionIfNeeded() {
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
              let layer = symbolView.layer else {
            symbolView.isHidden = true
            return
        }
        let animation = CABasicAnimation(keyPath: "opacity")
        animation.fromValue = 1
        animation.toValue = 0
        animation.duration = appKitToolDisclosureFadeOutDuration
        animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
        layer.add(animation, forKey: "toolStatusDisclosureFadeOut")
    }

    private func addSymbolFadeTransition(to layer: CALayer) {
        let transition = CATransition()
        transition.type = .fade
        transition.duration = appKitToolDisclosureAnimationDuration
        transition.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        layer.add(transition, forKey: "toolStatusSymbolFade")
    }

    private func isDisclosureSymbol(_ systemName: String?) -> Bool {
        systemName == appKitToolDisclosureSymbolName
    }

    private func disclosureRotation(isExpanded: Bool) -> CGFloat {
        isExpanded ? appKitToolDisclosureExpandedRotation : 0
    }

    // Keep the view-backed layer centered while rotating; otherwise the disclosure
    // glyph can visually drift from the status slot during expand/collapse.
    private func positionSymbolLayer(rotation: CGFloat) {
        guard let layer = symbolView.layer else {
            return
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        layer.bounds = CGRect(origin: .zero, size: symbolView.bounds.size)
        layer.position = CGPoint(x: symbolView.frame.midX, y: symbolView.frame.midY)
        layer.setAffineTransform(CGAffineTransform(rotationAngle: rotation))
        CATransaction.commit()
    }

    private func updateSymbolConfiguration() {
        symbolView.symbolConfiguration = .init(
            pointSize: transcriptInlineToolRowMetrics(for: typography).statusIconSize,
            weight: .regular
        )
    }

    private struct SymbolTransition {
        let previousSymbolName: String?
        let nextSymbolName: String
        let previousRotation: CGFloat
        let nextRotation: CGFloat
        let symbolChanged: Bool
        let rotationChanged: Bool
    }
}

#if DEBUG
extension AppKitTranscriptToolStatusIndicatorView {
    var statusSymbolPointSizeForTesting: CGFloat {
        transcriptInlineToolRowMetrics(for: typography).statusIconSize
    }

    var statusSymbolSystemNameForTesting: String? {
        symbolSystemName
    }

    var statusSymbolTintColorForTesting: NSColor? {
        symbolView.contentTintColor
    }

    var statusSymbolRotationForTesting: CGFloat {
        symbolRotation
    }

    var statusSymbolLayerPositionForTesting: CGPoint? {
        symbolView.layer?.position
    }

    var statusSymbolRotationAnimationForTesting: CABasicAnimation? {
        symbolView.layer?.animation(forKey: "toolStatusDisclosureRotation") as? CABasicAnimation
    }

    var statusSymbolFadeOutAnimationForTesting: CABasicAnimation? {
        symbolView.layer?.animation(forKey: "toolStatusDisclosureFadeOut") as? CABasicAnimation
    }

    func performDisclosurePressForTesting() {
        onPress?()
    }
}
#endif
