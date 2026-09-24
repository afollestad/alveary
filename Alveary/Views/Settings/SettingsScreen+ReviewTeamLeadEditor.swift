import SwiftUI

struct PullRequestReviewLeadEditor: View {
    let viewModel: SettingsViewModel
    @Binding var draft: AppSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Lead")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            Text("Reviews, votes, and synthesizes. All reviewers run read-only.")
                .font(.caption)
                .foregroundStyle(.secondary)

            SettingsFormSection {
                SettingsFormRow(showsDivider: false) {
                    SettingsResponsiveControlRow("Agent", horizontalControlSizing: .selectedContent) {
                        SettingsAgentSelector(
                            accessibilityLabel: "Lead agent",
                            presentation: viewModel.reviewTeamLeadPresentation(draft),
                            apply: { viewModel.applyReviewTeamLead($0, in: &draft) }
                        )
                    }
                }
            }
        }
    }
}
