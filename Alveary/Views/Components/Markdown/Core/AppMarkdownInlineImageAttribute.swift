import BlockInputKit
import Foundation

/// Payload for one remote image that shares a line with text and therefore
/// renders inline within the text run instead of as a standalone image block.
struct AppMarkdownInlineImageInfo: Hashable, Sendable, Codable {
    /// Absolute `http`/`https` source; inline rendering is remote-only, so no
    /// base-URL resolution is needed at render time.
    let source: String
    let altText: String
    /// Declared `<img>` dimensions in points, when present.
    let width: Int?
    let height: Int?

    init(image: BlockInputImage) {
        source = image.source
        altText = image.altText
        width = image.width
        height = image.height
    }

    var accessibilityLabel: String {
        altText.isEmpty ? source : altText
    }

    /// The image this run stands in for, for the store calls and sizing helpers that take one.
    var image: BlockInputImage {
        BlockInputImage(source: source, altText: altText, width: width, height: height)
    }

    /// How far an inline image dips below the text baseline so it centers on the
    /// cap-height midline, matching GitHub's `vertical-align: middle`. Shared by
    /// both renderers so SwiftUI baseline offsets and AppKit attachment bounds agree.
    ///
    /// **Clamped to one cap-height.** The drop is reserved as descent *in addition to* the
    /// image's full ascent, so an unclamped drop on a picture-sized image shows up as half that
    /// image's height in blank space above it. Badge-sized images are under the clamp and keep
    /// centering exactly; anything taller sits essentially on the baseline instead.
    static func baselineDrop(forDisplayHeight height: CGFloat, capHeight: CGFloat) -> CGFloat {
        min(max(0, (height - capHeight) / 2), max(0, capHeight))
    }

    /// Declared dimensions win; otherwise the loaded bitmap's natural point size
    /// drives rendering. Shared by the SwiftUI and AppKit renderers so both size
    /// the same image identically. The result fits inside
    /// `appMarkdownInlineImageMaxSize` — an image sharing a line with text cannot widen its
    /// container to its own natural size.
    func displaySize(forNaturalSize naturalSize: CGSize) -> CGSize {
        appMarkdownImageSize(
            unconstrainedDisplaySize(forNaturalSize: naturalSize),
            fittingWithin: appMarkdownInlineImageMaxSize
        )
    }

    private func unconstrainedDisplaySize(forNaturalSize naturalSize: CGSize) -> CGSize {
        let aspectRatio = naturalSize.width / max(naturalSize.height, 1)
        switch (width.map(CGFloat.init), height.map(CGFloat.init)) {
        case let (width?, height?):
            return CGSize(width: width, height: height)
        case let (width?, nil):
            return CGSize(width: width, height: width / max(aspectRatio, 0.01))
        case let (nil, height?):
            return CGSize(width: height * aspectRatio, height: height)
        case (nil, nil):
            return naturalSize
        }
    }
}

/// One image occupying an entire table cell, plus the `[![alt](src)](href)` wrapper link when the
/// author wrapped it.
///
/// GitHub fits such an image to its column. Rendering it inline instead sizes it against the text
/// run, which both widens the column past the pane and — through the badge-centering baseline drop
/// — reserves blank space above it, so both renderers branch to a fitted image block here.
///
/// Every store call for this image passes a `nil` base URL, because the parser classified it inline
/// and both renderers kick inline loads under that key; anything else would split the entry.
struct AppMarkdownCellImage: Equatable {
    let image: BlockInputImage
    let link: URL?
}

extension AttributedString {
    /// Non-nil when this content carries exactly one inline image and no other visible text, which
    /// is what makes a table cell an image cell. Styling inside the alt text can split one image
    /// span across several runs, so equal infos coalesce rather than disqualifying the cell.
    var appMarkdownSoleInlineImage: AppMarkdownCellImage? {
        var found: AppMarkdownInlineImageInfo?
        var link: URL?
        for run in runs {
            guard let info = run[AppMarkdownInlineImageAttribute.self] else {
                guard String(self[run.range].characters).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    return nil
                }
                continue
            }
            if let found, found != info {
                return nil
            }
            found = info
            link = link ?? run.link
        }
        guard let found else {
            return nil
        }
        return AppMarkdownCellImage(image: found.image, link: link)
    }
}

extension AttributedStringProtocol {
    /// Every inline image this content carries, in run order.
    ///
    /// Layout caches digest these to decide whether their measurements still hold: an inline image
    /// is alt text before its bitmap arrives and a picture after, and nothing else about a table's
    /// grid — column count, subview count — changes across that transition. A cell holding only an
    /// image is an inline run too, so this reaches those as well as images sharing a line with text.
    var appMarkdownInlineImages: [BlockInputImage] {
        var images: [BlockInputImage] = []
        for run in runs[AppMarkdownInlineImageAttribute.self] {
            guard let info = run.0 else {
                continue
            }
            images.append(info.image)
        }
        return images
    }
}

extension AppMarkdownDocument {
    /// Sources of every inline-image run across the document's markdown fragments,
    /// used to decide whether a finished load affects a rendered view.
    var inlineImageSources: Set<String> {
        var sources: Set<String> = []
        for block in blocks {
            guard case let .markdown(content) = block else {
                continue
            }
            for run in content.runs[AppMarkdownInlineImageAttribute.self] {
                if let info = run.0 {
                    sources.insert(info.source)
                }
            }
        }
        return sources
    }
}

/// AttributedString key carried by the alt-text run of an inline image. Renderers
/// that support inline images replace the run with the loaded bitmap; renderers
/// that do not simply show the alt text, which is also the pre-load state.
enum AppMarkdownInlineImageAttribute: CodableAttributedStringKey {
    typealias Value = AppMarkdownInlineImageInfo
    static let name = "AppMarkdownInlineImage"
}

extension AttributeScopes {
    struct AppMarkdownAttributes: AttributeScope {
        let inlineImage: AppMarkdownInlineImageAttribute
        let foundation: FoundationAttributes
    }

    var appMarkdown: AppMarkdownAttributes.Type {
        AppMarkdownAttributes.self
    }
}

extension AttributeDynamicLookup {
    subscript<T: AttributedStringKey>(
        dynamicMember keyPath: KeyPath<AttributeScopes.AppMarkdownAttributes, T>
    ) -> T {
        self[T.self]
    }
}
