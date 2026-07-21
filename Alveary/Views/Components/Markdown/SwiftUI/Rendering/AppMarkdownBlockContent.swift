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
                .appMarkdownFont(headerFontLevel(for: level))
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

    private func headerFontLevel(for level: Int) -> AppMarkdownTypography.FontLevel {
        switch level {
        case 1: return .title1
        case 2: return .title2
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

    func makeCache(subviews: Subviews) -> AppMarkdownBlockStackLayoutCache {
        AppMarkdownBlockStackLayoutCache()
    }

    func updateCache(
        _ cache: inout AppMarkdownBlockStackLayoutCache,
        subviews: Subviews
    ) {
        cache = AppMarkdownBlockStackLayoutCache()
    }

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout AppMarkdownBlockStackLayoutCache
    ) -> CGSize {
        measurement(
            proposalWidth: proposal.width,
            subviews: subviews,
            cache: &cache
        ).size
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout AppMarkdownBlockStackLayoutCache
    ) {
        let measurement = measurement(
            proposalWidth: bounds.width,
            subviews: subviews,
            cache: &cache
        )
        var currentY = bounds.minY
        let childProposal = ProposedViewSize(width: bounds.width, height: nil)

        for (index, subview) in subviews.enumerated() {
            if index > 0 {
                currentY += spacing
            }
            subview.place(
                at: CGPoint(x: bounds.minX, y: currentY),
                anchor: .topLeading,
                proposal: childProposal
            )
            currentY += measurement.childSizes[index].height
        }
    }

    private func measurement(
        proposalWidth: CGFloat?,
        subviews: Subviews,
        cache: inout AppMarkdownBlockStackLayoutCache
    ) -> AppMarkdownBlockStackLayoutMeasurement {
        if let measurement = cache.measurement,
           measurement.proposalWidth == proposalWidth,
           measurement.spacing == spacing,
           measurement.childSizes.count == subviews.count {
            return measurement
        }

        let childProposal = ProposedViewSize(width: proposalWidth, height: nil)
        var childSizes: [CGSize] = []
        childSizes.reserveCapacity(subviews.count)
        var width: CGFloat = 0
        var height: CGFloat = 0
        var hasWidthContributingSubview = false

        for (index, subview) in subviews.enumerated() {
            let size = subview.sizeThatFits(childProposal)
            childSizes.append(size)
            if index > 0 {
                height += spacing
            }
            height += size.height

            guard !subview[AppMarkdownThematicBreakLayoutKey.self] else {
                continue
            }
            hasWidthContributingSubview = true
            width = max(
                width,
                widthContribution(
                    for: subview,
                    at: index,
                    measuredSize: size,
                    proposalWidth: proposalWidth,
                    cache: &cache
                )
            )
        }

        if !hasWidthContributingSubview {
            width = min(proposalWidth ?? appMarkdownFallbackThematicBreakWidth, appMarkdownFallbackThematicBreakWidth)
        }

        let measurement = AppMarkdownBlockStackLayoutMeasurement(
            proposalWidth: proposalWidth,
            spacing: spacing,
            childSizes: childSizes,
            size: CGSize(width: width, height: height)
        )
        cache.measurement = measurement
        return measurement
    }

    private func widthContribution(
        for subview: LayoutSubview,
        at index: Int,
        measuredSize: CGSize,
        proposalWidth: CGFloat?,
        cache: inout AppMarkdownBlockStackLayoutCache
    ) -> CGFloat {
        guard subview[AppMarkdownIntrinsicWidthLayoutKey.self] else {
            return measuredSize.width
        }

        // Code blocks fill the stack width like rules when placed, but report their
        // intrinsic code width here so they expand the bubble only when content needs it.
        let intrinsicWidth: CGFloat
        if let cachedWidth = cache.intrinsicWidths[index] {
            intrinsicWidth = cachedWidth
        } else {
            intrinsicWidth = subview.sizeThatFits(.unspecified).width
            cache.intrinsicWidths[index] = intrinsicWidth
        }
        guard let proposalWidth else {
            return intrinsicWidth
        }
        return min(intrinsicWidth, proposalWidth)
    }
}

private struct AppMarkdownBlockStackLayoutCache {
    var measurement: AppMarkdownBlockStackLayoutMeasurement?
    var intrinsicWidths: [Int: CGFloat] = [:]
}

private struct AppMarkdownBlockStackLayoutMeasurement {
    let proposalWidth: CGFloat?
    let spacing: CGFloat
    let childSizes: [CGSize]
    let size: CGSize
}
