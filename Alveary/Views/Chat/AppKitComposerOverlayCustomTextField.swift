@preconcurrency import AppKit

private typealias OverlayMetrics = AppKitComposerOverlayMetrics

final class AppKitComposerOverlayCustomTextField: NSTextField {
    override var intrinsicContentSize: NSSize {
        NSSize(width: super.intrinsicContentSize.width, height: OverlayMetrics.customFieldHeight)
    }
}

final class AppKitComposerOverlayCustomTextFieldCell: NSTextFieldCell {
    override func drawingRect(forBounds rect: NSRect) -> NSRect {
        centeredTextRect(forBounds: rect)
    }

    override func edit(
        withFrame rect: NSRect,
        in controlView: NSView,
        editor textObj: NSText,
        delegate: Any?,
        event: NSEvent?
    ) {
        super.edit(
            withFrame: centeredTextRect(forBounds: rect),
            in: controlView,
            editor: textObj,
            delegate: delegate,
            event: event
        )
    }

    override func select(
        withFrame rect: NSRect,
        in controlView: NSView,
        editor textObj: NSText,
        delegate: Any?,
        start selStart: Int,
        length selLength: Int
    ) {
        super.select(
            withFrame: centeredTextRect(forBounds: rect),
            in: controlView,
            editor: textObj,
            delegate: delegate,
            start: selStart,
            length: selLength
        )
    }

    private func centeredTextRect(forBounds rect: NSRect) -> NSRect {
        let textHeight = min(cellSize(forBounds: rect).height, rect.height)
        return NSRect(
            x: rect.minX,
            y: rect.minY + floor((rect.height - textHeight) / 2),
            width: rect.width,
            height: textHeight
        )
    }
}
