import AppKit
import SwiftUI

@testable import Alveary

@MainActor
extension SnapshotTests {
    func testAppImagePreviewOverlayLoadedLight() {
        assertMacSnapshot(
            appImagePreviewOverlay(colorScheme: .light),
            size: CGSize(width: 900, height: 640),
            named: "app_image_preview_loaded_light",
            colorScheme: .light
        )
    }

    func testAppImagePreviewOverlayLoadedDark() {
        assertMacSnapshot(
            appImagePreviewOverlay(colorScheme: .dark),
            size: CGSize(width: 900, height: 640),
            named: "app_image_preview_loaded_dark",
            colorScheme: .dark
        )
    }

    func testAppImagePreviewOverlayAppShotText() {
        let request = AppImagePreviewRequest.appShotFileURL(
            URL(fileURLWithPath: "/tmp/appshot.png"),
            title: "Preview - Document.pdf",
            axTreeText: """
            AXApplication: Preview
              AXWindow: Preview - Document.pdf
                AXToolbar
                  AXButton: Sidebar
                  AXButton: Share
                AXScrollArea
                  AXImage: Document page 1
            """
        )

        assertMacSnapshot(
            AppImagePreviewOverlay(
                request: request,
                onDismiss: {},
                imageLoader: { _ in Self.previewLoadedImage },
                imageSaver: { _, _ in true },
                initialLoadedImage: Self.previewLoadedImage,
                initialTextMode: true
            ),
            size: CGSize(width: 900, height: 640),
            named: "app_image_preview_appshot_text",
            colorScheme: .dark
        )
    }

    private func appImagePreviewOverlay(colorScheme: ColorScheme) -> some View {
        let request = AppImagePreviewRequest.fileURL(
            URL(fileURLWithPath: "/tmp/preview.png"),
            title: "Preview image.png"
        )
        return AppImagePreviewOverlay(
            request: request,
            onDismiss: {},
            imageLoader: { _ in Self.previewLoadedImage },
            imageSaver: { _, _ in true },
            initialLoadedImage: Self.previewLoadedImage
        )
        .environment(\.colorScheme, colorScheme)
    }

    private static var previewLoadedImage: AppImagePreviewLoadedImage {
        let size = NSSize(width: 1_200, height: 760)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor(calibratedRed: 0.18, green: 0.25, blue: 0.38, alpha: 1).setFill()
        NSRect(origin: .zero, size: size).fill()
        NSColor(calibratedRed: 0.42, green: 0.70, blue: 0.96, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: 80, y: 90, width: 360, height: 180), xRadius: 22, yRadius: 22).fill()
        NSColor(calibratedRed: 0.95, green: 0.78, blue: 0.36, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: 500, y: 150, width: 540, height: 420), xRadius: 28, yRadius: 28).fill()
        NSColor(calibratedRed: 0.12, green: 0.38, blue: 0.22, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: 680, y: 360, width: 240, height: 280), xRadius: 30, yRadius: 30).fill()
        image.unlockFocus()
        return AppImagePreviewLoadedImage(image: image, pixelSize: size)
    }
}
