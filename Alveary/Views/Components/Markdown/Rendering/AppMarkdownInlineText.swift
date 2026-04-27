import Foundation
import SwiftUI

struct AppMarkdownInlineText: View {
    let content: AttributedString
    let inlineCodeStyle: AppMarkdownInlineCodeStyle

    var body: some View {
        Text(styledContent)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var styledContent: AttributedString {
        var attributed = content
        let ranges = attributed.runs.map { run in
            (
                range: run.range,
                isCode: run.inlinePresentationIntent?.contains(.code) == true,
                isLink: run.link != nil
            )
        }

        for item in ranges {
            if item.isCode {
                attributed[item.range].font = .system(.body, design: .monospaced)
                attributed[item.range].foregroundColor = inlineCodeForegroundColor
                attributed[item.range].backgroundColor = inlineCodeFillColor
            }
            if item.isLink {
                attributed[item.range].foregroundColor = linkColor
                attributed[item.range].underlineStyle = .single
            }
        }
        return attributed
    }

    private var linkColor: Color {
        inlineCodeStyle == .userBubble ? .primary : .accentColor
    }

    private var inlineCodeFillColor: Color {
        switch inlineCodeStyle {
        case .standard:
            return Color(nsColor: AppMarkdownCodeBlockPalette.inlineFillNSColor)
        case .userBubble:
            return Color(nsColor: AppMarkdownCodeBlockPalette.userBubbleInlineFillNSColor)
        case .composer:
            return Color(nsColor: AppMarkdownCodeBlockPalette.composerChipFillNSColor)
        }
    }

    private var inlineCodeForegroundColor: Color {
        switch inlineCodeStyle {
        case .standard, .userBubble:
            return Color(nsColor: AppMarkdownCodeBlockPalette.inlineChipForegroundNSColor)
        case .composer:
            return Color(nsColor: AppMarkdownCodeBlockPalette.composerChipForegroundNSColor)
        }
    }
}
