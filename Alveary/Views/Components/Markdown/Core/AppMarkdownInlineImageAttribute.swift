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

    /// How far an inline image dips below the text baseline so it centers on the
    /// cap-height midline, matching GitHub's `vertical-align: middle`. Shared by
    /// both renderers so SwiftUI baseline offsets and AppKit attachment bounds agree.
    static func baselineDrop(forDisplayHeight height: CGFloat, capHeight: CGFloat) -> CGFloat {
        max(0, (height - capHeight) / 2)
    }

    /// Declared dimensions win; otherwise the loaded bitmap's natural point size
    /// drives rendering. Shared by the SwiftUI and AppKit renderers so both size
    /// the same image identically.
    func displaySize(forNaturalSize naturalSize: CGSize) -> CGSize {
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
