import AppKit

func transcriptInlineToolRowPulseHighlightColor(isHovered: Bool) -> NSColor {
    let baseColor = transcriptInlineToolRowForegroundColor(isHovered: isHovered)
    return NSColor(name: nil) { appearance in
        let base = baseColor.resolved(for: appearance)
        let label = NSColor.labelColor.resolved(for: appearance)
        return base.interpolated(toward: label, amount: 0.45)
    }
}

private extension NSColor {
    func interpolated(toward target: NSColor, amount: CGFloat) -> NSColor {
        guard let sourceRGB = usingColorSpace(.deviceRGB),
              let targetRGB = target.usingColorSpace(.deviceRGB) else {
            return target
        }
        let clampedAmount = min(max(amount, 0), 1)
        return NSColor(
            deviceRed: sourceRGB.redComponent + ((targetRGB.redComponent - sourceRGB.redComponent) * clampedAmount),
            green: sourceRGB.greenComponent + ((targetRGB.greenComponent - sourceRGB.greenComponent) * clampedAmount),
            blue: sourceRGB.blueComponent + ((targetRGB.blueComponent - sourceRGB.blueComponent) * clampedAmount),
            alpha: sourceRGB.alphaComponent + ((targetRGB.alphaComponent - sourceRGB.alphaComponent) * clampedAmount)
        )
    }
}
