@preconcurrency import AppKit

@MainActor
extension AppKitComposerAttachmentStripView {
    override var isOpaque: Bool {
        false
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard bounds.width > 0, bounds.height > 0 else {
            return
        }

        let rect = bounds.insetBy(dx: AppKitChatComposerEditorController.borderWidth / 2, dy: 0)
        let path = topRoundedPath(rect: rect, radius: AppKitChatComposerEditorController.editorCornerRadius)
        let backgroundColor = BlockInputComposerStyle.imagePreviewStripBackgroundColor.resolved(for: appKitRenderingAppearance)
        if backgroundColor.alphaComponent > 0 {
            backgroundColor.setFill()
            path.fill()
        }

        let borderPath = NSBezierPath()
        let radius = AppKitChatComposerEditorController.editorCornerRadius
        borderPath.move(to: NSPoint(x: rect.minX, y: rect.maxY))
        borderPath.line(to: NSPoint(x: rect.minX, y: rect.minY + radius))
        borderPath.curve(
            to: NSPoint(x: rect.minX + radius, y: rect.minY),
            controlPoint1: NSPoint(x: rect.minX, y: rect.minY + radius * 0.45),
            controlPoint2: NSPoint(x: rect.minX + radius * 0.45, y: rect.minY)
        )
        borderPath.line(to: NSPoint(x: rect.maxX - radius, y: rect.minY))
        borderPath.curve(
            to: NSPoint(x: rect.maxX, y: rect.minY + radius),
            controlPoint1: NSPoint(x: rect.maxX - radius * 0.45, y: rect.minY),
            controlPoint2: NSPoint(x: rect.maxX, y: rect.minY + radius * 0.45)
        )
        borderPath.line(to: NSPoint(x: rect.maxX, y: rect.maxY))
        BlockInputComposerStyle.editorBorderColor.resolved(for: appKitRenderingAppearance).setStroke()
        borderPath.lineWidth = AppKitChatComposerEditorController.borderWidth
        borderPath.stroke()
    }

    private func topRoundedPath(rect: NSRect, radius: CGFloat) -> NSBezierPath {
        let radius = min(radius, min(rect.width, rect.height) / 2)
        let path = NSBezierPath()
        path.move(to: NSPoint(x: rect.minX, y: rect.maxY))
        path.line(to: NSPoint(x: rect.minX, y: rect.minY + radius))
        path.curve(
            to: NSPoint(x: rect.minX + radius, y: rect.minY),
            controlPoint1: NSPoint(x: rect.minX, y: rect.minY + radius * 0.45),
            controlPoint2: NSPoint(x: rect.minX + radius * 0.45, y: rect.minY)
        )
        path.line(to: NSPoint(x: rect.maxX - radius, y: rect.minY))
        path.curve(
            to: NSPoint(x: rect.maxX, y: rect.minY + radius),
            controlPoint1: NSPoint(x: rect.maxX - radius * 0.45, y: rect.minY),
            controlPoint2: NSPoint(x: rect.maxX, y: rect.minY + radius * 0.45)
        )
        path.line(to: NSPoint(x: rect.maxX, y: rect.maxY))
        path.close()
        return path
    }
}
