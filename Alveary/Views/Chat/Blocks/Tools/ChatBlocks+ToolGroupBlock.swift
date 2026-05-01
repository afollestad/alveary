import SwiftUI

struct ToolGroupBlock: View {
    let tools: [ToolEntry]
    private let externalIsExpanded: Binding<Bool>?
    @State private var isExpanded: Bool

    init(
        tools: [ToolEntry],
        initiallyExpanded: Bool = false,
        isExpanded: Binding<Bool>? = nil
    ) {
        self.tools = tools
        self.externalIsExpanded = isExpanded
        _isExpanded = State(initialValue: initiallyExpanded)
    }

    var body: some View {
        let expansion = expansionBinding
        if tools.count <= 1, let only = tools.first {
            InlineToolRow(tool: only, isExpanded: expansion)
        } else {
            let toggleExpansion = {
                withAnimation(appExpansionAnimation) {
                    expansion.wrappedValue.toggle()
                }
            }
            VStack(alignment: .leading, spacing: 0) {
                AppHeaderToggle(action: toggleExpansion) {
                    TranscriptDisclosureHeaderRow(
                        summary: summary,
                        isExpanded: expansion.wrappedValue,
                        phase: aggregateStatusPhase,
                        debounceStatus: true,
                        bottomPadding: expansion.wrappedValue ? 0 : transcriptToolRowVerticalPadding
                    )
                }

                if expansion.wrappedValue {
                    TranscriptNestedToolRows(tools: tools)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .appExpansionAnimationOverride(value: tools)
            .appExpansionAnimationOverride(value: expansion.wrappedValue)
        }
    }

    private var expansionBinding: Binding<Bool> {
        externalIsExpanded ?? $isExpanded
    }

    private var summary: String {
        let summaries = categorySummaries
        guard let first = summaries.first else {
            return ""
        }
        let tail = summaries.dropFirst().map(TranscriptToolGroupSummaryFormatter.lowercasedFirstLetter)
        return ([first] + tail).joined(separator: ", ")
    }

    private var aggregateIsError: Bool {
        tools.contains(where: \.isError)
    }

    private var aggregateIsComplete: Bool {
        !tools.isEmpty && tools.allSatisfy(\.isComplete)
    }

    private var aggregateStatusPhase: ToolStatusPhase {
        ToolStatusPhase(isError: aggregateIsError, isComplete: aggregateIsComplete)
    }

    private var categorySummaries: [String] {
        var order: [String] = []
        var counts: [String: Int] = [:]
        for tool in tools {
            let key = TranscriptToolGroupSummaryFormatter.toolCategoryKey(for: tool.name)
            if counts[key] == nil {
                order.append(key)
            }
            counts[key, default: 0] += 1
        }
        return order.map { key in
            TranscriptToolGroupSummaryFormatter.toolCategorySummary(
                for: key,
                count: counts[key] ?? 0,
                isComplete: aggregateIsComplete
            )
        }
    }
}
