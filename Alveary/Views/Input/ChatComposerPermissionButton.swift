import AppKit

@MainActor
class ComposerIconTitleDropdownButton: ComposerCompactDropdownButton {
    static let minWidth: CGFloat = 64
    static let maxWidth: CGFloat = 184

    static let iconSlotSize: CGFloat = 16
    static let iconTextSpacing: CGFloat = 5
    static let iconPointSize: CGFloat = 13
    private static let symbolTransitionDuration: TimeInterval = 0.14

    struct Presentation: Equatable {
        let title: String
        let symbolName: String
        let iconRotationRadians: CGFloat
        let isWarning: Bool

        init(
            title: String,
            symbolName: String,
            iconRotationRadians: CGFloat = 0,
            isWarning: Bool = false
        ) {
            self.title = title
            self.symbolName = symbolName
            self.iconRotationRadians = iconRotationRadians
            self.isWarning = isWarning
        }
    }

    private struct SymbolTransition {
        let previous: Presentation
        let current: Presentation
        let startedAt: TimeInterval
    }

    private var presentation: Presentation?
    private var lastResolvedPresentation: Presentation?
    private var symbolTransition: SymbolTransition?

    override var minimumDropdownWidth: CGFloat { Self.minWidth }
    override var maximumDropdownWidth: CGFloat { Self.maxWidth }
    override var chevronSlotWidth: CGFloat { Self.iconTextSpacing + chevronDrawingWidth }
    override var chevronColor: NSColor {
        guard let presentation = currentPresentation, presentation.isWarning else {
            return super.chevronColor
        }
        return foregroundColor(for: presentation)
    }
    override var measuredContentWidth: CGFloat {
        guard let presentation else {
            return 0
        }
        return Self.iconSlotSize + Self.iconTextSpacing +
            presentation.title.size(withAttributes: [.font: titleFont]).width
    }

    func configure(
        presentation: Presentation,
        height: CGFloat,
        isEnabled: Bool,
        actionHandler: @escaping () -> Void
    ) {
        self.presentation = presentation
        configureBase(height: height, isEnabled: isEnabled, actionHandler: actionHandler)
        setAccessibilityValue(presentation.title)
    }

    #if DEBUG
    var debugTitle: String? { currentPresentation?.title }
    var debugSymbolName: String? { currentPresentation?.symbolName }
    var debugIconRotationRadians: CGFloat { currentPresentation?.iconRotationRadians ?? 0 }
    var debugIsWarning: Bool { currentPresentation?.isWarning == true }
    var debugIconSlotSize: CGFloat { Self.iconSlotSize }
    var debugIconTextSpacing: CGFloat { Self.iconTextSpacing }
    var debugTextChevronSpacing: CGFloat { chevronSlotWidth - chevronDrawingWidth }
    var debugReservesTrailingSlot: Bool { reservesTrailingSlot }
    var debugDrawsChevron: Bool { drawsChevron }
    var debugHasSymbolTransition: Bool { symbolTransition != nil }
    var debugForegroundColor: NSColor? {
        currentPresentation.map { foregroundColor(for: $0) }
    }
    #endif

    func resolvedPresentation(from presentation: Presentation) -> Presentation {
        presentation
    }

    func cancelSymbolTransition() {
        symbolTransition = nil
    }

    func currentResolvedPresentation() -> Presentation? {
        currentPresentation
    }

    func prepareSymbolTransitionForCurrentPresentation(previousPresentation: Presentation? = nil) {
        guard let presentation = currentPresentation else {
            lastResolvedPresentation = nil
            symbolTransition = nil
            return
        }
        let previousPresentation = lastResolvedPresentation ?? previousPresentation
        defer {
            lastResolvedPresentation = presentation
        }
        guard animatesSymbolChanges,
              controlIsEnabled,
              let previousPresentation,
              previousPresentation.symbolName != presentation.symbolName else {
            if !animatesSymbolChanges || !controlIsEnabled {
                symbolTransition = nil
            }
            return
        }
        symbolTransition = SymbolTransition(
            previous: previousPresentation,
            current: presentation,
            startedAt: Date().timeIntervalSinceReferenceDate
        )
    }

    override func drawContent(in rect: NSRect) {
        guard let presentation = currentPresentation else {
            lastResolvedPresentation = nil
            symbolTransition = nil
            return
        }
        let foregroundColor = foregroundColor(for: presentation)
        updateSymbolTransitionIfNeeded(to: presentation)
        drawSymbol(for: presentation, color: foregroundColor, in: rect)

        let attributes: [NSAttributedString.Key: Any] = [
            .font: titleFont,
            .foregroundColor: foregroundColor,
            .paragraphStyle: truncatingParagraphStyle
        ]
        let titleSize = presentation.title.size(withAttributes: attributes)
        let titleX = rect.minX + Self.iconSlotSize + Self.iconTextSpacing
        (presentation.title as NSString).draw(
            in: NSRect(
                x: titleX,
                y: floor((bounds.height - titleSize.height) / 2),
                width: max(0, rect.maxX - titleX),
                height: titleSize.height
            ),
            withAttributes: attributes
        )
    }

    private var currentPresentation: Presentation? {
        presentation.map { resolvedPresentation(from: $0) }
    }

    private var titleFont: NSFont {
        NSFont.preferredFont(forTextStyle: .body)
    }

    private var truncatingParagraphStyle: NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byTruncatingTail
        return style
    }

    private func foregroundColor(for presentation: Presentation) -> NSColor {
        let color: NSColor = presentation.isWarning ? .systemOrange : .labelColor
        return color.appKitResolvedColor(in: self, alpha: textAlpha)
    }

    private func iconOpticalYOffset(for presentation: Presentation) -> CGFloat {
        presentation.iconRotationRadians == 0 ? 0 : 1
    }

    private func updateSymbolTransitionIfNeeded(to presentation: Presentation) {
        defer {
            lastResolvedPresentation = presentation
        }
        guard animatesSymbolChanges,
              controlIsEnabled,
              let previous = lastResolvedPresentation,
              previous.symbolName != presentation.symbolName else {
            if !animatesSymbolChanges || !controlIsEnabled {
                symbolTransition = nil
            }
            return
        }
        symbolTransition = SymbolTransition(
            previous: previous,
            current: presentation,
            startedAt: Date().timeIntervalSinceReferenceDate
        )
    }

    var animatesSymbolChanges: Bool {
        false
    }

    private func drawSymbol(for presentation: Presentation, color: NSColor, in rect: NSRect) {
        guard let transition = symbolTransition,
              transition.current.symbolName == presentation.symbolName else {
            drawSymbol(presentation, color: color, alpha: 1, in: rect)
            return
        }

        let elapsed = Date().timeIntervalSinceReferenceDate - transition.startedAt
        let progress = min(1, max(0, elapsed / Self.symbolTransitionDuration))
        drawSymbol(transition.previous, color: color, alpha: 1 - progress, in: rect)
        drawSymbol(transition.current, color: color, alpha: progress, in: rect)

        if progress >= 1 {
            symbolTransition = nil
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.needsDisplay = true
            }
        }
    }

    private func drawSymbol(_ presentation: Presentation, color: NSColor, alpha: CGFloat, in rect: NSRect) {
        guard alpha > 0,
              let image = permissionSymbolImage(named: presentation.symbolName, color: color) else {
            return
        }
        let maxSize = symbolDrawMaxSize(for: presentation)
        let drawSize = symbolDrawingSize(for: image, maxSize: maxSize)
        drawImage(
            image,
            in: NSRect(
                x: rect.minX + floor((Self.iconSlotSize - drawSize.width) / 2),
                y: floor((bounds.height - drawSize.height) / 2) + iconOpticalYOffset(for: presentation),
                width: drawSize.width,
                height: drawSize.height
            ),
            rotationRadians: presentation.iconRotationRadians,
            alpha: alpha
        )
    }

    func symbolDrawMaxSize(for presentation: Presentation) -> CGFloat {
        Self.iconSlotSize
    }

    private func permissionSymbolImage(named name: String, color: NSColor) -> NSImage? {
        let configuration = NSImage.SymbolConfiguration(
            pointSize: Self.iconPointSize,
            weight: .semibold
        ).applying(.init(paletteColors: [color, color, color]))
        return NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration)
    }

    private func drawImage(_ image: NSImage, in rect: NSRect, rotationRadians: CGFloat, alpha: CGFloat) {
        guard rotationRadians != 0 else {
            image.draw(
                in: rect,
                from: .zero,
                operation: .sourceOver,
                fraction: alpha,
                respectFlipped: true,
                hints: nil
            )
            return
        }

        NSGraphicsContext.saveGraphicsState()
        let transform = NSAffineTransform()
        transform.translateX(by: rect.midX, yBy: rect.midY)
        transform.rotate(byRadians: rotationRadians)
        transform.translateX(by: -rect.midX, yBy: -rect.midY)
        transform.concat()
        image.draw(
            in: rect,
            from: .zero,
            operation: .sourceOver,
            fraction: alpha,
            respectFlipped: true,
            hints: nil
        )
        NSGraphicsContext.restoreGraphicsState()
    }

    private var chevronDrawingWidth: CGFloat {
        guard let image = symbolImage(named: "chevron.down", pointSize: chevronMaxSize, color: .labelColor) else {
            return chevronMaxSize
        }
        return symbolDrawingSize(for: image, maxSize: chevronMaxSize).width
    }
}

@MainActor
final class ComposerPermissionButton: ComposerIconTitleDropdownButton {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setAccessibilityLabel("Permissions")
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setAccessibilityLabel("Permissions")
    }

    func configure(
        option: ChatComposerActionRowView.PermissionOptionPresentation,
        height: CGFloat,
        isEnabled: Bool,
        actionHandler: @escaping () -> Void
    ) {
        configure(
            presentation: .init(
                title: option.title,
                symbolName: option.symbolName,
                isWarning: option.isWarning
            ),
            height: height,
            isEnabled: isEnabled,
            actionHandler: actionHandler
        )
    }
}

@MainActor
final class ComposerPlanModeButton: ComposerIconTitleDropdownButton {
    private var usesExitSymbol = false

    override var reservesTrailingSlot: Bool { false }
    override var drawsChevron: Bool { false }
    override var animatesSymbolChanges: Bool { true }

    override func symbolDrawMaxSize(for presentation: Presentation) -> CGFloat {
        presentation.symbolName == "xmark" ? 12 : super.symbolDrawMaxSize(for: presentation)
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setAccessibilityLabel("Exit plan mode")
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setAccessibilityLabel("Exit plan mode")
    }

    func configure(height: CGFloat, isEnabled: Bool, actionHandler: @escaping () -> Void) {
        configure(
            presentation: .init(
                title: "Plan",
                symbolName: "checklist"
            ),
            height: height,
            isEnabled: isEnabled,
            actionHandler: { [weak self] in
                self?.resetInteractionState()
                actionHandler()
            }
        )
    }

    override func resolvedPresentation(from presentation: Presentation) -> Presentation {
        Presentation(
            title: presentation.title,
            symbolName: usesExitSymbol ? "xmark" : presentation.symbolName,
            iconRotationRadians: presentation.iconRotationRadians,
            isWarning: presentation.isWarning
        )
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        guard controlIsEnabled else {
            return
        }
        let previousPresentation = currentResolvedPresentation()
        usesExitSymbol = true
        prepareSymbolTransitionForCurrentPresentation(previousPresentation: previousPresentation)
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        super.resetInteractionState()
        let previousPresentation = currentResolvedPresentation()
        usesExitSymbol = false
        prepareSymbolTransitionForCurrentPresentation(previousPresentation: previousPresentation)
        needsDisplay = true
    }

    override func resetInteractionState() {
        super.resetInteractionState()
        usesExitSymbol = false
        cancelSymbolTransition()
        needsDisplay = true
    }
}
