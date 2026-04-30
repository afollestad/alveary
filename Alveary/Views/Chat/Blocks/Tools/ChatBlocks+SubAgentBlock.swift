import Foundation
import SwiftUI

struct SubAgentBlock: View {
    let agents: [SubAgentEntry]
    let headerFrameID: String?
    private let externalIsExpanded: Binding<Bool>?
    @State private var isExpanded: Bool

    init(
        agents: [SubAgentEntry],
        initiallyExpanded: Bool = false,
        isExpanded: Binding<Bool>? = nil,
        headerFrameID: String? = nil
    ) {
        self.agents = agents
        self.headerFrameID = headerFrameID
        self.externalIsExpanded = isExpanded
        _isExpanded = State(initialValue: initiallyExpanded)
    }

    var body: some View {
        let expansion = expansionBinding
        let toggleExpansion = {
            withAnimation(appExpansionAnimation) {
                expansion.wrappedValue.toggle()
            }
        }
        VStack(alignment: .leading, spacing: 0) {
            AppHeaderToggle(action: toggleExpansion) {
                TranscriptDisclosureHeaderRow(
                    summary: headerSummary,
                    isExpanded: expansion.wrappedValue,
                    phase: aggregateStatusPhase,
                    bottomPadding: expansion.wrappedValue ? 0 : transcriptToolRowVerticalPadding
                )
                .transcriptToolHeaderFramePreference(id: headerFrameID)
            }

            if expansion.wrappedValue {
                expandedContent
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .appExpansionAnimationOverride(value: expansion.wrappedValue)
    }

    private var expansionBinding: Binding<Bool> {
        externalIsExpanded ?? $isExpanded
    }

    @ViewBuilder
    private var expandedContent: some View {
        if agents.count == 1, let agent = agents.first {
            SubAgentExpandedContent(agent: agent)
        } else {
            TranscriptElbowStack(rowIDs: agents.map(\.id)) {
                ForEach(agents) { agent in
                    SubAgentInlineRow(agent: agent, headerPreferenceID: agent.id)
                }
            }
        }
    }

    private var headerSummary: String {
        if agents.count == 1, let agent = agents.first {
            return "\(agent.isComplete ? "Explored" : "Exploring"): \(agent.description)"
        }

        if agents.allSatisfy(\.isComplete) {
            return agents.count == 1 ? "Explored 1 sub-agent" : "Explored \(agents.count) sub-agents"
        }
        return agents.count == 1 ? "Exploring 1 sub-agent" : "Exploring \(agents.count) sub-agents"
    }

    private var aggregateStatusPhase: ToolStatusPhase {
        ToolStatusPhase(
            isError: agents.contains(where: \.hasFailedTool),
            isComplete: !agents.isEmpty && agents.allSatisfy(\.isComplete)
        )
    }
}

private struct SubAgentInlineRow: View {
    let agent: SubAgentEntry
    let headerPreferenceID: String
    @State private var isExpanded = true

    var body: some View {
        let headerBottomPadding = isExpanded ? 0 : transcriptToolRowVerticalPadding
        let toggleExpansion = {
            withAnimation(appExpansionAnimation) {
                isExpanded.toggle()
            }
        }
        VStack(alignment: .leading, spacing: 0) {
            AppHeaderToggle(action: toggleExpansion) {
                TranscriptDisclosureHeaderRow(
                    summary: agent.description,
                    isExpanded: isExpanded,
                    phase: ToolStatusPhase(isError: agent.hasFailedTool, isComplete: agent.isComplete),
                    bottomPadding: headerBottomPadding
                )
                .background {
                    GeometryReader { proxy in
                        Color.clear.preference(
                            key: TranscriptNestedRowCenterPreferenceKey.self,
                            value: [
                                headerPreferenceID: transcriptToolHeaderVisualCenter(
                                    in: proxy.frame(in: .named(transcriptNestedRowsCoordinateSpace)),
                                    bottomPadding: headerBottomPadding
                                )
                            ]
                        )
                    }
                }
            }

            if isExpanded {
                SubAgentExpandedContent(agent: agent)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .appExpansionAnimationOverride(value: isExpanded)
    }
}

private struct SubAgentExpandedContent: View {
    let agent: SubAgentEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !agent.tools.isEmpty {
                TranscriptNestedToolRows(tools: agent.tools)
            }

            if let result = agent.result,
               !result.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                DetailCodeBlock(title: "Result", content: result)
                    .padding(.top, agent.tools.isEmpty ? transcriptToolExpandedContentTopSpacing : 0)
                    .padding(.bottom, toolExpandedContentBottomSpacing)
                    .padding(.leading, transcriptToolDetailLeadingInset)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private extension SubAgentEntry {
    var hasFailedTool: Bool {
        tools.contains(where: \.isError)
    }
}
