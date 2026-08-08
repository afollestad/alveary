@preconcurrency import AppKit

extension ActionIcon {
    /// Renders the glyph for AppKit controls that paint their own contents.
    ///
    /// Both sources end up in the same resolved colour as the label beside
    /// them, which is what keeps enabled and disabled states in step: SF
    /// Symbols get it from `hierarchicalColor`, and octicons — fixed-canvas
    /// artwork that ignores symbol configuration — are redrawn into a `side`
    /// box and tinted with a `.sourceAtop` fill over transparent pixels.
    func nsImage(side: CGFloat, color: NSColor) -> NSImage? {
        switch self {
        case .system(let name):
            let configuration = NSImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
                .applying(.init(hierarchicalColor: color))
            return NSImage(systemSymbolName: name, accessibilityDescription: nil)?
                .withSymbolConfiguration(configuration)
        case .octicon(let octicon):
            guard let asset = NSImage(named: octicon.assetName) else {
                return nil
            }
            return NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
                asset.draw(in: rect)
                color.set()
                rect.fill(using: .sourceAtop)
                return true
            }
        }
    }
}
