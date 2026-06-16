@preconcurrency import AppKit
import Foundation
import SwiftUI

@MainActor
enum AppKitMarkdownAttributedStringBuilder {
    static func attributedString(
        from content: AttributedString,
        baseFont: NSFont,
        inlineCodeFont: NSFont? = nil,
        weight: NSFont.Weight = .regular,
        inlineCodeStyle: AppMarkdownInlineCodeStyle
    ) -> NSAttributedString {
        let attributed = NSMutableAttributedString(attributedString: NSAttributedString(content))
        let fullRange = NSRange(location: 0, length: attributed.length)
        let weightedFont = NSFont.systemFont(ofSize: baseFont.pointSize, weight: weight)
        attributed.addAttributes([
            NSAttributedString.Key.font: weightedFont,
            NSAttributedString.Key.foregroundColor: NSColor.labelColor
        ], range: fullRange)

        var location = 0
        for run in content.runs {
            let runText = String(content[run.range].characters)
            let range = NSRange(location: location, length: (runText as NSString).length)
            defer { location += range.length }
            addAttributes(for: run, to: attributed, context: .init(
                range: range,
                baseFont: baseFont,
                inlineCodeFont: inlineCodeFont,
                inlineCodeStyle: inlineCodeStyle
            ))
        }
        return attributed
    }

    static func syntaxHighlightedCode(
        _ source: String,
        language: String,
        colorScheme: ColorScheme,
        font: NSFont,
        preserveLineNumberPrefixes: Bool = false
    ) -> NSAttributedString {
        let highlighted = SyntaxHighlighter.highlighted(
            source,
            language: language,
            colorScheme: colorScheme,
            preserveLineNumberPrefixes: preserveLineNumberPrefixes
        )
        let attributed = NSMutableAttributedString(
            string: String(highlighted.characters),
            attributes: [
                NSAttributedString.Key.font: font,
                NSAttributedString.Key.foregroundColor: NSColor.labelColor
            ]
        )

        var location = 0
        for run in highlighted.runs {
            let runText = String(highlighted[run.range].characters)
            let range = NSRange(location: location, length: (runText as NSString).length)
            defer { location += range.length }

            if let foregroundColor = run.foregroundColor {
                attributed.addAttribute(
                    NSAttributedString.Key.foregroundColor,
                    value: NSColor(foregroundColor),
                    range: range
                )
            }
        }
        return attributed
    }

    static func inlineCodeAttributes(
        for style: AppMarkdownInlineCodeStyle,
        font: NSFont
    ) -> [NSAttributedString.Key: Any] {
        [
            NSAttributedString.Key.font: font,
            NSAttributedString.Key.foregroundColor: inlineCodeForegroundColor(for: style),
            NSAttributedString.Key.backgroundColor: inlineCodeFillColor(for: style)
        ]
    }

    private static func linkColor(for style: AppMarkdownInlineCodeStyle) -> NSColor {
        style == .userBubble ? .labelColor : .controlAccentColor
    }

    private static func addAttributes(
        for run: AttributedString.Runs.Run,
        to attributed: NSMutableAttributedString,
        context: RunAttributeContext
    ) {
        addEmphasisAttributes(for: run, to: attributed, range: context.range, baseFont: context.baseFont)
        let isInlineCode = run.inlinePresentationIntent?.contains(.code) == true
        if isInlineCode {
            attributed.addAttributes(
                inlineCodeAttributes(
                    for: context.inlineCodeStyle,
                    font: context.inlineCodeFont ?? NSFont.monospacedSystemFont(
                        ofSize: context.baseFont.pointSize * markdownInlineCodeFontScale,
                        weight: .regular
                    )
                ),
                range: context.range
            )
        }
        if let link = run.link {
            var linkAttributes = linkAttributes(for: link, inlineCodeStyle: context.inlineCodeStyle, isInlineCode: isInlineCode)
            linkAttributes[NSAttributedString.Key.link] = link
            attributed.addAttributes(linkAttributes, range: context.range)
        }
        if run.underlineStyle != nil {
            attributed.addAttribute(NSAttributedString.Key.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: context.range)
        }
    }

    private static func addEmphasisAttributes(
        for run: AttributedString.Runs.Run,
        to attributed: NSMutableAttributedString,
        range: NSRange,
        baseFont: NSFont
    ) {
        if run.inlinePresentationIntent?.contains(.stronglyEmphasized) == true {
            attributed.addAttribute(NSAttributedString.Key.font, value: NSFont.boldSystemFont(ofSize: baseFont.pointSize), range: range)
        } else if run.inlinePresentationIntent?.contains(.emphasized) == true {
            let italic = NSFontManager.shared.convert(baseFont, toHaveTrait: .italicFontMask)
            attributed.addAttribute(NSAttributedString.Key.font, value: italic, range: range)
        }
    }

    private static func linkAttributes(
        for link: URL,
        inlineCodeStyle: AppMarkdownInlineCodeStyle,
        isInlineCode: Bool
    ) -> [NSAttributedString.Key: Any] {
        guard !isInlineCode else {
            return [:]
        }
        let color = isFileReferenceLink(link) ? NSColor.labelColor : linkColor(for: inlineCodeStyle)
        return [
            NSAttributedString.Key.foregroundColor: color,
            NSAttributedString.Key.underlineStyle: NSUnderlineStyle.single.rawValue
        ]
    }

    private static func isFileReferenceLink(_ link: URL) -> Bool {
        link.isFileURL || link.scheme == nil
    }

    private static func inlineCodeFillColor(for style: AppMarkdownInlineCodeStyle) -> NSColor {
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

    private static func inlineCodeForegroundColor(for style: AppMarkdownInlineCodeStyle) -> NSColor {
        switch style {
        case .standard, .assistantBubble, .userBubble:
            return AppMarkdownCodeBlockPalette.inlineChipForegroundNSColor
        case .composer:
            return AppMarkdownCodeBlockPalette.composerChipForegroundNSColor
        }
    }
}

private struct RunAttributeContext {
    let range: NSRange
    let baseFont: NSFont
    let inlineCodeFont: NSFont?
    let inlineCodeStyle: AppMarkdownInlineCodeStyle
}
