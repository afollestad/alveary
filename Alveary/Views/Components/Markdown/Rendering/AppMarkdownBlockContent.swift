import Foundation
import SwiftUI

private let appMarkdownBlockSpacing: CGFloat = 8
private let appMarkdownFallbackThematicBreakWidth: CGFloat = 240

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
        AppMarkdownBlockStackLayout(spacing: appMarkdownBlockSpacing) {
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
            .layoutValue(key: AppMarkdownIntrinsicWidthLayoutKey.self, value: true)
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
            Rectangle()
                .fill(Color.secondary.opacity(0.24))
                .frame(height: 1)
                .padding(.vertical, 4)
                .layoutValue(key: AppMarkdownThematicBreakLayoutKey.self, value: true)
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

private struct AppMarkdownThematicBreakLayoutKey: LayoutValueKey {
    static let defaultValue = false
}

private struct AppMarkdownIntrinsicWidthLayoutKey: LayoutValueKey {
    static let defaultValue = false
}

private struct AppMarkdownBlockStackLayout: Layout {
    let spacing: CGFloat

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        let childProposal = ProposedViewSize(width: proposal.width, height: nil)
        var width: CGFloat = 0
        var height: CGFloat = 0
        var hasWidthContributingSubview = false

        for (index, subview) in subviews.enumerated() {
            let size = subview.sizeThatFits(childProposal)
            if index > 0 {
                height += spacing
            }
            height += size.height

            guard !subview[AppMarkdownThematicBreakLayoutKey.self] else {
                continue
            }
            hasWidthContributingSubview = true
            width = max(width, widthContribution(for: subview, measuredSize: size, proposal: proposal))
        }

        if !hasWidthContributingSubview {
            width = min(proposal.width ?? appMarkdownFallbackThematicBreakWidth, appMarkdownFallbackThematicBreakWidth)
        }

        return CGSize(width: width, height: height)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        var currentY = bounds.minY
        let childProposal = ProposedViewSize(width: bounds.width, height: nil)

        for (index, subview) in subviews.enumerated() {
            let size = subview.sizeThatFits(childProposal)
            if index > 0 {
                currentY += spacing
            }
            subview.place(
                at: CGPoint(x: bounds.minX, y: currentY),
                anchor: .topLeading,
                proposal: childProposal
            )
            currentY += size.height
        }
    }

    private func widthContribution(
        for subview: LayoutSubview,
        measuredSize: CGSize,
        proposal: ProposedViewSize
    ) -> CGFloat {
        guard subview[AppMarkdownIntrinsicWidthLayoutKey.self] else {
            return measuredSize.width
        }

        // Code blocks fill the stack width like rules when placed, but report their
        // intrinsic code width here so they expand the bubble only when content needs it.
        let intrinsicWidth = subview.sizeThatFits(ProposedViewSize(width: nil, height: nil)).width
        guard let proposedWidth = proposal.width else {
            return intrinsicWidth
        }
        return min(intrinsicWidth, proposedWidth)
    }
}
