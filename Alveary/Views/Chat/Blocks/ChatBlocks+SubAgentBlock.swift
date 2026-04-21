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
        // Route the `DisclosureGroup` binding through a `withAnimation`-wrapping
        // setter so the enclosing `LazyVStack`'s sibling reflow eases in step with
        // the block's expand/collapse. `DisclosureGroup` animates its own content
        // reveal, but it is not guaranteed to wrap the user-tap binding write in
        // `withAnimation`, so — as with the tool-bubble rows — the next transcript
        // item could otherwise snap to its new position while this block is still
        // mid-animate. Matches the pattern documented for tool bubbles in AGENTS.md.
        //
        // Caveat: if `DisclosureGroup` *does* wrap internally, our explicit
        // `withAnimation(toolExpansionAnimation)` replaces that inner animation for
        // the same update, so the content-reveal curve becomes whatever
        // `toolExpansionAnimation` is set to (see `ChatBlocks.swift`) instead of
        // Apple's default. That's intentional — it keeps sub-agent and tool-bubble
        // expansion timing consistent — but worth revisiting if Apple's default
        // starts to feel materially different in a future SwiftUI release.
        DisclosureGroup(
            isExpanded: Binding(
                get: { isExpanded },
                set: { newValue in
                    withAnimation(toolExpansionAnimation) {
                        isExpanded = newValue
                    }
                }
            )
        ) {
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
        // Match the tool-bubble pattern: the `withAnimation` in the binding's
        // setter drives inactive-turn animation, and this override re-enables it
        // within the bubble's subtree during active turns (when the transcript's
        // `.transaction { $0.disablesAnimations = true }` would otherwise snap the
        // block). Without this, a user toggle during streaming would snap the
        // `SubAgentBlock` while tool bubbles continued to ease.
        .toolAnimationOverride(value: isExpanded)
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
