@preconcurrency import AppKit
import SwiftUI

private let appMarkdownInlineCodeCornerRadius: CGFloat = 5
private let appMarkdownInlineCodeHorizontalPadding: CGFloat = 5
private let appMarkdownInlineCodeVerticalPadding: CGFloat = 2

// Renders compact single-line chips for sidebar rows and tab labels. Multi-line
// markdown surfaces use `AppMarkdownRenderer` so line height stays uniform.
struct AppMarkdownInlineCodeChip: View {
    let text: String
    let style: AppMarkdownInlineCodeStyle
    let fontSize: CGFloat

    var body: some View {
        Text(verbatim: text)
            .font(.system(size: fontSize, weight: .regular, design: .monospaced))
            .foregroundStyle(Color(nsColor: foregroundColor))
            .lineLimit(1)
            .truncationMode(.tail)
            .padding(.horizontal, appMarkdownInlineCodeHorizontalPadding)
            .padding(.vertical, appMarkdownInlineCodeVerticalPadding)
            .background(Color(nsColor: fillColor))
            .clipShape(RoundedRectangle(cornerRadius: appMarkdownInlineCodeCornerRadius, style: .continuous))
    }

    private var fillColor: NSColor {
        switch style {
        case .standard:
            return AppMarkdownCodeBlockPalette.inlineFillNSColor
        case .assistantBubble:
            return AppMarkdownCodeBlockPalette.assistantBubbleInlineFillNSColor
        case .userBubble:
            return AppMarkdownCodeBlockPalette.userBubbleInlineFillNSColor
        case .composer:
            return AppMarkdownCodeBlockPalette.composerChipFillNSColor
        }
    }

    private var foregroundColor: NSColor {
        switch style {
        case .standard, .assistantBubble, .userBubble:
            return AppMarkdownCodeBlockPalette.inlineChipForegroundNSColor
        case .composer:
            return AppMarkdownCodeBlockPalette.composerChipForegroundNSColor
        }
    }
}
