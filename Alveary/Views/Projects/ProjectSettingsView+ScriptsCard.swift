import SwiftUI

struct ProjectSettingsWorktreesCard: View {
    @Binding var setupScript: String
    @Binding var teardownScript: String
    let patterns: [String]
    let bindingForPattern: (Int) -> Binding<String>
    let onRemovePattern: (Int) -> Void

    var body: some View {
        ProjectSettingsSection(title: "Worktrees") {
            VStack(alignment: .leading, spacing: 14) {
                ProjectSettingsScriptsLayout {
                    ProjectSettingsScriptField(
                        title: "Setup command",
                        helpText: "Runs in each new worktree after files are copied.",
                        text: $setupScript
                    )
                    ProjectSettingsScriptField(
                        title: "Cleanup command",
                        helpText: "Runs in the worktree before it is removed.",
                        text: $teardownScript
                    )
                }

                Divider()

                ProjectSettingsPreservePatternsCard(
                    patterns: patterns,
                    bindingForPattern: bindingForPattern,
                    onRemovePattern: onRemovePattern
                )
            }
        }
    }
}

private struct ProjectSettingsScriptField: View {
    let title: String
    let helpText: String
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline.weight(.medium))
                .accessibilityHidden(true)

            AppTextField(
                title,
                text: $text,
                showsPrompt: false,
                horizontalPadding: 10,
                verticalPadding: ProjectSettingsLayout.fieldVerticalPadding
            )
            .font(.body.monospaced())
            .accessibilityHint(helpText + " Optional.")

            Text(helpText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Reflow the same fields so resizing cannot replace their native editors or discard keyboard focus.
private struct ProjectSettingsScriptsLayout: Layout {
    private let spacing: CGFloat = 14

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard subviews.count == 2 else { return .zero }
        let width = max(proposal.width ?? ProjectSettingsLayout.compactBreakpoint, 0)
        let isHorizontal = width >= ProjectSettingsLayout.compactBreakpoint
        let fieldWidth = isHorizontal ? max((width - spacing) / 2, 0) : width
        let fieldProposal = ProposedViewSize(width: fieldWidth, height: nil)
        let first = subviews[0].sizeThatFits(fieldProposal)
        let second = subviews[1].sizeThatFits(fieldProposal)
        return CGSize(
            width: width,
            height: isHorizontal ? max(first.height, second.height) : first.height + spacing + second.height
        )
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard subviews.count == 2 else { return }
        let isHorizontal = bounds.width >= ProjectSettingsLayout.compactBreakpoint
        let fieldWidth = isHorizontal ? max((bounds.width - spacing) / 2, 0) : bounds.width
        let fieldProposal = ProposedViewSize(width: fieldWidth, height: nil)
        subviews[0].place(at: bounds.origin, anchor: .topLeading, proposal: fieldProposal)
        let secondOrigin = isHorizontal
            ? CGPoint(x: bounds.minX + fieldWidth + spacing, y: bounds.minY)
            : CGPoint(x: bounds.minX, y: bounds.minY + subviews[0].sizeThatFits(fieldProposal).height + spacing)
        subviews[1].place(at: secondOrigin, anchor: .topLeading, proposal: fieldProposal)
    }
}
