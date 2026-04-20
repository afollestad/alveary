import Foundation
import SwiftUI

struct SubAgentBlock: View {
    let agents: [SubAgentEntry]
    @State private var isExpanded = false

    @Environment(\.transcriptBubbleMaxWidth) private var bubbleMaxWidth

    private var runningCount: Int {
        agents.filter { !$0.isComplete }.count
    }

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(agents) { agent in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 10) {
                            Circle()
                                .fill(agent.isComplete ? Color.green : Color.blue)
                                .frame(width: 8, height: 8)

                            Text(agent.description)
                                .font(.subheadline.weight(.semibold))

                            Spacer()

                            Text(summary(for: agent))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        if let status = agent.statusDescription ?? agent.lastToolName {
                            Text(status)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        if !agent.tools.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                ForEach(agent.tools) { tool in
                                    InlineToolRow(tool: tool)
                                }
                            }
                        }

                        if let result = agent.result,
                           !result.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            DetailCodeBlock(title: "Result", content: result)
                        }
                    }
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: chatBlockCornerRadius, style: .continuous)
                            .fill(Color.secondary.opacity(0.06))
                    )
                }
            }
            .padding(.top, 12)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(runningCount == 0 ? "Sub-agents finished" : "Running \(runningCount) of \(agents.count) sub-agents")
                    .font(.headline)

                Text("\(agents.count) agent\(agents.count == 1 ? "" : "s")")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(chatBlockPadding)
        .bubbleBackground(maxWidth: bubbleMaxWidth)
    }

    private func summary(for agent: SubAgentEntry) -> String {
        let tokens = tokenLabel(agent.totalTokens)
        return "\(agent.toolUseCount) tools · \(tokens)"
    }

    private func tokenLabel(_ count: Int) -> String {
        if count >= 1_000 {
            return String(format: "%.1fk tokens", Double(count) / 1_000)
        }
        return "\(count) tokens"
    }
}
