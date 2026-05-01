@preconcurrency import AppKit
import Foundation

struct AppKitMarkdownTypography: Equatable {
    static var `default`: AppKitMarkdownTypography {
        AppKitMarkdownTypography()
    }

    let title1: NSFont
    let title2: NSFont
    let headline: NSFont
    let subheadline: NSFont
    let body: NSFont
    let codeBlock: NSFont
    let inlineCode: NSFont

    init(
        title1: NSFont = .preferredFont(forTextStyle: .title2),
        title2: NSFont = .preferredFont(forTextStyle: .title3),
        headline: NSFont = .preferredFont(forTextStyle: .headline),
        subheadline: NSFont = .preferredFont(forTextStyle: .subheadline),
        body: NSFont = .preferredFont(forTextStyle: .body),
        codeBlock: NSFont = .monospacedSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular),
        inlineCode: NSFont = .monospacedSystemFont(ofSize: NSFont.systemFontSize * markdownInlineCodeFontScale, weight: .regular)
    ) {
        self.title1 = title1
        self.title2 = title2
        self.headline = headline
        self.subheadline = subheadline
        self.body = body
        self.codeBlock = codeBlock
        self.inlineCode = inlineCode
    }

    func headingFont(for level: Int) -> NSFont {
        switch level {
        case 1:
            return title1
        case 2:
            return title2
        case 3:
            return headline
        default:
            return subheadline
        }
    }
}
