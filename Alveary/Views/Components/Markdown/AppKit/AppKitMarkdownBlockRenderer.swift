@preconcurrency import AppKit
import Foundation

@MainActor
struct AppKitMarkdownBlockRenderer {
    let taskStateNamespace: String
    let inlineCodeStyle: AppMarkdownInlineCodeStyle
    let typography: AppKitMarkdownTypography
    let onOpenLink: ((URL) -> Void)?
    let heightInvalidationHandler: () -> Void

    func views<Content: AttributedStringProtocol>(
        for content: Content,
        parent: PresentationIntent.IntentType? = nil,
        path: String = ""
    ) -> [NSView] {
        content.appMarkdownBlockRuns(parent: parent).enumerated().map { index, run in
            view(
                for: run,
                content: AttributedString(content[run.range]),
                parent: parent,
                path: path.appMarkdownAppendingPathComponent(index)
            )
        }
    }

    private func view(
        for run: AppMarkdownBlockRun,
        content: AttributedString,
        parent: PresentationIntent.IntentType?,
        path: String
    ) -> NSView {
        switch run.intent?.kind {
        case .header(let level):
            return textView(content, font: typography.headingFont(for: level), weight: .semibold)
        case .codeBlock(let languageHint):
            return AppKitMarkdownCodeBlockView(
                code: codeBlockText(content),
                languageHint: languageHint,
                codeFont: typography.codeBlock
            )
        case .unorderedList:
            return listView(intent: run.intent, content: content, path: path, isOrdered: false)
        case .orderedList:
            return listView(intent: run.intent, content: content, path: path, isOrdered: true)
        case .blockQuote:
            return quoteView(intent: run.intent, content: content, path: path)
        case .thematicBreak:
            return AppKitMarkdownRuleView()
        case .table(let columns):
            return AppKitMarkdownTableView(
                intent: run.intent,
                content: content,
                columns: columns,
                rendering: AppKitMarkdownTableRendering(
                    inlineCodeStyle: inlineCodeStyle,
                    typography: typography,
                    onOpenLink: onOpenLink,
                    heightInvalidationHandler: heightInvalidationHandler
                )
            )
        default:
            return textView(content)
        }
    }

    private func listView(
        intent: PresentationIntent.IntentType?,
        content: AttributedString,
        path: String,
        isOrdered: Bool
    ) -> NSView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .width
        stack.spacing = AppKitMarkdownMetrics.listItemSpacing
        stack.translatesAutoresizingMaskIntoConstraints = false

        let itemRuns = content.appMarkdownBlockRuns(parent: intent)
        for (index, itemRun) in itemRuns.enumerated() {
            let itemContent = AttributedString(content[itemRun.range])
            let taskState = isOrdered ? nil : AppMarkdownTaskListState(content: itemContent)
            let row = NSStackView()
            row.orientation = .horizontal
            row.alignment = .top
            row.spacing = 8
            row.translatesAutoresizingMaskIntoConstraints = false

            let marker = AppKitMarkdownMarkerColumnView(
                contentView: markerView(
                    for: itemRun,
                    fallbackIndex: index,
                    isOrdered: isOrdered,
                    taskState: taskState,
                    taskID: taskID(path: path, index: index)
                )
            )
            let markerWidth = markerWidth(isOrdered: isOrdered, taskState: taskState)
            marker.widthAnchor.constraint(equalToConstant: markerWidth)
                .isActive = true
            row.addArrangedSubview(marker)

            let childStack = verticalStack()
            views(
                for: taskState?.contentWithoutMarker ?? itemContent,
                parent: itemRun.intent,
                path: path.appMarkdownAppendingPathComponent(index)
            )
            .forEach(childStack.addArrangedSubview)
            row.addArrangedSubview(childStack)
            stack.addArrangedSubview(row)
        }
        return stack
    }

    private func quoteView(
        intent: PresentationIntent.IntentType?,
        content: AttributedString,
        path: String
    ) -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .top
        row.spacing = 10
        row.translatesAutoresizingMaskIntoConstraints = false

        let bar = NSBox()
        bar.boxType = .custom
        bar.isTransparent = false
        bar.fillColor = .separatorColor
        bar.cornerRadius = AppKitMarkdownMetrics.quoteBarWidth / 2
        bar.translatesAutoresizingMaskIntoConstraints = false
        bar.widthAnchor.constraint(equalToConstant: AppKitMarkdownMetrics.quoteBarWidth).isActive = true
        row.addArrangedSubview(bar)

        let childStack = verticalStack()
        views(for: content, parent: intent, path: path).forEach(childStack.addArrangedSubview)
        row.addArrangedSubview(childStack)
        return row
    }

    private func textView(
        _ content: AttributedString,
        font: NSFont? = nil,
        weight: NSFont.Weight = .regular
    ) -> NSView {
        AppKitMarkdownTextView(
            content: AppKitMarkdownAttributedStringBuilder.attributedString(
                from: content,
                baseFont: font ?? typography.body,
                inlineCodeFont: typography.inlineCode,
                weight: weight,
                inlineCodeStyle: inlineCodeStyle
            ),
            onOpenLink: onOpenLink,
            heightInvalidationHandler: heightInvalidationHandler
        )
    }

    private func markerView(
        for run: AppMarkdownBlockRun,
        fallbackIndex: Int,
        isOrdered: Bool,
        taskState: AppMarkdownTaskListState?,
        taskID: String
    ) -> NSView {
        if let taskState {
            return AppKitMarkdownTaskCheckbox(id: taskID, initialValue: taskState.isChecked)
        }
        if !isOrdered {
            return AppKitMarkdownBulletMarkerView(font: typography.body, color: .secondaryLabelColor)
        }
        let text: String
        if case .listItem(let ordinal) = run.intent?.kind, ordinal > 0 {
            text = "\(ordinal)."
        } else {
            text = "\(fallbackIndex + 1)."
        }
        return AppKitMarkdownMarkerLabel(
            text: text,
            font: typography.body,
            color: .secondaryLabelColor
        )
    }

    private func markerWidth(isOrdered: Bool, taskState: AppMarkdownTaskListState?) -> CGFloat {
        if taskState != nil {
            return AppKitMarkdownMetrics.taskMarkerWidth
        }
        return isOrdered ? AppKitMarkdownMetrics.orderedListMarkerWidth : AppKitMarkdownMetrics.unorderedListMarkerWidth
    }

    private func taskID(path: String, index: Int) -> String {
        [taskStateNamespace, path.appMarkdownAppendingPathComponent(index)]
            .filter { !$0.isEmpty }
            .joined(separator: ":")
    }

    private func codeBlockText(_ content: AttributedString) -> String {
        let value = String(content.characters)
        return value.hasSuffix("\n") ? String(value.dropLast()) : value
    }

    private func verticalStack() -> NSStackView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .width
        stack.spacing = AppKitMarkdownMetrics.blockSpacing
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }
}
