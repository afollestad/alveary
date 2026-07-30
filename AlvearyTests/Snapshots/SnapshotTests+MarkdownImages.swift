import AppKit
import BlockInputKit
import SwiftUI
import XCTest

@testable import Alveary

extension SnapshotTests {
    func testMarkdownRemoteImages() throws {
        let fixture = try markdownImagesFixture()
        assertMacSnapshot(
            fixture,
            size: CGSize(width: 460, height: 360),
            named: "markdown_remote_images"
        )
    }

    func testMarkdownRemoteImagesDark() throws {
        let fixture = try markdownImagesFixture()
        assertMacSnapshot(
            fixture,
            size: CGSize(width: 460, height: 360),
            named: "markdown_remote_images_dark",
            colorScheme: .dark
        )
    }

    /// One fixture covers the three markdown image states: an inline badge sharing
    /// a line with bold text (loaded), a standalone image block (loaded), and an
    /// inline image still loading, which keeps showing its alt text.
    private func markdownImagesFixture() throws -> some View {
        let store = AppMarkdownImageStore(loader: SnapshotUnavailableImageLoader(), diskCache: nil)
        let badgePNG = try appMarkdownTestPNGData(width: 40, height: 20, color: .systemOrange)
        let photoPNG = try appMarkdownTestPNGData(width: 240, height: 120, color: .systemTeal)
        if let badge = NSImage(data: badgePNG) {
            store.preloadForTesting(source: "https://example.com/p1.png", image: badge)
        }
        if let photo = NSImage(data: photoPNG) {
            store.preloadForTesting(source: "https://example.com/photo.png", image: photo)
        }
        let markdown = """
        **![P1](https://example.com/p1.png) Add the required commit trailer**

        A standalone image renders as a block:

        ![Screenshot](https://example.com/photo.png)

        Pending ![Pending badge](https://example.com/pending.png) shows alt text.
        """
        return AppMarkdownText(markdown: markdown)
            .environment(\.appMarkdownImageStore, store)
            .padding(16)
    }
}

/// Never resolves, so unseeded sources stay in the alt-text state deterministically.
private struct SnapshotUnavailableImageLoader: BlockInputImageLoading {
    func loadImage(_ request: BlockInputImageLoadRequest) async throws -> BlockInputLoadedImage {
        try await Task.sleep(nanoseconds: 60_000_000_000)
        throw CancellationError()
    }
}
