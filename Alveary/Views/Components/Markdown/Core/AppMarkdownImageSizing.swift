import BlockInputKit
import Foundation

// Display sizing for markdown images, shared by the SwiftUI renderer, the AppKit renderer, and the
// AppKit measurer. Every surface resolves through here so a measured box and a drawn one cannot
// disagree; `AppMarkdownImages.swift` next door owns finding the images in the source.

let appMarkdownImageDefaultAspectRatio: CGFloat = 16.0 / 9.0
let appMarkdownImageMinimumDisplayDimension: CGFloat = 24

/// The box a table cell's lone image fits inside, aspect preserved. The cell's image *is* its
/// column width, so the width caps a two-column before/after table to something the pull request
/// pane can show without horizontal scrolling, and the height keeps a portrait phone capture from
/// turning one row into two screens of scrolling.
let appMarkdownTableImageCellMaxSize = CGSize(width: 260, height: 420)

/// The box an image that shares a line with text fits inside. Such an image is a badge by intent;
/// an uncapped one sizes at its full natural size and widens whatever measured it — a 720x1565
/// screenshot inside a table row is what first exposed this.
let appMarkdownInlineImageMaxSize = CGSize(width: 320, height: 320)

func appMarkdownImageDisplaySize(
    for image: BlockInputImage,
    constrainedTo width: CGFloat,
    defaultAspectRatio: CGFloat = appMarkdownImageDefaultAspectRatio
) -> CGSize {
    let availableWidth = max(width, appMarkdownImageMinimumDisplayDimension)
    let aspectRatio = max(defaultAspectRatio, 0.01)
    let sourceWidth: CGFloat
    let sourceHeight: CGFloat

    switch (image.width, image.height) {
    case let (width?, height?):
        sourceWidth = CGFloat(width)
        sourceHeight = CGFloat(height)
    case let (width?, nil):
        sourceWidth = CGFloat(width)
        sourceHeight = sourceWidth / aspectRatio
    case let (nil, height?):
        sourceHeight = CGFloat(height)
        sourceWidth = sourceHeight * aspectRatio
    case (nil, nil):
        sourceWidth = availableWidth
        sourceHeight = availableWidth / aspectRatio
    }

    return appMarkdownConstrainedImageSize(
        width: sourceWidth,
        height: sourceHeight,
        availableWidth: availableWidth
    )
}

/// Width-and-height variant of `appMarkdownImageDisplaySize(for:constrainedTo:)`. The width pass
/// runs first so a declared or natural size resolves identically either way, then the result is
/// scaled to fit the remaining height.
func appMarkdownImageDisplaySize(
    for image: BlockInputImage,
    constrainedTo maxSize: CGSize,
    defaultAspectRatio: CGFloat = appMarkdownImageDefaultAspectRatio
) -> CGSize {
    appMarkdownImageSize(
        appMarkdownImageDisplaySize(
            for: image,
            constrainedTo: maxSize.width,
            defaultAspectRatio: defaultAspectRatio
        ),
        fittingWithin: maxSize
    )
}

/// Scales `size` down until it fits inside `maxSize`, preserving aspect ratio. A size that already
/// fits comes back unchanged, so a badge-sized image is never enlarged to the cap.
func appMarkdownImageSize(_ size: CGSize, fittingWithin maxSize: CGSize) -> CGSize {
    let safeWidth = max(size.width, 1)
    let safeHeight = max(size.height, 1)
    let scale = min(1, min(maxSize.width / safeWidth, maxSize.height / safeHeight))
    // Returned verbatim rather than floored at the minimum display dimension: a 40x20 badge that
    // already fits must keep its exact declared box, not be stretched to a square minimum.
    guard scale < 1 else {
        return size
    }
    return CGSize(
        width: ceil(max(appMarkdownImageMinimumDisplayDimension, safeWidth * scale)),
        height: ceil(max(appMarkdownImageMinimumDisplayDimension, safeHeight * scale))
    )
}

extension BlockInputImage {
    /// Fills in missing dimensions from the image's real pixel size so display
    /// sizing wraps the bitmap instead of falling back to
    /// `appMarkdownImageDefaultAspectRatio`. Declared HTML dimensions win — an
    /// author who sized an image meant it. Both renderers and the AppKit
    /// measurer resolve through this, or a measured height stops matching a
    /// drawn one.
    func appMarkdownResolved(naturalSize: CGSize?) -> BlockInputImage {
        guard let naturalSize,
              naturalSize.width > 0,
              naturalSize.height > 0,
              width == nil,
              height == nil else {
            return self
        }
        return BlockInputImage(
            source: source,
            altText: altText,
            width: Int(naturalSize.width.rounded()),
            height: Int(naturalSize.height.rounded()),
            sourceStyle: sourceStyle
        )
    }
}

private func appMarkdownConstrainedImageSize(
    width: CGFloat,
    height: CGFloat,
    availableWidth: CGFloat
) -> CGSize {
    let safeWidth = max(width, appMarkdownImageMinimumDisplayDimension)
    let safeHeight = max(height, appMarkdownImageMinimumDisplayDimension)
    let scale = min(1, availableWidth / safeWidth)
    return CGSize(
        width: ceil(max(appMarkdownImageMinimumDisplayDimension, safeWidth * scale)),
        height: ceil(max(appMarkdownImageMinimumDisplayDimension, safeHeight * scale))
    )
}
