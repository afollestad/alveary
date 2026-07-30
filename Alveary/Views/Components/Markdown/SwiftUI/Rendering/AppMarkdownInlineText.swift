import BlockInputKit
import Foundation
import SwiftUI

struct AppMarkdownInlineText: View {
    let content: AttributedString
    let inlineCodeStyle: AppMarkdownInlineCodeStyle

    @Environment(\.appMarkdownTypography) private var typography
    @Environment(\.appMarkdownImageStore) private var environmentStore

    var body: some View {
        builtText
            .fixedSize(horizontal: false, vertical: true)
            .task(id: inlineImageInfos) {
                for info in inlineImageInfos {
                    store.ensureLoad(for: BlockInputImage(source: info.source, altText: info.altText), baseURL: nil)
                }
            }
    }

    /// Inline-image runs whose bitmap has loaded render as the image at natural
    /// (or declared) point size, sitting on the text baseline; unloaded and failed
    /// runs keep showing their alt text.
    private var builtText: Text {
        let styled = styledContent
        guard !inlineImageInfos.isEmpty else {
            return Text(styled)
        }
        var built = Text(verbatim: "")
        for run in styled.runs[AppMarkdownInlineImageAttribute.self] {
            let segment: Text
            if let info = run.0, let nsImage = store.image(forSource: info.source) {
                segment = inlineImageText(info: info, nsImage: nsImage)
            } else {
                segment = Text(AttributedString(styled[run.1]))
            }
            built = Text("\(built)\(segment)")
        }
        return built
    }

    private func inlineImageText(info: AppMarkdownInlineImageInfo, nsImage: NSImage) -> Text {
        guard let sized = nsImage.copy() as? NSImage else {
            return Text(info.accessibilityLabel)
        }
        let displaySize = info.displaySize(forNaturalSize: nsImage.size)
        sized.size = displaySize
        sized.accessibilityDescription = info.accessibilityLabel
        // Body cap height approximates the run's font; comment surfaces render at
        // body size, and a slight miss in headings beats a baseline-riding badge.
        let drop = AppMarkdownInlineImageInfo.baselineDrop(
            forDisplayHeight: displaySize.height,
            capHeight: NSFont.preferredFont(forTextStyle: .body).capHeight
        )
        return Text(Image(nsImage: sized)).baselineOffset(-drop)
    }

    private var inlineImageInfos: [AppMarkdownInlineImageInfo] {
        var infos: [AppMarkdownInlineImageInfo] = []
        for run in content.runs[AppMarkdownInlineImageAttribute.self] {
            if let info = run.0, !infos.contains(info) {
                infos.append(info)
            }
        }
        return infos
    }

    private var store: AppMarkdownImageStore {
        environmentStore ?? .shared
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
                attributed[item.range].font = typography.swiftUIFont(.inlineCode)
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
        case .assistantBubble:
            return Color(nsColor: AppMarkdownCodeBlockPalette.assistantBubbleInlineFillNSColor)
        case .userBubble:
            return Color(nsColor: AppMarkdownCodeBlockPalette.userBubbleInlineFillNSColor)
        case .composer:
            return Color(nsColor: AppMarkdownCodeBlockPalette.composerChipFillNSColor)
        }
    }

    private var inlineCodeForegroundColor: Color {
        switch inlineCodeStyle {
        case .standard, .assistantBubble, .userBubble:
            return Color(nsColor: AppMarkdownCodeBlockPalette.inlineChipForegroundNSColor)
        case .composer:
            return Color(nsColor: AppMarkdownCodeBlockPalette.composerChipForegroundNSColor)
        }
    }
}
