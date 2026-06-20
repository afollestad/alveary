@preconcurrency import AppKit
import SwiftUI

struct AppHoverPopup<Content: View>: View {
    private let arrowEdge: AppHoverPopupArrowEdge
    private let horizontalPadding: CGFloat
    private let verticalPadding: CGFloat
    private let textAlignment: TextAlignment
    private let content: Content

    init(
        arrowEdge: AppHoverPopupArrowEdge = .none,
        horizontalPadding: CGFloat = 18,
        verticalPadding: CGFloat = 14,
        textAlignment: TextAlignment = .center,
        @ViewBuilder content: () -> Content
    ) {
        self.arrowEdge = arrowEdge
        self.horizontalPadding = horizontalPadding
        self.verticalPadding = verticalPadding
        self.textAlignment = textAlignment
        self.content = content()
    }

    var body: some View {
        content
            .multilineTextAlignment(textAlignment)
            .padding(.vertical, verticalPadding)
            .padding(.horizontal, horizontalPadding)
            .padding(.top, arrowEdge == .top ? AppHoverPopupBubbleShape.arrowDepth : 0)
            .padding(.leading, arrowEdge == .leading ? AppHoverPopupBubbleShape.arrowDepth : 0)
            .background {
                AppHoverPopupBubbleShape(arrowEdge: arrowEdge)
                    .fill(Color(nsColor: AppPopupSurfaceStyle.backgroundNSColor))
                    .shadow(color: .black.opacity(0.18), radius: 14, y: 6)
                    .overlay {
                        AppHoverPopupBubbleShape(arrowEdge: arrowEdge)
                            .stroke(Color.secondary.opacity(0.22), lineWidth: 1)
                    }
            }
    }
}

enum AppHoverPopupArrowEdge {
    case none
    case top
    case leading
}

struct AppHoverInfoIcon: View {
    let text: String

    var body: some View {
        AppHoverInfoIconRepresentable(text: text)
            .frame(width: 14, height: 14)
    }
}

@MainActor
class AppKitHoverInfoButton: NSButton {
    private static let iconConfiguration = NSImage.SymbolConfiguration(pointSize: 10.5, weight: .medium)

    private var trackingArea: NSTrackingArea?
    private var hoverTooltip = AppKitHoverTooltipController()
    private var helpText: String?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: 14, height: 14)
    }

    override var isEnabled: Bool {
        get { true }
        set {
            // Settings rows can disable their parent controls, but the help affordance should
            // stay visually stable and remain available for explaining disabled settings.
            _ = newValue
            preserveEnabledIconAppearance()
        }
    }

    func configure(helpText: String?) {
        self.helpText = helpText
        isEnabled = true
        alphaValue = 1
        toolTip = nil
        setAccessibilityLabel("More information")
        setAccessibilityValue(helpText ?? "")
        setAccessibilityHelp(helpText)
        if helpText == nil {
            closeHoverTooltip()
        } else if hoverTooltip.isShown {
            updateHoverTooltip()
        }
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

    override func mouseEntered(with event: NSEvent) {
        showHoverTooltip()
    }

    override func mouseExited(with event: NSEvent) {
        closeHoverTooltip()
    }

    override func mouseDown(with event: NSEvent) {
        showHoverTooltip()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        refreshIconImage()
        if window == nil {
            closeHoverTooltip()
        }
    }

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        if superview == nil {
            closeHoverTooltip()
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshIconImage()
        updateHoverTooltip()
    }

    func closeHoverTooltip() {
        hoverTooltip.close()
    }

    func preferredTooltipEdge(for contentSize: NSSize, visibleFrame: NSRect) -> NSRectEdge {
        guard let window else {
            return .maxY
        }
        let screenRect = window.convertToScreen(convert(bounds, to: nil))
        let rightMargin: CGFloat = 12
        let availableRightSpace = visibleFrame.maxX - screenRect.maxX
        return availableRightSpace >= contentSize.width + rightMargin ? .maxX : .maxY
    }

    private func setup() {
        isBordered = false
        refusesFirstResponder = true
        imagePosition = .imageOnly
        imageScaling = .scaleNone
        alignment = .center
        setButtonType(.momentaryChange)
        (cell as? NSButtonCell)?.highlightsBy = []
        (cell as? NSButtonCell)?.showsStateBy = []
        refreshIconImage()
    }

    private func preserveEnabledIconAppearance() {
        super.isEnabled = true
        alphaValue = 1
        refreshIconImage()
    }

    private func refreshIconImage() {
        let color = iconColor()
        image = tintedIconImage(color: color)
        contentTintColor = nil
    }

    private func iconColor() -> NSColor {
        // Preserve the semantic color's own alpha. Forcing alpha to 1 makes
        // dark-mode secondary label icons read as white instead of muted gray.
        NSColor.secondaryLabelColor.resolved(for: appKitRenderingAppearance)
    }

    private func tintedIconImage(color: NSColor) -> NSImage? {
        guard let symbol = NSImage(systemSymbolName: "info.circle", accessibilityDescription: "More information")?
            .withSymbolConfiguration(Self.iconConfiguration) else {
            return nil
        }
        let image = NSImage(size: symbol.size)
        image.lockFocus()
        defer {
            image.unlockFocus()
        }
        let rect = NSRect(origin: .zero, size: symbol.size)
        color.setFill()
        rect.fill()
        symbol.draw(in: rect, from: .zero, operation: .destinationIn, fraction: 1)
        image.isTemplate = false
        return image
    }

    private func showHoverTooltip() {
        guard let helpText,
              !helpText.isEmpty,
              window != nil else {
            return
        }
        hoverTooltip.show(text: helpText, relativeTo: self)
    }

    private func updateHoverTooltip() {
        guard hoverTooltip.isShown,
              let helpText,
              !helpText.isEmpty,
              window != nil else {
            return
        }
        hoverTooltip.show(text: helpText, relativeTo: self)
    }
}

#if DEBUG
extension AppKitHoverInfoButton {
    var iconColorForTesting: NSColor {
        iconColor()
    }

    func preferredTooltipEdgeForTesting(contentSize: NSSize, visibleFrame: NSRect) -> NSRectEdge {
        preferredTooltipEdge(for: contentSize, visibleFrame: visibleFrame)
    }

    func showTooltipForTesting() {
        showHoverTooltip()
    }

    var tooltipIgnoresMouseForTesting: Bool? {
        hoverTooltip.tooltipIgnoresMouse
    }
}
#endif

private struct AppHoverInfoIconRepresentable: NSViewRepresentable {
    let text: String

    func makeNSView(context: Context) -> AppKitHoverInfoButton {
        AppKitHoverInfoButton()
    }

    func updateNSView(_ nsView: AppKitHoverInfoButton, context: Context) {
        nsView.configure(helpText: text)
    }

    static func dismantleNSView(_ nsView: AppKitHoverInfoButton, coordinator: ()) {
        nsView.closeHoverTooltip()
    }
}

@MainActor
final class AppKitHoverTooltipController {
    private var tooltipWindow: NSWindow?
    private weak var parentWindow: NSWindow?

    var isShown: Bool {
        tooltipWindow?.isVisible == true
    }

    func show(text: String, relativeTo sourceView: NSView) {
        close()

        guard let sourceWindow = sourceView.window else {
            return
        }

        let visibleFrame = sourceWindow.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
        let rightView = makeHostingView(text: text, arrowEdge: .leading)
        let rightSize = rightView.fittingSize
        let edge = preferredEdge(for: rightSize, relativeTo: sourceView, visibleFrame: visibleFrame)
        let hostingView = edge == .maxX ? rightView : makeHostingView(text: text, arrowEdge: .top)
        let preferredSize = hostingView.fittingSize
        let frame = tooltipFrame(
            size: preferredSize,
            edge: edge,
            relativeTo: sourceView,
            visibleFrame: visibleFrame
        )
        let tooltipWindow = NSPanel(
            contentRect: frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        tooltipWindow.backgroundColor = .clear
        tooltipWindow.contentView = hostingView
        tooltipWindow.hasShadow = false
        tooltipWindow.ignoresMouseEvents = true
        tooltipWindow.isOpaque = false
        tooltipWindow.level = .popUpMenu
        tooltipWindow.collectionBehavior = [.transient, .ignoresCycle]
        sourceWindow.addChildWindow(tooltipWindow, ordered: .above)
        tooltipWindow.orderFront(nil)
        self.tooltipWindow = tooltipWindow
        parentWindow = sourceWindow
    }

    func close() {
        if let tooltipWindow {
            parentWindow?.removeChildWindow(tooltipWindow)
            tooltipWindow.orderOut(nil)
        }
        tooltipWindow = nil
        parentWindow = nil
    }

    private func preferredEdge(for contentSize: NSSize, relativeTo sourceView: NSView, visibleFrame: NSRect) -> NSRectEdge {
        if let button = sourceView as? AppKitHoverInfoButton {
            return button.preferredTooltipEdge(for: contentSize, visibleFrame: visibleFrame)
        }
        let sourceRect = sourceScreenRect(for: sourceView)
        let rightMargin: CGFloat = 12
        return visibleFrame.maxX - sourceRect.maxX >= contentSize.width + rightMargin ? .maxX : .maxY
    }

    private func tooltipFrame(size: NSSize, edge: NSRectEdge, relativeTo sourceView: NSView, visibleFrame: NSRect) -> NSRect {
        let sourceRect = sourceScreenRect(for: sourceView)
        let margin: CGFloat = 6
        let shadowPadding = AppHoverTooltipContent.shadowPadding
        let origin: NSPoint
        switch edge {
        case .maxX:
            origin = NSPoint(
                x: sourceRect.maxX + margin - shadowPadding,
                y: clamped(sourceRect.midY - (size.height / 2), min: visibleFrame.minY + margin, max: visibleFrame.maxY - size.height - margin)
            )
        default:
            origin = NSPoint(
                x: clamped(sourceRect.midX - (size.width / 2), min: visibleFrame.minX + margin, max: visibleFrame.maxX - size.width - margin),
                y: sourceRect.minY - size.height - margin + shadowPadding
            )
        }
        return NSRect(origin: origin, size: size)
    }

    private func sourceScreenRect(for sourceView: NSView) -> NSRect {
        guard let sourceWindow = sourceView.window else {
            return .zero
        }
        return sourceWindow.convertToScreen(sourceView.convert(sourceView.bounds, to: nil))
    }

    private func makeHostingView(text: String, arrowEdge: AppHoverPopupArrowEdge) -> NSHostingView<AppHoverTooltipContent> {
        let view = NSHostingView(rootView: AppHoverTooltipContent(text: text, arrowEdge: arrowEdge))
        view.frame = NSRect(origin: .zero, size: view.fittingSize)
        return view
    }

    private func clamped(_ value: CGFloat, min minValue: CGFloat, max maxValue: CGFloat) -> CGFloat {
        guard maxValue >= minValue else {
            return minValue
        }
        return min(max(value, minValue), maxValue)
    }
}

#if DEBUG
extension AppKitHoverTooltipController {
    var tooltipIgnoresMouse: Bool? {
        tooltipWindow?.ignoresMouseEvents
    }
}
#endif

private struct AppHoverTooltipContent: View {
    static let shadowPadding: CGFloat = 10
    private static let maxTextWidth: CGFloat = 280
    private static let textFont = NSFont.systemFont(ofSize: 13, weight: .semibold)

    let text: String
    let arrowEdge: AppHoverPopupArrowEdge

    var body: some View {
        AppHoverPopup(arrowEdge: arrowEdge, horizontalPadding: 12, verticalPadding: 15, textAlignment: .leading) {
            Text(text)
                .font(.callout.weight(.semibold))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: !Self.shouldWrap(text), vertical: false)
                .frame(width: Self.wrappedTextWidth(for: text), alignment: .leading)
        }
        .padding(Self.shadowPadding)
    }

    private static func shouldWrap(_ text: String) -> Bool {
        measuredTextWidth(for: text) > maxTextWidth
    }

    private static func wrappedTextWidth(for text: String) -> CGFloat? {
        shouldWrap(text) ? maxTextWidth : nil
    }

    private static func measuredTextWidth(for text: String) -> CGFloat {
        let attributes: [NSAttributedString.Key: Any] = [.font: textFont]
        return ceil((text as NSString).size(withAttributes: attributes).width)
    }
}

private struct AppHoverPopupBubbleShape: Shape {
    static let arrowDepth: CGFloat = 8
    private static let arrowLength: CGFloat = 14

    let arrowEdge: AppHoverPopupArrowEdge

    func path(in rect: CGRect) -> Path {
        switch arrowEdge {
        case .none:
            return Path(roundedRect: rect, cornerRadius: 10)
        case .top:
            return topArrowPath(in: rect)
        case .leading:
            return leadingArrowPath(in: rect)
        }
    }

    private func topArrowPath(in rect: CGRect) -> Path {
        let arrowDepth = Self.arrowDepth
        let arrowHalfLength = Self.arrowLength / 2
        let bubble = CGRect(
            x: rect.minX,
            y: rect.minY + arrowDepth,
            width: rect.width,
            height: max(0, rect.height - arrowDepth)
        )
        let radius = min(10, bubble.width / 2, bubble.height / 2)
        let arrowX = min(max(rect.midX, bubble.minX + radius + arrowHalfLength), bubble.maxX - radius - arrowHalfLength)
        var path = Path()
        path.move(to: CGPoint(x: arrowX, y: rect.minY))
        path.addLine(to: CGPoint(x: arrowX + arrowHalfLength, y: bubble.minY))
        path.addLine(to: CGPoint(x: bubble.maxX - radius, y: bubble.minY))
        path.addQuadCurve(to: CGPoint(x: bubble.maxX, y: bubble.minY + radius), control: CGPoint(x: bubble.maxX, y: bubble.minY))
        path.addLine(to: CGPoint(x: bubble.maxX, y: bubble.maxY - radius))
        path.addQuadCurve(to: CGPoint(x: bubble.maxX - radius, y: bubble.maxY), control: CGPoint(x: bubble.maxX, y: bubble.maxY))
        path.addLine(to: CGPoint(x: bubble.minX + radius, y: bubble.maxY))
        path.addQuadCurve(to: CGPoint(x: bubble.minX, y: bubble.maxY - radius), control: CGPoint(x: bubble.minX, y: bubble.maxY))
        path.addLine(to: CGPoint(x: bubble.minX, y: bubble.minY + radius))
        path.addQuadCurve(to: CGPoint(x: bubble.minX + radius, y: bubble.minY), control: CGPoint(x: bubble.minX, y: bubble.minY))
        path.addLine(to: CGPoint(x: arrowX - arrowHalfLength, y: bubble.minY))
        path.closeSubpath()
        return path
    }

    private func leadingArrowPath(in rect: CGRect) -> Path {
        let arrowDepth = Self.arrowDepth
        let arrowHalfLength = Self.arrowLength / 2
        let bubble = CGRect(
            x: rect.minX + arrowDepth,
            y: rect.minY,
            width: max(0, rect.width - arrowDepth),
            height: rect.height
        )
        let radius = min(10, bubble.width / 2, bubble.height / 2)
        let arrowY = min(max(rect.midY, bubble.minY + radius + arrowHalfLength), bubble.maxY - radius - arrowHalfLength)
        var path = Path()
        path.move(to: CGPoint(x: bubble.minX + radius, y: bubble.minY))
        path.addLine(to: CGPoint(x: bubble.maxX - radius, y: bubble.minY))
        path.addQuadCurve(to: CGPoint(x: bubble.maxX, y: bubble.minY + radius), control: CGPoint(x: bubble.maxX, y: bubble.minY))
        path.addLine(to: CGPoint(x: bubble.maxX, y: bubble.maxY - radius))
        path.addQuadCurve(to: CGPoint(x: bubble.maxX - radius, y: bubble.maxY), control: CGPoint(x: bubble.maxX, y: bubble.maxY))
        path.addLine(to: CGPoint(x: bubble.minX + radius, y: bubble.maxY))
        path.addQuadCurve(to: CGPoint(x: bubble.minX, y: bubble.maxY - radius), control: CGPoint(x: bubble.minX, y: bubble.maxY))
        path.addLine(to: CGPoint(x: bubble.minX, y: arrowY + arrowHalfLength))
        path.addLine(to: CGPoint(x: rect.minX, y: arrowY))
        path.addLine(to: CGPoint(x: bubble.minX, y: arrowY - arrowHalfLength))
        path.addLine(to: CGPoint(x: bubble.minX, y: bubble.minY + radius))
        path.addQuadCurve(to: CGPoint(x: bubble.minX + radius, y: bubble.minY), control: CGPoint(x: bubble.minX, y: bubble.minY))
        path.closeSubpath()
        return path
    }
}
