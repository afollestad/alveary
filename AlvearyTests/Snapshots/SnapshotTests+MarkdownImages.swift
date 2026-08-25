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
            size: CGSize(width: 460, height: 560),
            named: "markdown_remote_images"
        )
    }

    func testMarkdownRemoteImagesDark() throws {
        let fixture = try markdownImagesFixture()
        assertMacSnapshot(
            fixture,
            size: CGSize(width: 460, height: 560),
            named: "markdown_remote_images_dark",
            colorScheme: .dark
        )
    }

    func testMarkdownTableImages() throws {
        let fixture = try markdownTableImagesFixture()
        assertMacSnapshot(
            fixture,
            size: CGSize(width: 500, height: 560),
            named: "markdown_table_images"
        )
    }

    func testMarkdownTableImagesDark() throws {
        let fixture = try markdownTableImagesFixture()
        assertMacSnapshot(
            fixture,
            size: CGSize(width: 500, height: 560),
            named: "markdown_table_images_dark",
            colorScheme: .dark
        )
    }

    /// One fixture covers the markdown image states: an inline badge sharing a
    /// line with bold text (loaded), a standalone image block (loaded), an inline
    /// image still loading (keeps its alt text), and a standalone block still
    /// loading (placeholder with the centered working indicator).
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

        ![Loading block](https://example.com/loading.png)
        """
        return AppMarkdownText(markdown: markdown)
            .environment(\.appMarkdownImageStore, store)
            .padding(16)
    }

    /// A before/after comparison table whose image cells are portrait phone captures — the shape
    /// that rendered its thumbnails at natural size, pushing the table into horizontal overflow and
    /// reserving half an image height of blank space above each one.
    ///
    /// The alt text is deliberately long. Should a cell ever fall back to inline rendering, the
    /// column widens to that whole unwrapped line rather than to the image, which is the visible
    /// difference between the two paths once the bitmap has loaded.
    private func markdownTableImagesFixture() throws -> some View {
        let store = AppMarkdownImageStore(loader: SnapshotUnavailableImageLoader(), diskCache: nil)
        let capturePNG = try appMarkdownTestPNGData(width: 720, height: 1_565, color: .systemIndigo)
        for source in ["https://example.com/before.png", "https://example.com/after.png"] {
            if let capture = NSImage(data: capturePNG) {
                store.preloadForTesting(source: source, image: capture)
            }
        }
        let markdown = """
        | Before | After |
        | --- | --- |
        | [![Before video: Brand Profile cart toolbar detent visibility]\
        (https://example.com/before.png)](<https://example.com/before.mp4>) | \
        [![After video: Brand Profile cart toolbar detent visibility]\
        (https://example.com/after.png)](<https://example.com/after.mp4>) |
        | [Build #26 (90dc1b57)](<https://example.com/a>) | [Build #99199 (7ce56057)](<https://example.com/b>) |
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
