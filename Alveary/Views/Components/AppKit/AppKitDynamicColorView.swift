@preconcurrency import AppKit

/// Shared base view for AppKit surfaces that cache dynamic `NSColor`s into
/// `CALayer` `CGColor`s for native drawing.
///
/// Keep the dynamic `NSColor` as the source of truth so theme changes refresh
/// from one primitive instead of leaf views observing appearance changes.
class AppKitDynamicColorView: NSView {
    private var fillColorProvider: ((NSAppearance) -> NSColor?)?
    private var fillAlpha: CGFloat = 1
    private var fillPreservesResolvedAlpha = false
    private var strokeColorProvider: ((NSAppearance) -> NSColor?)?
    private var strokeAlpha: CGFloat = 1

    func setLayerFillColor(_ color: NSColor?, alpha: CGFloat = 1) {
        fillColorProvider = { _ in color }
        fillAlpha = alpha
        fillPreservesResolvedAlpha = false
        refreshDynamicLayerColors()
    }

    func setLayerStrokeColor(_ color: NSColor?, alpha: CGFloat = 1) {
        strokeColorProvider = { _ in color }
        strokeAlpha = alpha
        refreshDynamicLayerColors()
    }

    func setLayerFillColor(alpha: CGFloat = 1, provider: @escaping (NSAppearance) -> NSColor?) {
        fillColorProvider = provider
        fillAlpha = alpha
        fillPreservesResolvedAlpha = false
        refreshDynamicLayerColors()
    }

    func setLayerFillColorPreservingResolvedAlpha(provider: @escaping (NSAppearance) -> NSColor?) {
        fillColorProvider = provider
        fillAlpha = 1
        fillPreservesResolvedAlpha = true
        refreshDynamicLayerColors()
    }

    func setLayerStrokeColor(alpha: CGFloat = 1, provider: @escaping (NSAppearance) -> NSColor?) {
        strokeColorProvider = provider
        strokeAlpha = alpha
        refreshDynamicLayerColors()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshDynamicLayerColors()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        refreshDynamicLayerColors()
    }

    private func refreshDynamicLayerColors() {
        guard wantsLayer else {
            return
        }
        let appearance = appKitRenderingAppearance
        let fillColor = fillColorProvider?(appearance)
        layer?.backgroundColor = fillPreservesResolvedAlpha ?
            fillColor?.resolved(for: appearance).cgColor :
            fillColor?.appKitResolvedCGColor(in: self, alpha: fillAlpha)
        layer?.borderColor = strokeColorProvider?(appearance)?.appKitResolvedCGColor(in: self, alpha: strokeAlpha)
    }
}

/// Flipped variant for transcript and markdown rows that lay out top-to-bottom.
final class AppKitFlippedDynamicColorView: AppKitDynamicColorView {
    override var isFlipped: Bool {
        true
    }
}

/// Text field that refreshes a layer-backed dynamic fill across appearance
/// changes without each caller owning a custom observer.
final class AppKitDynamicColorTextField: NSTextField {
    private var fillColor: NSColor?
    private var fillAlpha: CGFloat = 1

    func setLayerFillColor(_ color: NSColor?, alpha: CGFloat = 1) {
        fillColor = color
        fillAlpha = alpha
        refreshDynamicLayerColors()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshDynamicLayerColors()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        refreshDynamicLayerColors()
    }

    private func refreshDynamicLayerColors() {
        guard wantsLayer else {
            return
        }
        layer?.backgroundColor = fillColor?.appKitResolvedCGColor(in: self, alpha: fillAlpha)
    }
}

/// Template image view that keeps a dynamic `contentTintColor` current across
/// effective-appearance changes.
final class AppKitDynamicTintImageView: NSImageView {
    private var dynamicTintColor: NSColor?
    private var dynamicTintAlpha: CGFloat = 1

    override var image: NSImage? {
        didSet {
            image?.isTemplate = true
            refreshDynamicTintColor()
        }
    }

    override var symbolConfiguration: NSImage.SymbolConfiguration? {
        didSet {
            refreshDynamicTintColor()
        }
    }

    func setDynamicContentTintColor(_ color: NSColor?) {
        dynamicTintColor = color
        dynamicTintAlpha = 1
        refreshDynamicTintColor()
    }

    func setDynamicContentTintColor(_ color: NSColor?, alpha: CGFloat) {
        dynamicTintColor = color
        dynamicTintAlpha = alpha
        refreshDynamicTintColor()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshDynamicTintColor()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        refreshDynamicTintColor()
    }

    private func refreshDynamicTintColor() {
        contentTintColor = dynamicTintColor?.appKitResolvedColor(in: self, alpha: dynamicTintAlpha)
    }
}

extension NSColor {
    @MainActor
    func appKitResolvedColor(in view: NSView, alpha: CGFloat = 1) -> NSColor {
        resolved(for: view.appKitRenderingAppearance).withAlphaComponent(alpha)
    }

    @MainActor
    fileprivate func appKitResolvedCGColor(in view: NSView, alpha: CGFloat = 1) -> CGColor {
        appKitResolvedColor(in: view, alpha: alpha).cgColor
    }
}

extension NSView {
    @MainActor
    var appKitRenderingAppearance: NSAppearance {
        appearance ?? window?.effectiveAppearance ?? effectiveAppearance
    }
}
