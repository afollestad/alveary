import Foundation
import SwiftUI

struct AppMarkdownBlockContent<Content: AttributedStringProtocol>: View {
    let content: Content
    let parent: PresentationIntent.IntentType?
    let taskStateNamespace: String
    let path: String
    let inlineCodeStyle: AppMarkdownInlineCodeStyle

    init(
        content: Content,
        parent: PresentationIntent.IntentType? = nil,
        taskStateNamespace: String,
        path: String = "",
        inlineCodeStyle: AppMarkdownInlineCodeStyle
    ) {
        self.content = content
        self.parent = parent
        self.taskStateNamespace = taskStateNamespace
        self.path = path
        self.inlineCodeStyle = inlineCodeStyle
    }

    var body: some View {
        let runs = content.appMarkdownBlockRuns(parent: parent)
        VStack(alignment: .leading, spacing: 8) {
            ForEach(runs.indices, id: \.self) { index in
                let run = runs[index]
                AppMarkdownBlock(
                    intent: run.intent,
                    content: content[run.range],
                    taskStateNamespace: taskStateNamespace,
                    path: path.appMarkdownAppendingPathComponent(index),
                    inlineCodeStyle: inlineCodeStyle
                )
            }
        }
    }
}

struct AppMarkdownBlock: View {
    let intent: PresentationIntent.IntentType?
    let content: AttributedSubstring
    let taskStateNamespace: String
    let path: String
    let inlineCodeStyle: AppMarkdownInlineCodeStyle

    var body: some View {
        switch intent?.kind {
        case .header(let level):
            AppMarkdownInlineText(content: AttributedString(content), inlineCodeStyle: inlineCodeStyle)
                .font(headerFont(for: level))
                .fontWeight(.semibold)
                .padding(.top, level == 1 ? 2 : 1)
        case .codeBlock(let languageHint):
            AppMarkdownCodeBlock(
                code: codeBlockText,
                languageHint: languageHint
            )
            .padding(.vertical, 2)
        case .unorderedList:
            AppMarkdownList(
                intent: intent,
                content: content,
                taskStateNamespace: taskStateNamespace,
                path: path,
                isOrdered: false,
                inlineCodeStyle: inlineCodeStyle
            )
        case .orderedList:
            AppMarkdownList(
                intent: intent,
                content: content,
                taskStateNamespace: taskStateNamespace,
                path: path,
                isOrdered: true,
                inlineCodeStyle: inlineCodeStyle
            )
        case .blockQuote:
            HStack(alignment: .top, spacing: 10) {
                Rectangle()
                    .fill(Color.secondary.opacity(0.45))
                    .frame(width: 3)
                    .clipShape(Capsule())
                AppMarkdownBlockContent(
                    content: content,
                    parent: intent,
                    taskStateNamespace: taskStateNamespace,
                    path: path,
                    inlineCodeStyle: inlineCodeStyle
                )
            }
            .padding(.vertical, 2)
        case .thematicBreak:
            Divider()
                .padding(.vertical, 4)
        case .table(let columns):
            AppMarkdownTable(
                intent: intent,
                content: content,
                columns: columns,
                inlineCodeStyle: inlineCodeStyle
            )
            .padding(.vertical, 2)
        default:
            AppMarkdownInlineText(content: AttributedString(content), inlineCodeStyle: inlineCodeStyle)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var codeBlockText: String {
        let value = String(content.characters)
        if value.hasSuffix("\n") {
            return String(value.dropLast())
        }
        return value
    }

    private func headerFont(for level: Int) -> Font {
        switch level {
        case 1: return .title2
        case 2: return .title3
        case 3: return .headline
        default: return .subheadline
        }
    }
}

extension String {
    func appMarkdownAppendingPathComponent(_ component: Int) -> String {
        isEmpty ? "\(component)" : "\(self).\(component)"
    }
}
