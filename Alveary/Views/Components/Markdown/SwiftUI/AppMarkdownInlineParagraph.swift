import AppKit
import SwiftUI

/// Wrapping counterpart to `AppMarkdownInlineLabel`. Renders a string that may contain inline
/// markdown as a single `Text`, so inline code styles as a flat attributed run rather than a
/// chip view — a chip is `lineLimit(1)` and cannot break, so a code span wider than the
/// container would truncate instead of wrapping.
///
/// Use where the string must wrap and inline code should read the way it does in the block
/// markdown around it, such as the pull request pane's title above its description.
struct AppMarkdownInlineParagraph: View {
    let text: String
    /// Drives both the text font and the inline-code font size, so the two cannot mismatch.
    var textStyle: NSFont.TextStyle = .body
    var weight: Font.Weight = .regular

    var body: some View {
        AppMarkdownInlineText(content: content, inlineCodeStyle: .standard)
            // Applied as the environment font rather than through `.fontWeight`, so the
            // explicit per-run font on inline code keeps its own regular weight.
            .font(textStyle.appMarkdownSwiftUIFont.weight(weight))
            .environment(\.appMarkdownTypography, typography)
    }

    /// `AppMarkdownInlineText` reads the inline-code font from the typography environment, whose
    /// default is body-sized. Without this injection a `.title3` title would render its code runs
    /// at body size.
    private var typography: AppMarkdownTypography {
        AppMarkdownTypography(
            inlineCode: .system(size: textStyle.appMarkdownInlineCodeFontSize, design: .monospaced)
        )
    }

    private var content: AttributedString {
        guard let parsed = AppMarkdownInlineParseCache.parsedInline(for: text) else {
            return AttributedString(text)
        }
        return sanitized(parsed)
    }

    /// Strips link attributes the way `AppMarkdownInlineLabel` does. These surfaces render a
    /// label, not prose — a title must not become an underlined, clickable header.
    private func sanitized(_ content: AttributedString) -> AttributedString {
        var sanitized = content
        for range in sanitized.runs.map(\.range) {
            sanitized[range].link = nil
        }
        return sanitized
    }
}
