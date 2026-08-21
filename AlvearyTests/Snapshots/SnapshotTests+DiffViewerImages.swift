import CoreGraphics
import SwiftUI
import XCTest

@testable import Alveary

@MainActor
extension SnapshotTests {
    func testDiffViewerImagePreviewLoadedNewImage() throws {
        let preview = DiffImagePreview(
            old: nil,
            new: Self.imageVersion(side: .new, path: "Assets/new-photo.jpg")
        )

        assertMacSnapshot(
            DiffImagePreviewSlots(
                preview: preview,
                loadImage: { _, _ in try Self.imageOutput(width: 180, height: 110, color: CGColor(red: 0.16, green: 0.45, blue: 0.78, alpha: 1)) },
                openImage: { _ in }
            )
            .padding(12),
            size: CGSize(width: 500, height: 220),
            named: "diff_viewer_image_preview_loaded_new"
        )
    }

    func testDiffViewerImagePreviewLoadedDeletedImage() throws {
        let preview = DiffImagePreview(
            old: Self.imageVersion(side: .old, path: "Assets/removed-photo.jpg"),
            new: nil
        )

        assertMacSnapshot(
            DiffImagePreviewSlots(
                preview: preview,
                loadImage: { _, _ in try Self.imageOutput(width: 160, height: 120, color: CGColor(red: 0.70, green: 0.16, blue: 0.16, alpha: 1)) },
                openImage: { _ in }
            )
            .padding(12),
            size: CGSize(width: 500, height: 220),
            named: "diff_viewer_image_preview_loaded_deleted"
        )
    }

    func testDiffViewerImagePreviewLoadedSplitSlots() throws {
        let preview = DiffImagePreview(
            old: Self.imageVersion(side: .old, path: "Assets/photo.jpg"),
            new: Self.imageVersion(side: .new, path: "Assets/photo.jpg")
        )

        assertMacSnapshot(
            DiffImagePreviewSlots(
                preview: preview,
                loadImage: { version, _ in
                    switch version.side {
                    case .old:
                        return try Self.imageOutput(width: 130, height: 95, color: CGColor(red: 0.70, green: 0.16, blue: 0.16, alpha: 1))
                    case .new:
                        return try Self.imageOutput(width: 130, height: 95, color: CGColor(red: 0.12, green: 0.55, blue: 0.24, alpha: 1))
                    }
                },
                openImage: { _ in }
            )
            .padding(12),
            size: CGSize(width: 500, height: 220),
            named: "diff_viewer_image_preview_loaded_split"
        )
    }

    func testDiffViewerImagePreviewLoadingSlots() {
        let preview = DiffImagePreview(
            old: DiffImageVersion(
                source: .git(.head(path: "Assets/logo.png")),
                side: .old,
                identityPrefix: "abc123",
                fileIdentity: "Assets/logo.png",
                fileExtension: "png",
                needsContentHash: false
            ),
            new: DiffImageVersion(
                source: .git(.worktree(path: "Assets/logo.png")),
                side: .new,
                identityPrefix: "abc123-worktree",
                fileIdentity: "Assets/logo.png",
                fileExtension: "png",
                needsContentHash: true
            )
        )

        assertMacSnapshot(
            DiffImagePreviewSlots(
                preview: preview,
                loadImage: { _, _ in
                    try await Task.sleep(for: .seconds(30))
                    throw CancellationError()
                },
                openImage: { _ in }
            )
            .padding(12),
            size: CGSize(width: 500, height: 220),
            named: "diff_viewer_image_preview_loading_slots"
        )
    }

    func testDiffViewerImagePreviewFailedSlotsFallBackToBinaryCallout() {
        let preview = DiffImagePreview(
            old: nil,
            new: DiffImageVersion(
                source: .git(.worktree(path: "Assets/broken.png")),
                side: .new,
                identityPrefix: "abc123-worktree",
                fileIdentity: "Assets/broken.png",
                fileExtension: "png",
                needsContentHash: true
            )
        )

        assertMacSnapshot(
            DiffImagePreviewSlots(
                preview: preview,
                loadImage: { _, _ in throw DiffImagePreviewLoaderError.unsupportedImage },
                openImage: { _ in }
            )
            .padding(12),
            size: CGSize(width: 500, height: 220),
            named: "diff_viewer_image_preview_failed_slots"
        )
    }

    /// Git LFS holds large files by design, so a size-gated image offers itself rather than
    /// downloading on scroll.
    func testDiffViewerImagePreviewLargeImageAwaitsConfirmation() {
        let preview = DiffImagePreview(
            old: nil,
            new: Self.remoteImageVersion(path: "assets/hero.png", byteSize: 42 * 1024 * 1024)
        )

        assertMacSnapshot(
            DiffImagePreviewSlots(
                preview: preview,
                loadImage: { version, _ in throw DiffImageBlobTooLargeError(byteSize: version.byteSize) },
                openImage: { _ in }
            )
            .padding(12),
            size: CGSize(width: 500, height: 220),
            named: "diff_viewer_image_preview_awaits_confirmation"
        )
    }

    func testDiffViewerImagePreviewPastTheHardCapOffersNoLoadButton() {
        let oversized = DiffImagePreviewSupport.remoteMaxSourceBytes + 1
        let preview = DiffImagePreview(
            old: nil,
            new: Self.remoteImageVersion(path: "assets/master.psd.png", byteSize: oversized)
        )

        assertMacSnapshot(
            DiffImagePreviewSlots(
                preview: preview,
                loadImage: { version, _ in throw DiffImageBlobTooLargeError(byteSize: version.byteSize) },
                openImage: { _ in }
            )
            .padding(12),
            size: CGSize(width: 500, height: 220),
            named: "diff_viewer_image_preview_too_large"
        )
    }

    func testDiffViewerSelectedDiffFailureMessage() {
        let file = FileStatus(path: "H05A4356.jpg", originalPath: nil, status: .untracked, isStaged: false)

        assertMacSnapshot(
            DiffViewerPreviewSection(
                selectedFile: file,
                selectedFileCount: 1,
                parsedDiff: nil,
                imagePreview: nil,
                rawDiffContent: "",
                errorMessage: "Untracked file is too large to preview (>100KB)",
                isPending: false,
                isLoading: false,
                fileDisplayName: { $0.path },
                statusTitle: { $0.rawValue.capitalized },
                diffPreviewIdentity: { $0.id },
                loadImage: { _, _ in throw DiffImagePreviewLoaderError.unsupportedImage },
                openImage: { _ in }
            ),
            size: CGSize(width: 600, height: 420),
            named: "diff_viewer_selected_diff_failure_message"
        )
    }

    /// A pull request image, whose bytes live on GitHub rather than in a checkout.
    private static func remoteImageVersion(path: String, byteSize: Int) -> DiffImageVersion {
        DiffImageVersion(
            source: .gitHub(
                GitHubImageBlobSource(
                    owner: "octo",
                    repo: "demo",
                    path: path,
                    storage: .lfs(oid: String(repeating: "a", count: 64), byteSize: byteSize)
                )
            ),
            side: .new,
            identityPrefix: "lfs-\(String(repeating: "a", count: 64))",
            fileIdentity: path,
            fileExtension: "png",
            needsContentHash: false,
            byteSize: byteSize
        )
    }

    /// A portrait screenshot letterboxed into the row's bounded box, which is the shape that used to
    /// stretch the row to its own 2532pt height.
    func testDiffViewerImageRowFitsAPortraitScreenshot() throws {
        let path = "snapshots/LOCAL_CASH_happy.png"
        let raw = """
        diff --git a/\(path) b/\(path)
        deleted file mode 100644
        index abbe130..0000000
        Binary files a/\(path) and /dev/null differ
        """
        let files = DiffParser.parse(raw)
        let fileID = FlattenedDiffPreviewRows.fileCollapseID(for: files[0], fileIndex: 0)

        assertMacSnapshot(
            FlattenedDiffPreview(
                files: files,
                imagePreviews: [fileID: DiffImagePreview(old: Self.imageVersion(side: .old, path: path), new: nil)],
                showsFileHeaders: true,
                loadImage: { _, _ in
                    try Self.imageOutput(width: 585, height: 1_266, color: CGColor(red: 0.12, green: 0.35, blue: 0.62, alpha: 1))
                },
                openImage: { _ in }
            ),
            size: CGSize(width: 620, height: 520),
            named: "diff_viewer_image_row_portrait"
        )
    }

    private static func imageVersion(side: DiffImageVersion.Side, path: String) -> DiffImageVersion {
        DiffImageVersion(
            source: side == .old ? .git(.head(path: path)) : .git(.worktree(path: path)),
            side: side,
            identityPrefix: side == .old ? "abc123" : "abc123-worktree",
            fileIdentity: path,
            fileExtension: "jpg",
            needsContentHash: side == .new
        )
    }

    private static func imageOutput(width: Int, height: Int, color: CGColor) throws -> DiffImagePreviewOutput {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw DiffImagePreviewLoaderError.unsupportedImage
        }

        context.setFillColor(CGColor(gray: 0.04, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.setFillColor(color)
        context.fill(CGRect(x: width / 5, y: height / 4, width: width * 3 / 5, height: height / 2))

        guard let image = context.makeImage() else {
            throw DiffImagePreviewLoaderError.unsupportedImage
        }
        return DiffImagePreviewOutput(image: image, pixelSize: CGSize(width: width, height: height))
    }
}
