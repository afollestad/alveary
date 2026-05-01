@preconcurrency import AppKit

final class AppKitTranscriptHeaderToggleButton: NSButton {
    private enum Metrics {
        static let height: CGFloat = 24
        static let iconSize: CGFloat = 13
        static let iconTextSpacing: CGFloat = 4
    }

    private var isPressed = false
    var symbolName: String? {
        didSet {
            image = nil
            needsDisplay = true
            invalidateIntrinsicContentSize()
        }
    }

    var preferredWidth: CGFloat {
        let titleWidth = ceil((title as NSString).size(withAttributes: [.font: drawingFont]).width)
        let imageWidth = symbolDrawingSize?.width ?? 0
        let symbolWidth = symbolName == nil ? 0 : imageWidth + Metrics.iconTextSpacing
        return ceil(symbolWidth + titleWidth)
    }

    override var fittingSize: NSSize {
        NSSize(width: preferredWidth, height: Metrics.height)
    }

    override var intrinsicContentSize: NSSize {
        fittingSize
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled else {
            return
        }
        isPressed = true
        needsDisplay = true
        super.mouseDown(with: event)
        isPressed = false
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let color = NSColor.secondaryLabelColor.appKitResolvedColor(in: self, alpha: isPressed ? appHeaderTogglePressedOpacity : 1)
        let textAttributes: [NSAttributedString.Key: Any] = [
            .font: drawingFont,
            .foregroundColor: color
        ]
        let titleSize = (title as NSString).size(withAttributes: textAttributes)
        let symbolSize = symbolDrawingSize ?? .zero
        let imageWidth = symbolName == nil ? 0 : symbolSize.width + Metrics.iconTextSpacing
        var currentX = bounds.minX
        let centerY = bounds.midY

        if let symbolName,
           let image = symbolImage(named: symbolName, color: color) {
            let imageRect = NSRect(
                x: currentX,
                y: floor(centerY - (symbolSize.height / 2)),
                width: symbolSize.width,
                height: symbolSize.height
            )
            image.draw(in: imageRect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
            currentX += imageWidth
        }

        (title as NSString).draw(
            in: NSRect(x: currentX, y: floor(centerY - (titleSize.height / 2)), width: titleSize.width, height: titleSize.height),
            withAttributes: textAttributes
        )
    }

    private var drawingFont: NSFont {
        font ?? .systemFont(ofSize: max(NSFont.systemFontSize - 2, 9), weight: .medium)
    }

    private var symbolDrawingSize: NSSize? {
        guard let symbolName,
              let image = symbolImage(named: symbolName, color: .secondaryLabelColor) else {
            return nil
        }
        return symbolDrawingSize(for: image)
    }

    private func symbolDrawingSize(for image: NSImage) -> NSSize {
        // SwiftUI `Label` preserves SF Symbol aspect. Drawing AppKit symbols into
        // a square rect stretches wide chevrons vertically, making Show more/less
        // diverge from the SwiftUI transcript bubbles.
        let size = image.size
        guard size.width > 0, size.height > 0 else {
            return NSSize(width: Metrics.iconSize, height: Metrics.iconSize)
        }
        let scale = min(Metrics.iconSize / size.width, Metrics.iconSize / size.height)
        return NSSize(width: ceil(size.width * scale), height: ceil(size.height * scale))
    }

    private func symbolImage(named name: String, color: NSColor) -> NSImage? {
        // Match SwiftUI's `Label` behavior by resolving the symbol from the
        // same color used for the Show more/less title.
        let configuration = NSImage.SymbolConfiguration(pointSize: 12, weight: .medium)
            .applying(.init(hierarchicalColor: color))
        return NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration)
    }
}

#if DEBUG
extension AppKitTranscriptHeaderToggleButton {
    var symbolNameForTesting: String? {
        symbolName
    }

    var symbolDrawingSizeForTesting: NSSize? {
        symbolDrawingSize
    }
}
#endif
