@preconcurrency import AppKit
import SwiftUI

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
        let helpTextChanged = self.helpText != helpText
        self.helpText = helpText
        isEnabled = true
        alphaValue = 1
        toolTip = nil
        setAccessibilityLabel("More information")
        setAccessibilityValue(helpText ?? "")
        setAccessibilityHelp(helpText)
        if helpText?.isEmpty != false {
            closeHoverTooltip()
        } else if helpTextChanged, hoverTooltip.isShown {
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
        guard let helpText,
              !helpText.isEmpty,
              window != nil else {
            return
        }
        hoverTooltip.showForTesting(text: helpText)
    }

    var tooltipIgnoresMouseForTesting: Bool? {
        hoverTooltip.tooltipIgnoresMouse
    }

    var tooltipContentBuildCountForTesting: Int {
        hoverTooltip.contentBuildCountForTesting
    }

    var tooltipIsShownForTesting: Bool {
        hoverTooltip.isShown
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
    private var tooltipPopover: NSPopover?
#if DEBUG
    private var isShowingForTesting = false
    private(set) var contentBuildCountForTesting = 0
#endif

    var isShown: Bool {
#if DEBUG
        if isShowingForTesting {
            return true
        }
#endif
        return tooltipPopover?.isShown == true
    }

    func show(text: String, relativeTo sourceView: NSView) {
#if DEBUG
        if isShowingForTesting {
            showForTesting(text: text)
            return
        }
#endif
        close()

        guard let sourceWindow = sourceView.window else {
            return
        }

        let visibleFrame = sourceWindow.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
        let controller = makePopoverController(text: text)
        let preferredSize = controller.preferredContentSize
        let edge = preferredEdge(for: preferredSize, relativeTo: sourceView, visibleFrame: visibleFrame)
        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = false
        popover.contentViewController = controller
        popover.contentSize = preferredSize
        tooltipPopover = popover
        popover.show(relativeTo: sourceView.bounds, of: sourceView, preferredEdge: edge)
        updatePopoverWindowMouseHandling(for: popover)
        Task { @MainActor [weak self, weak popover] in
            await Task.yield()
            guard let self,
                  let popover,
                  self.tooltipPopover === popover else {
                return
            }
            self.updatePopoverWindowMouseHandling(for: popover)
        }
    }

    func close() {
        tooltipPopover?.performClose(nil)
        tooltipPopover = nil
#if DEBUG
        isShowingForTesting = false
#endif
    }

    private func preferredEdge(for contentSize: NSSize, relativeTo sourceView: NSView, visibleFrame: NSRect) -> NSRectEdge {
        if let button = sourceView as? AppKitHoverInfoButton {
            return button.preferredTooltipEdge(for: contentSize, visibleFrame: visibleFrame)
        }
        let sourceRect = sourceScreenRect(for: sourceView)
        let rightMargin: CGFloat = 12
        return visibleFrame.maxX - sourceRect.maxX >= contentSize.width + rightMargin ? .maxX : .maxY
    }

    private func sourceScreenRect(for sourceView: NSView) -> NSRect {
        guard let sourceWindow = sourceView.window else {
            return .zero
        }
        return sourceWindow.convertToScreen(sourceView.convert(sourceView.bounds, to: nil))
    }

    private func makePopoverController(text: String) -> NSHostingController<AppHoverTooltipContent> {
#if DEBUG
        contentBuildCountForTesting += 1
#endif
        let controller = NSHostingController(rootView: AppHoverTooltipContent(text: text))
        controller.preferredContentSize = controller.view.fittingSize
        return controller
    }

    private func updatePopoverWindowMouseHandling(for popover: NSPopover) {
        popover.contentViewController?.view.window?.ignoresMouseEvents = true
    }
}

#if DEBUG
extension AppKitHoverTooltipController {
    func showForTesting(text: String) {
        close()
        _ = makePopoverController(text: text)
        isShowingForTesting = true
    }

    var tooltipIgnoresMouse: Bool? {
        if isShowingForTesting {
            return true
        }
        return tooltipPopover?.contentViewController?.view.window?.ignoresMouseEvents
    }
}
#endif

struct AppHoverTooltipContent: View {
    private static let maxTextWidth: CGFloat = 280
    private static let textFont = NSFont.systemFont(ofSize: 13, weight: .semibold)

    let text: String

    var body: some View {
        Text(text)
            .font(.callout.weight(.semibold))
            .foregroundStyle(.primary)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: !Self.shouldWrap(text), vertical: true)
            .frame(width: Self.wrappedTextWidth(for: text), alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 15)
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
