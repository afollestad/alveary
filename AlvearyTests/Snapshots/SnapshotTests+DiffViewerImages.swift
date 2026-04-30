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
                loadImage: { _ in try Self.imageOutput(width: 180, height: 110, color: CGColor(red: 0.16, green: 0.45, blue: 0.78, alpha: 1)) },
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
                loadImage: { _ in try Self.imageOutput(width: 160, height: 120, color: CGColor(red: 0.70, green: 0.16, blue: 0.16, alpha: 1)) },
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
                loadImage: { version in
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
                source: .head(path: "Assets/logo.png"),
                side: .old,
                identityPrefix: "abc123",
                fileIdentity: "Assets/logo.png",
                fileExtension: "png",
                needsContentHash: false
            ),
            new: DiffImageVersion(
                source: .worktree(path: "Assets/logo.png"),
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
                loadImage: { _ in
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
                source: .worktree(path: "Assets/broken.png"),
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
                loadImage: { _ in throw DiffImagePreviewLoaderError.unsupportedImage },
                openImage: { _ in }
            )
            .padding(12),
            size: CGSize(width: 500, height: 220),
            named: "diff_viewer_image_preview_failed_slots"
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
                loadImage: { _ in throw DiffImagePreviewLoaderError.unsupportedImage },
                openImage: { _ in }
            ),
            size: CGSize(width: 600, height: 420),
            named: "diff_viewer_selected_diff_failure_message"
        )
    }

    private static func imageVersion(side: DiffImageVersion.Side, path: String) -> DiffImageVersion {
        DiffImageVersion(
            source: side == .old ? .head(path: path) : .worktree(path: path),
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
