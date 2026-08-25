import BlockInputKit
import SwiftUI

/// Renders one standalone markdown image block: placeholder chrome while
/// loading, the bitmap once it arrives, and an unavailable label on failure.
/// Clicking a loaded image opens the host's image preview modal when an
/// `appMarkdownImagePreviewAction` is injected, else its resolved remote URL.
struct AppMarkdownImageBlockView: View {
    let block: AppMarkdownImageBlock
    var baseURL: URL?
    /// The `[![alt](src)](href)` wrapper link, when the image carried one. A click follows it
    /// instead of opening the preview modal — the author pointed the image somewhere on purpose,
    /// and for a before/after table that destination is the demo video the thumbnail stands in for.
    var linkURL: URL?
    /// Caps the rendered box, for hosts that must fit the image into space they own — a table cell
    /// sizes its column from this. Nil keeps the standalone-block behavior of wrapping the bitmap
    /// at its natural size.
    var maxDisplaySize: CGSize?

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
        if let nsImage = store.image(forSource: block.image.source, baseURL: baseURL) {
            loadedImage(nsImage)
        } else if store.hasFailed(source: block.image.source, baseURL: baseURL) {
            placeholder(text: "Image unavailable")
        } else {
            placeholder(text: nil)
        }
    }

    private func loadedImage(_ nsImage: NSImage) -> some View {
        let displaySize = displaySize(constrainedTo: .greatestFiniteMagnitude)
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
        // Sized from the same resolved dimensions as the loaded branch, so a
        // local image's placeholder already occupies the box its bitmap will.
        let displaySize = displaySize(constrainedTo: AppMarkdownImageBlockView.placeholderWidth)
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

    /// `maxDisplaySize` wins when a host set one; otherwise the branch's own fallback width
    /// applies, which is what keeps a standalone block wrapping its bitmap.
    private func displaySize(constrainedTo fallbackWidth: CGFloat) -> CGSize {
        guard let maxDisplaySize else {
            return appMarkdownImageDisplaySize(for: resolvedImage, constrainedTo: fallbackWidth)
        }
        return appMarkdownImageDisplaySize(for: resolvedImage, constrainedTo: maxDisplaySize)
    }

    /// Declared dimensions win; otherwise the store's resolved pixel size drives
    /// display sizing. Deliberately not `nsImage.size`, which reports points and
    /// would size a DPI-tagged source differently from the AppKit renderer and
    /// from an HTML `width`/`height` on the same image.
    private var resolvedImage: BlockInputImage {
        block.image.appMarkdownResolved(
            naturalSize: store.naturalSize(for: block.image, baseURL: baseURL)
        )
    }

    private func openImage() {
        if let linkURL {
            openURL(linkURL)
            return
        }
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
