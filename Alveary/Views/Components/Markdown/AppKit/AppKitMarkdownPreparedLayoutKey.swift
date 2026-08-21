@preconcurrency import AppKit
import Foundation

/// Bumped whenever AppKit markdown layout changes shape, so measurements cached by an earlier
/// build of the renderer cannot be reused. Version 4 added the `<details>` disclosure block, and
/// version 5 gave `<section>` the same block plus dropped the HTML tags markdown cannot express.
private let rendererVersion = 5

struct AppKitMarkdownLayoutMeasurement: Equatable {
    let contentHeight: CGFloat
    let naturalContentWidth: CGFloat
    let fallbackRequired: Bool
}

/// Cache identity for prepared markdown measurements. Keep this aligned with
/// every input that can change text layout or bubble chrome height.
struct AppKitMarkdownPreparedLayoutKey: Hashable {
    let rowID: String?
    let markdown: String
    let role: String
    let availableWidth: CGFloat
    let bubbleMaxWidth: CGFloat
    let typography: AppKitMarkdownTypographySignature
    let inlineCodeStyle: AppMarkdownInlineCodeStyle
    let appearanceName: String
    let isExpanded: Bool
    let showsRetry: Bool
    // Inline images swap from alt text to attachments as they load, changing
    // measured heights; the digest keeps pre-load measurements from sticking.
    let inlineImageFingerprint: String
    // A `<details>` toggle changes a row's height without changing anything else in this key, so
    // a cached measurement would outlive the collapse it should have shrunk with. The store's
    // counter retires every entry on any toggle; toggles are rare, and the cache is a bounded LRU.
    let detailsExpansionGeneration: Int
    let rendererVersion: Int

    init(
        rowID: String?,
        markdown: String,
        role: String,
        availableWidth: CGFloat,
        bubbleMaxWidth: CGFloat,
        typography: AppKitMarkdownTypography,
        inlineCodeStyle: AppMarkdownInlineCodeStyle,
        appearanceName: String,
        isExpanded: Bool,
        showsRetry: Bool,
        inlineImageFingerprint: String = "",
        detailsExpansionGeneration: Int = AppMarkdownDetailsExpansionStore.generation,
        rendererVersion: Int = AppKitMarkdownRendererVersion.current
    ) {
        self.rowID = rowID
        self.markdown = markdown
        self.role = role
        self.availableWidth = availableWidth
        self.bubbleMaxWidth = bubbleMaxWidth
        self.typography = AppKitMarkdownTypographySignature(typography)
        self.inlineCodeStyle = inlineCodeStyle
        self.appearanceName = appearanceName
        self.isExpanded = isExpanded
        self.showsRetry = showsRetry
        self.inlineImageFingerprint = inlineImageFingerprint
        self.detailsExpansionGeneration = detailsExpansionGeneration
        self.rendererVersion = rendererVersion
    }
}

struct AppKitMarkdownTypographySignature: Hashable {
    let title1: FontSignature
    let title2: FontSignature
    let headline: FontSignature
    let subheadline: FontSignature
    let body: FontSignature
    let codeBlock: FontSignature
    let inlineCode: FontSignature

    init(_ typography: AppKitMarkdownTypography) {
        title1 = FontSignature(typography.title1)
        title2 = FontSignature(typography.title2)
        headline = FontSignature(typography.headline)
        subheadline = FontSignature(typography.subheadline)
        body = FontSignature(typography.body)
        codeBlock = FontSignature(typography.codeBlock)
        inlineCode = FontSignature(typography.inlineCode)
    }

    struct FontSignature: Hashable {
        let fontName: String
        let pointSize: CGFloat

        init(_ font: NSFont) {
            fontName = font.fontName
            pointSize = font.pointSize
        }
    }
}

enum AppKitMarkdownRendererVersion {
    static let current = rendererVersion
}
