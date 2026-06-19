import AppKit
import BlockInputKit
import XCTest

struct EditorCornerSamples {
    let topLeft: NSColor
    let topRight: NSColor
    let bottomLeft: NSColor
    let bottomRight: NSColor
}

@MainActor
func renderedEditorCornerSamples(
    _ editor: BlockInputView,
    file: StaticString = #filePath,
    line: UInt = #line
) throws -> EditorCornerSamples {
    editor.displayIfNeeded()
    editor.layoutSubtreeIfNeeded()
    editor.updateLayer()
    editor.layer?.layoutIfNeeded()

    let size = editor.bounds.size
    let bitmap = try XCTUnwrap(
        NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(size.width),
            pixelsHigh: Int(size.height),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ),
        file: file,
        line: line
    )
    bitmap.size = size
    let context = try XCTUnwrap(NSGraphicsContext(bitmapImageRep: bitmap), file: file, line: line)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    editor.layer?.render(in: context.cgContext)
    NSGraphicsContext.restoreGraphicsState()

    return EditorCornerSamples(
        topLeft: try XCTUnwrap(bitmap.colorAt(x: 2, y: 2), file: file, line: line),
        topRight: try XCTUnwrap(bitmap.colorAt(x: Int(size.width) - 3, y: 2), file: file, line: line),
        bottomLeft: try XCTUnwrap(bitmap.colorAt(x: 2, y: Int(size.height) - 3), file: file, line: line),
        bottomRight: try XCTUnwrap(bitmap.colorAt(x: Int(size.width) - 3, y: Int(size.height) - 3), file: file, line: line)
    )
}

func assertFilled(
    _ color: NSColor,
    _ corner: String,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    let resolved = color.usingColorSpace(.deviceRGB) ?? color
    let message = "Expected \(corner) to be filled for attached queued composer, got alpha \(resolved.alphaComponent)"
    XCTAssertGreaterThan(resolved.alphaComponent, 0.02, message, file: file, line: line)
}

func assertClipped(
    _ color: NSColor,
    _ corner: String,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    let resolved = color.usingColorSpace(.deviceRGB) ?? color
    let message = "Expected \(corner) to be clipped for attached queued composer, got alpha \(resolved.alphaComponent)"
    XCTAssertLessThan(resolved.alphaComponent, 0.01, message, file: file, line: line)
}
