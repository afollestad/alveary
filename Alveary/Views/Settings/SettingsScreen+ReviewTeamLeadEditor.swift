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
                SettingsFormRow {
                    SettingsResponsiveControlRow("Harness", horizontalControlSizing: .intrinsic) {
                        SettingsMenuPicker(
                            "Lead harness",
                            selection: harness,
                            options: viewModel.reviewTeamLeadHarnessOptions(draft),
                            label: { viewModel.reviewTeamLeadHarnessLabel($0, settings: draft) }
                        )
                    }
                }

                SettingsFormRow {
                    SettingsResponsiveControlRow("Model", horizontalControlSizing: .intrinsic) {
                        SettingsMenuPicker(
                            "Lead model",
                            selection: model,
                            options: viewModel.reviewTeamLeadModelOptions(draft),
                            label: { viewModel.reviewTeamLeadModelLabel($0, settings: draft) }
                        )
                    }
                }

                SettingsFormRow(showsDivider: false) {
                    SettingsResponsiveControlRow("Effort", horizontalControlSizing: .intrinsic) {
                        SettingsMenuPicker(
                            "Lead effort",
                            selection: effort,
                            options: viewModel.reviewTeamLeadEffortOptions(draft),
                            label: { viewModel.reviewTeamLeadEffortLabel($0, settings: draft) }
                        )
                    }
                }
            }
        }
    }
}

private extension PullRequestReviewLeadEditor {
    var harness: Binding<String> {
        Binding(
            get: { draft.pullRequestReviewHarness ?? SettingsViewModel.pullRequestReviewInheritValue },
            set: { viewModel.setReviewTeamLeadHarness($0, in: &draft) }
        )
    }

    var model: Binding<String> {
        Binding(
            get: { viewModel.reviewTeamLeadModelSelection(draft) },
            set: { viewModel.setReviewTeamLeadModel($0, in: &draft) }
        )
    }

    var effort: Binding<String> {
        Binding(
            get: { draft.pullRequestReviewEffort ?? SettingsViewModel.pullRequestReviewInheritValue },
            set: { draft.pullRequestReviewEffort = $0 == SettingsViewModel.pullRequestReviewInheritValue ? nil : $0 }
        )
    }
}
