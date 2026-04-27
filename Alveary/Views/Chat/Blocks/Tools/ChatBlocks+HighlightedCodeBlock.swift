import SwiftUI

/// Shared code-block container used by tool rows that want to show content *as code* —
/// Write's file body, Read's file output, Bash's stdout, etc. Applies `SyntaxHighlighter`
/// styling and reuses `AppMarkdownCodeBlockPalette` so the surface matches the rest of
/// the app's code chrome (same fill / border / monospaced type).
struct HighlightedCodeBlock: View {
    let content: String
    let language: String
    var preservesLeadingLineNumberPrefixes = false
    var horizontalPadding: CGFloat = 12
    var verticalPadding: CGFloat = 10

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        // No `.frame(maxWidth: .infinity)` on the ScrollView: it would force the block
        // (and therefore the enclosing bubble) to grow to `bubbleMaxWidth` even when
        // the code body is a short snippet. Let the ScrollView report its content-ideal
        // width; the parent bubble's own cap still limits oversized content.
        ScrollView(.horizontal) {
            Text(attributedContent)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .fixedSize(horizontal: true, vertical: false)
                .padding(.horizontal, horizontalPadding)
                .padding(.vertical, verticalPadding)
        }
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(AppMarkdownCodeBlockPalette.fillColor(for: colorScheme))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(AppMarkdownCodeBlockPalette.borderColor(for: colorScheme), lineWidth: 1)
        )
    }

    private var attributedContent: AttributedString {
        SyntaxHighlighter.highlighted(
            content,
            language: language,
            colorScheme: colorScheme,
            preserveLineNumberPrefixes: preservesLeadingLineNumberPrefixes
        )
    }
}
