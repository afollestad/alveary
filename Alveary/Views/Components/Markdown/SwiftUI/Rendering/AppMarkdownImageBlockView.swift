import BlockInputKit
import SwiftUI

/// Renders one standalone markdown image block: placeholder chrome while
/// loading, the bitmap once it arrives, and an unavailable label on failure.
/// Clicking a loaded image opens the host's image preview modal when an
/// `appMarkdownImagePreviewAction` is injected, else its resolved remote URL.
struct AppMarkdownImageBlockView: View {
    let block: AppMarkdownImageBlock
    var baseURL: URL?

    @Environment(\.appMarkdownImageStore) private var environmentStore
    @Environment(\.appMarkdownImagePreviewAction) private var imagePreviewAction
    @Environment(\.openURL) private var openURL

    var body: some View {
        content
            .task(id: block.image.source) {
                store.ensureLoad(for: block.image, baseURL: baseURL)
            }
            .accessibilityLabel(block.accessibilityLabel)
            .help(block.accessibilityLabel)
    }

    @ViewBuilder
    private var content: some View {
        if let nsImage = store.image(forSource: block.image.source) {
            loadedImage(nsImage)
        } else if store.hasFailed(source: block.image.source) {
            placeholder(text: "Image unavailable")
        } else {
            placeholder(text: nil)
        }
    }

    private func loadedImage(_ nsImage: NSImage) -> some View {
        let displaySize = appMarkdownImageDisplaySize(
            for: resolvedImage(naturalSize: nsImage.size),
            constrainedTo: .greatestFiniteMagnitude
        )
        return Button {
            openImage()
        } label: {
            // Clip before the max-size frame: the frame can be wider than the
            // fitted image (it expands to the available width), and a clip on
            // the frame leaves the image's trailing corners square.
            Image(nsImage: nsImage)
                .resizable()
                .scaledToFit()
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .frame(maxWidth: displaySize.width, maxHeight: displaySize.height, alignment: .leading)
        }
        .buttonStyle(.plain)
    }

    private func placeholder(text: String?) -> some View {
        let displaySize = appMarkdownImageDisplaySize(
            for: block.image,
            constrainedTo: AppMarkdownImageBlockView.placeholderWidth
        )
        return RoundedRectangle(cornerRadius: 8)
            .fill(Color(nsColor: .quaternaryLabelColor).opacity(0.26))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color(nsColor: .separatorColor).opacity(0.35))
            )
            .overlay {
                if let text {
                    Text(text)
                        .foregroundStyle(.secondary)
                } else {
                    // Centered working indicator while the network load runs.
                    StatusIndicatorSpinner(color: .secondary, diameter: 16, lineWidth: 2)
                }
            }
            .frame(width: displaySize.width, height: displaySize.height, alignment: .leading)
    }

    /// Declared dimensions win; otherwise the natural size drives display sizing.
    private func resolvedImage(naturalSize: CGSize) -> BlockInputImage {
        guard block.image.width == nil, block.image.height == nil else {
            return block.image
        }
        return BlockInputImage(
            source: block.image.source,
            altText: block.image.altText,
            width: Int(naturalSize.width.rounded()),
            height: Int(naturalSize.height.rounded()),
            sourceStyle: block.image.sourceStyle
        )
    }

    private func openImage() {
        if let imagePreviewAction {
            imagePreviewAction(block.image, baseURL: baseURL)
            return
        }
        guard let url = AppMarkdownImageSourceResolver.resolvedURL(for: block.image.source, baseURL: baseURL),
              !url.isFileURL else {
            return
        }
        openURL(url)
    }

    private var store: AppMarkdownImageStore {
        environmentStore ?? .shared
    }

    private static let placeholderWidth: CGFloat = 320
}
