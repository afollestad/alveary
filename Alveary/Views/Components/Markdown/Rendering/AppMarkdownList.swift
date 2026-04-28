import Foundation
import SwiftUI

struct AppMarkdownList: View {
    let intent: PresentationIntent.IntentType?
    let content: AttributedSubstring
    let taskStateNamespace: String
    let path: String
    let isOrdered: Bool
    let inlineCodeStyle: AppMarkdownInlineCodeStyle

    var body: some View {
        let itemRuns = content.appMarkdownBlockRuns(parent: intent)
        VStack(alignment: .leading, spacing: 5) {
            ForEach(itemRuns.indices, id: \.self) { index in
                let itemRun = itemRuns[index]
                let itemContent = AttributedString(content[itemRun.range])
                let taskState = isOrdered ? nil : AppMarkdownTaskListState(content: itemContent)
                HStack(alignment: .top, spacing: 8) {
                    markerView(
                        for: itemRun,
                        fallbackIndex: index,
                        taskState: taskState,
                        taskID: taskID(for: index)
                    )
                    .frame(minWidth: markerWidth(for: taskState), alignment: .trailing)

                    AppMarkdownBlockContent(
                        content: taskState?.contentWithoutMarker ?? itemContent,
                        parent: itemRun.intent,
                        taskStateNamespace: taskStateNamespace,
                        path: path.appMarkdownAppendingPathComponent(index),
                        inlineCodeStyle: inlineCodeStyle
                    )
                }
            }
        }
        .padding(.leading, 2)
    }

    private func markerWidth(for taskState: AppMarkdownTaskListState?) -> CGFloat {
        if taskState != nil {
            return 16
        }
        return isOrdered ? 24 : 14
    }

    @ViewBuilder
    private func markerView(
        for run: AppMarkdownBlockRun,
        fallbackIndex: Int,
        taskState: AppMarkdownTaskListState?,
        taskID: String
    ) -> some View {
        if let taskState {
            AppMarkdownTaskCheckbox(id: taskID, initialValue: taskState.isChecked)
        } else {
            Text(marker(for: run, fallbackIndex: fallbackIndex))
                .appMarkdownFont(.body)
                .foregroundStyle(.secondary)
        }
    }

    private func marker(for run: AppMarkdownBlockRun, fallbackIndex: Int) -> String {
        guard isOrdered else {
            return "•"
        }
        if case .listItem(let ordinal) = run.intent?.kind {
            return "\(ordinal)."
        }
        return "\(fallbackIndex + 1)."
    }

    private func taskID(for index: Int) -> String {
        [taskStateNamespace, path.appMarkdownAppendingPathComponent(index)]
            .filter { !$0.isEmpty }
            .joined(separator: ":")
    }
}

struct AppMarkdownTaskListState {
    let isChecked: Bool
    let contentWithoutMarker: AttributedString

    init?(content: AttributedString) {
        var content = content
        let text = String(content.characters)
        let markerLength: Int
        if text.hasPrefix("[ ] ") {
            isChecked = false
            markerLength = 4
        } else if text.hasPrefix("[ ]") {
            isChecked = false
            markerLength = 3
        } else if text.lowercased().hasPrefix("[x] ") {
            isChecked = true
            markerLength = 4
        } else if text.lowercased().hasPrefix("[x]") {
            isChecked = true
            markerLength = 3
        } else {
            return nil
        }

        let markerEnd = content.characters.index(content.startIndex, offsetBy: markerLength)
        content.removeSubrange(content.startIndex..<markerEnd)
        contentWithoutMarker = content
    }
}
