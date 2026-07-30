import Foundation
import SwiftUI

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
                interleavedBlocks
            }
        }
        .textSelection(.enabled)
    }

    /// Image blocks interleave with markdown fragments; fragment indices prefix the
    /// task-state path so checkbox identity stays stable across the split.
    private var interleavedBlocks: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(document.blocks.enumerated()), id: \.offset) { index, block in
                switch block {
                case .markdown(let content):
                    AppMarkdownBlockContent(
                        content: content,
                        taskStateNamespace: document.taskStateNamespace,
                        path: "\(index)",
                        inlineCodeStyle: inlineCodeStyle
                    )
                case .image(let imageBlock):
                    AppMarkdownImageBlockView(block: imageBlock, baseURL: baseURL)
                }
            }
        }
    }

    private var onlyContent: AttributedString? {
        guard document.blocks.count == 1,
              case let .markdown(content) = document.blocks[0] else {
            return nil
        }
        return content
    }
}
