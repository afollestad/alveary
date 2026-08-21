import Foundation
import SwiftUI

/// Matches `AppKitMarkdownMetrics.blockSpacing`, so a document's blocks sit the same distance
/// apart in both renderers.
private let appMarkdownDocumentBlockSpacing: CGFloat = 8

struct AppMarkdownRenderer: View {
    let document: AppMarkdownDocument
    let inlineCodeStyle: AppMarkdownInlineCodeStyle
    var baseURL: URL?

    var body: some View {
        Group {
            if let onlyContent {
                AppMarkdownBlockContent(
                    content: onlyContent,
                    taskStateNamespace: document.taskStateNamespace,
                    inlineCodeStyle: inlineCodeStyle
                )
            } else {
                AppMarkdownBlockList(
                    blocks: document.blocks,
                    taskStateNamespace: document.taskStateNamespace,
                    inlineCodeStyle: inlineCodeStyle,
                    baseURL: baseURL
                )
            }
        }
        .textSelection(.enabled)
    }

    private var onlyContent: AttributedString? {
        guard document.blocks.count == 1,
              case let .markdown(content) = document.blocks[0] else {
            return nil
        }
        return content
    }
}

/// Markdown fragments, image blocks, and disclosures interleave in source order.
///
/// Block indices prefix the task-state path so checkbox and disclosure identity stay stable
/// across the split, and so a disclosure's body gets its own path space — two checkboxes at the
/// same position inside and outside a disclosure must not share one entry.
///
/// This is a plain `VStack`, deliberately not `AppMarkdownBlockStackLayout`: that layout caches
/// its measurement by proposal width and subview count, neither of which changes when a
/// disclosure opens, so a disclosure hosted there would keep reporting its collapsed height.
struct AppMarkdownBlockList: View {
    let blocks: [AppMarkdownDocumentBlock]
    let taskStateNamespace: String
    var pathPrefix: String = ""
    let inlineCodeStyle: AppMarkdownInlineCodeStyle
    var baseURL: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: appMarkdownDocumentBlockSpacing) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { index, block in
                blockView(block, path: pathPrefix.appMarkdownAppendingPathComponent(index))
            }
        }
    }

    @ViewBuilder
    private func blockView(
        _ block: AppMarkdownDocumentBlock,
        path: String
    ) -> some View {
        switch block {
        case .markdown(let content):
            AppMarkdownBlockContent(
                content: content,
                taskStateNamespace: taskStateNamespace,
                path: path,
                inlineCodeStyle: inlineCodeStyle
            )
        case .image(let imageBlock):
            AppMarkdownImageBlockView(block: imageBlock, baseURL: baseURL)
        case .details(let detailsBlock):
            AppMarkdownDetailsBlockView(
                block: detailsBlock,
                taskStateNamespace: taskStateNamespace,
                path: path,
                inlineCodeStyle: inlineCodeStyle,
                baseURL: baseURL
            )
        }
    }
}
