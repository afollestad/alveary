import AppKit
import BlockInputKit
import SwiftUI
import XCTest

@testable import Alveary

/// Load-after-layout coverage for a table cell holding one image. Every snapshot of this shape
/// seeds the store before the first render, so none of them can see the transition that actually
/// happens in the app: the cell is laid out against the 16:9 pre-load placeholder, then the bitmap
/// arrives with a completely different aspect ratio and the cell has to grow to it.
@MainActor
final class AppMarkdownTableImageCellTests: XCTestCase {
    func testTableRemeasuresWhenACellImageLoads() async throws {
        let store = AppMarkdownImageStore(loader: SuspendedTableImageLoader(), diskCache: nil)
        let host = mount(store: store)
        defer { host.tearDown() }
        await host.settle()

        let placeholderHeight = host.hosting.fittingSize.height
        try preload(into: store)
        await host.settle()

        // The fitted capture is 420pt tall against a 147pt 16:9 placeholder. A cell whose body
        // SwiftUI skipped — its stored properties are identical across the load — keeps the
        // placeholder's box and squeezes the loaded bitmap into a third of it.
        XCTAssertGreaterThan(host.hosting.fittingSize.height, placeholderHeight + 200)
    }

    private static let beforeSource = "https://example.com/before.png"
    private static let afterSource = "https://example.com/after.png"

    private static let markdown = """
    | Before | After |
    | --- | --- |
    | [![Before video: cart toolbar detent visibility](\(beforeSource))](<https://example.com/before.mp4>) | \
    [![After video: cart toolbar detent visibility](\(afterSource))](<https://example.com/after.mp4>) |
    | [Build #26 (90dc1b57)](<https://example.com/a>) | [Build #99199 (7ce56057)](<https://example.com/b>) |
    """

    private func preload(into store: AppMarkdownImageStore) throws {
        let data = try appMarkdownTestPNGData(width: 720, height: 1_565)
        for source in [Self.beforeSource, Self.afterSource] {
            store.preloadForTesting(source: source, image: try XCTUnwrap(NSImage(data: data)))
        }
    }

    private func mount(store: AppMarkdownImageStore) -> Host {
        let size = NSRect(x: 0, y: 0, width: 500, height: 900)
        let hosting = NSHostingView(
            rootView: AnyView(
                AppMarkdownText(markdown: Self.markdown)
                    .environment(\.appMarkdownImageStore, store)
                    .frame(width: 500, alignment: .leading)
            )
        )
        hosting.frame = size
        let window = NSWindow(contentRect: size, styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = hosting
        hosting.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        return Host(window: window, hosting: hosting)
    }

    @MainActor
    private struct Host {
        let window: NSWindow
        let hosting: NSHostingView<AnyView>

        func settle() async {
            for _ in 0..<40 {
                hosting.layoutSubtreeIfNeeded()
                window.displayIfNeeded()
                try? await Task.sleep(nanoseconds: 5_000_000)
            }
        }

        func tearDown() {
            window.contentView = nil
        }
    }
}

/// Never resolves, so the first layout runs against the unloaded placeholder deterministically.
private struct SuspendedTableImageLoader: BlockInputImageLoading {
    func loadImage(_ request: BlockInputImageLoadRequest) async throws -> BlockInputLoadedImage {
        try await Task.sleep(nanoseconds: 60_000_000_000)
        throw CancellationError()
    }
}
