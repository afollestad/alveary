import AppKit
import SwiftUI

/// Shared `NSFont.TextStyle` mappings for the inline label family. `AppMarkdownInlineLabel` and
/// `AppMarkdownInlineParagraph` both drive their text and inline-code sizing from a single
/// `textStyle` parameter, so the mappings live here rather than being duplicated per label — a
/// divergence would render a chip at a different size than the text it sits in.
extension NSFont.TextStyle {
    var appMarkdownSwiftUIFont: Font {
        switch self {
        case .largeTitle: return .largeTitle
        case .title1: return .title
        case .title2: return .title2
        case .title3: return .title3
        case .headline: return .headline
        case .subheadline: return .subheadline
        case .callout: return .callout
        case .footnote: return .footnote
        case .caption1: return .caption
        case .caption2: return .caption2
        default: return .body
        }
    }

    var appMarkdownInlineCodeFontSize: CGFloat {
        NSFont.preferredFont(forTextStyle: self).pointSize * markdownInlineCodeFontScale
    }

    var appMarkdownLineHeight: CGFloat {
        let font = NSFont.preferredFont(forTextStyle: self)
        return ceil(font.ascender + abs(font.descender) + font.leading)
    }
}

/// Cheap pre-filter so plain strings never reach the parser. Inline labels re-derive their content
/// on every `body` evaluation (and AppKit rows on every reconfigure), and the vast majority of the
/// strings they render carry no markdown at all.
func appMarkdownMayContainInlineMarkdown(_ markdown: String) -> Bool {
    markdown.contains { character in
        switch character {
        case "`", "[", "*", "_", "<", "!", "\\":
            return true
        default:
            return false
        }
    }
}
