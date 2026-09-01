import AppKit

/// Stateless drawing support for `ComposerReasoningMenuRowView`: symbol resolution, text
/// attributes, and image drawing that read only the passed-in configuration plus the view's
/// effective appearance.
extension ComposerReasoningMenuRowView {
    func symbolImage(named name: String, pointSize: CGFloat, color: NSColor) -> NSImage? {
        let configuration = NSImage.SymbolConfiguration(
            pointSize: pointSize,
            weight: .semibold
        ).applying(.init(paletteColors: [color, color, color]))
        return NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration)
    }

    func iconColor(for configuration: Configuration) -> NSColor {
        let color: NSColor = configuration.isWarning ? .systemOrange : .labelColor
        return color.appKitResolvedColor(in: self, alpha: configuration.isEnabled ? 0.72 : 0.32)
    }

    func titleAttributes(for configuration: Configuration) -> [NSAttributedString.Key: Any] {
        let color: NSColor = configuration.isWarning ? .systemOrange : .labelColor
        return [
            .font: ComposerReasoningMenuMetrics.itemFont,
            .foregroundColor: color.appKitResolvedColor(in: self, alpha: configuration.isEnabled ? 0.86 : 0.42),
            .paragraphStyle: ComposerReasoningMenuMetrics.truncatingParagraphStyle
        ]
    }

    func subtitleAttributes(for configuration: Configuration) -> [NSAttributedString.Key: Any] {
        var attributes = Self.subtitleMeasurementAttributes(lineLimit: configuration.subtitleLineLimit)
        attributes[.foregroundColor] = NSColor.secondaryLabelColor
            .appKitResolvedColor(in: self, alpha: configuration.isEnabled ? 0.68 : 0.32)
        return attributes
    }

    func symbolDrawingSize(for image: NSImage, maxSize: CGFloat) -> NSSize {
        let imageSize = image.size
        guard imageSize.width > 0, imageSize.height > 0 else {
            return NSSize(width: maxSize, height: maxSize)
        }
        let scale = min(maxSize / imageSize.width, maxSize / imageSize.height)
        return NSSize(width: ceil(imageSize.width * scale), height: ceil(imageSize.height * scale))
    }

    func drawImage(_ image: NSImage, in rect: NSRect, rotationRadians: CGFloat) {
        guard rotationRadians != 0 else {
            image.draw(
                in: rect,
                from: .zero,
                operation: .sourceOver,
                fraction: 1,
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
            fraction: 1,
            respectFlipped: true,
            hints: nil
        )
        NSGraphicsContext.restoreGraphicsState()
    }
}
