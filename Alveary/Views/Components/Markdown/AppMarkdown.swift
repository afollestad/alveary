import Foundation
import SwiftUI

let markdownInlineCodeFontScale: CGFloat = 0.94

enum AppMarkdownInlineCodeStyle {
    case standard
    case userBubble
    /// Accent-derived palette used by composer surfaces. The live input field draws
    /// chips directly from `AppMarkdownCodeBlockPalette.composerChip*`, and queue
    /// items render through this style so they match composer chrome.
    case composer
}

struct AppMarkdownText: View {
    let markdown: String
    var baseURL: URL?
    var foregroundColor: Color?
    var inlineCodeStyle: AppMarkdownInlineCodeStyle = .standard
    var composerChipProvider: ((String) -> [AppTextEditorChip])?
    var taskStateScope: String?

    var body: some View {
        Group {
            if let foregroundColor {
                content.foregroundStyle(foregroundColor)
            } else {
                content
            }
        }
    }

    private var content: some View {
        let document = AppMarkdownDocumentCache.document(
            markdown: markdown,
            context: AppMarkdownDocumentCacheContext(
                baseURL: baseURL,
                inlineCodeStyle: inlineCodeStyle,
                hasComposerChipProvider: composerChipProvider != nil,
                taskStateScope: taskStateScope
            )
        ) {
            let parser = AppMarkdownParser(
                baseURL: baseURL,
                composerChipProvider: composerChipProvider
            )
            return parser.documentPreservingSource(for: markdown)
        }
        return AppMarkdownRenderer(document: document, inlineCodeStyle: inlineCodeStyle)
    }
}
