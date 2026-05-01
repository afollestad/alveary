import AppKit
import SwiftUI
import XCTest

@testable import Alveary

@MainActor
final class AppMarkdownInteractionTests: XCTestCase {
    func testTaskCheckboxUsesCachedStateInsideSelectableMarkdown() throws {
        let markdown = "- [ ] Review task"
        let taskStateScope = UUID().uuidString
        let taskID = Self.taskID(
            markdown: markdown,
            taskStateScope: taskStateScope,
            path: "0.0"
        )

        let uncheckedHost = MarkdownInteractionHost(
            markdownView(markdown: markdown, taskStateScope: taskStateScope),
            size: CGSize(width: 320, height: 120)
        )
        let uncheckedSignature = try XCTUnwrap(uncheckedHost.markerSignature())

        AppMarkdownTaskCheckboxStore.set(true, for: taskID)

        let checkedHost = MarkdownInteractionHost(
            markdownView(markdown: markdown, taskStateScope: taskStateScope),
            size: CGSize(width: 320, height: 120)
        )
        let checkedSignature = try XCTUnwrap(checkedHost.markerSignature())

        XCTAssertNotEqual(checkedSignature, uncheckedSignature)
    }

    func testDeferredMarkdownTextSwapsPreviewForFullDocument() throws {
        let markdown = """
        # Full Document

        The parsed document includes content that is absent from the preview.

        - first
        - second
        """
        let host = MarkdownInteractionHost(
            DeferredAppMarkdownText(
                markdown: markdown,
                placeholder: "Preview only"
            )
            .padding(16),
            size: CGSize(width: 360, height: 220)
        )
        let previewSignature = try XCTUnwrap(host.renderedContentSignature())

        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.35))

        let fullDocumentSignature = try XCTUnwrap(host.renderedContentSignature())
        XCTAssertNotEqual(previewSignature, fullDocumentSignature)
    }

    private func markdownView(
        markdown: String,
        taskStateScope: String
    ) -> some View {
        AppMarkdownText(
            markdown: markdown,
            taskStateScope: taskStateScope
        )
        .textSelection(.enabled)
        .padding(16)
    }

    private static func taskID(
        markdown: String,
        taskStateScope: String,
        path: String
    ) -> String {
        let document = AppMarkdownDocumentCache.document(
            markdown: markdown,
            context: AppMarkdownDocumentCacheContext(
                baseURL: nil,
                inlineCodeStyle: .standard,
                composerChipMode: .none,
                taskStateScope: taskStateScope
            )
        ) {
            AppMarkdownParser().documentPreservingSource(for: markdown)
        }
        return [document.taskStateNamespace, path].filter { !$0.isEmpty }.joined(separator: ":")
    }
}

@MainActor
private final class MarkdownInteractionHost<Content: View> {
    private let controller: NSHostingController<AnyView>
    private let window: NSWindow
    private let size: CGSize

    init(
        _ view: Content,
        size: CGSize
    ) {
        self.size = size
        let rootView = AnyView(
            view
                .transaction { $0.animation = nil }
                .environment(\.locale, Locale(identifier: "en_US_POSIX"))
                .environment(\.layoutDirection, .leftToRight)
                .environment(\.colorScheme, ColorScheme.light)
                .frame(width: size.width, height: size.height, alignment: .topLeading)
                .background(Color(nsColor: .windowBackgroundColor))
        )

        controller = NSHostingController(rootView: rootView)
        controller.view.frame = CGRect(origin: .zero, size: size)
        controller.view.appearance = NSAppearance(named: .aqua)

        window = NSWindow(
            contentRect: CGRect(origin: CGPoint(x: -size.width - 1200, y: -size.height - 1200), size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .aqua)
        window.backgroundColor = .windowBackgroundColor
        window.contentViewController = controller
        flushLayout()
    }

    func markerSignature() -> Int? {
        let pixels = markerPixels(in: renderedImage())
        guard !pixels.isEmpty else {
            return nil
        }
        return pixels.reduce(0) { signature, point in
            signature &+ point.column &* 31 &+ point.row
        }
    }

    func renderedContentSignature() -> Int? {
        let pixels = contentPixels(in: renderedImage())
        guard !pixels.isEmpty else {
            return nil
        }
        return pixels.reduce(0) { signature, point in
            signature &+ point.column &* 31 &+ point.row &* 17
        }
    }

    private func flushLayout() {
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(nil)
        window.layoutIfNeeded()
        window.displayIfNeeded()
        controller.view.layoutSubtreeIfNeeded()
        controller.view.displayIfNeeded()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
    }

    private func renderedImage() -> NSBitmapImageRep {
        flushLayout()
        guard let bitmap = controller.view.bitmapImageRepForCachingDisplay(in: controller.view.bounds) else {
            XCTFail("Expected bitmap image representation")
            return NSBitmapImageRep()
        }
        controller.view.cacheDisplay(in: controller.view.bounds, to: bitmap)
        return bitmap
    }

    private func markerPixels(in image: NSBitmapImageRep) -> [PixelPoint] {
        pixelPoints(in: image, rect: CGRect(x: 8, y: 0, width: 48, height: size.height))
    }

    private func contentPixels(in image: NSBitmapImageRep) -> [PixelPoint] {
        pixelPoints(in: image, rect: CGRect(origin: .zero, size: size))
    }

    private func pixelPoints(in image: NSBitmapImageRep, rect: CGRect) -> [PixelPoint] {
        let minX = max(0, Int(rect.minX.rounded(.down)))
        let maxX = min(image.pixelsWide - 1, Int(rect.maxX.rounded(.up)))
        let minY = max(0, Int(rect.minY.rounded(.down)))
        let maxY = min(image.pixelsHigh - 1, Int(rect.maxY.rounded(.up)))
        var pixels: [PixelPoint] = []

        for row in minY...maxY {
            for column in minX...maxX {
                guard let color = image.colorAt(x: column, y: row),
                      color.alphaComponent > 0.7,
                      color.redComponent < 0.96,
                      color.greenComponent < 0.96,
                      color.blueComponent < 0.96 else {
                    continue
                }
                pixels.append(PixelPoint(column: column, row: row))
            }
        }
        return pixels
    }
}

private struct PixelPoint {
    let column: Int
    let row: Int
}
