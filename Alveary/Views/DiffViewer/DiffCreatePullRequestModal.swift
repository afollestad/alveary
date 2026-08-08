import SwiftUI

struct DiffCreatePullRequestModal: View {
    @Bindable var model: DiffCreatePullRequestModalModel
    /// Called with the created identifier so the root can link it and open its
    /// pane; plain close passes nothing.
    let onCreated: (PullRequestIdentifier) -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            VStack(alignment: .leading, spacing: 12) {
                if model.branchSelection == .new {
                    AppTextField("Branch name", text: $model.newBranchName)
                        .disabled(model.controlsDisabled)
                }

                AppTextField(DiffCreatePullRequestModalModel.titlePlaceholder, text: $model.title)
                    .disabled(model.controlsDisabled)

                // The shared BlockInputKit editor: four visible lines, growing
                // to its built-in ten-line cap. Never wrap it in a drop
                // modifier — see `Alveary/Views/PullRequests/AGENTS.md`.
                PullRequestCommentEditor(
                    draft: model.descriptionDraft,
                    placeholder: DiffCreatePullRequestModalModel.descriptionPlaceholder,
                    minimumVisibleLineCount: 4
                )
                .disabled(model.controlsDisabled)
            }

            if let preflightMessage = model.preflightMessage {
                InlineBanner(
                    message: preflightMessage,
                    severity: .warning,
                    autoDismissAfter: nil
                )
            }

            if let errorMessage = model.errorMessage {
                InlineBanner(
                    message: errorMessage,
                    severity: .error,
                    autoDismissAfter: nil,
                    onDismiss: { model.errorMessage = nil }
                )
            }

            Divider()

            footer
        }
        .padding(24)
        .frame(width: 560)
        .task {
            await model.load()
        }
        .interactiveDismissDisabled(model.isOperationInFlight)
    }
}

private extension DiffCreatePullRequestModal {
    var header: some View {
        HStack(alignment: .center, spacing: 12) {
            DiffBranchSelectionMenu(
                baseBranch: model.baseBranch,
                currentBranch: model.currentBranch,
                selectedTitle: model.selectedBranchTitle,
                isBaseSelectable: model.isBaseBranchSelectable,
                isCurrentSelectable: model.isCurrentBranchSelectable,
                isDisabled: model.controlsDisabled,
                accessibilityLabel: "Pull request branch",
                // Base is never selectable for a pull request (base into base),
                // so the menu's base row stays disabled context.
                onSelectBase: {},
                onSelectCurrent: model.selectCurrentBranch,
                onSelectNew: model.selectNewBranch
            )

            Spacer()

            ModalCloseButton("Close create pull request modal", action: onClose)
                .disabled(model.isOperationInFlight)
        }
    }

    var footer: some View {
        HStack(spacing: 12) {
            if let statusMessage = model.statusMessage {
                HStack(spacing: 8) {
                    StatusIndicatorSpinner(
                        color: .secondary,
                        diameter: 16,
                        lineWidth: 2
                    )
                    Text(statusMessage)
                        .foregroundStyle(.secondary)
                }
                .font(.subheadline)
            }

            Spacer()

            Button(action: onClose) {
                ActionButtonLabel(title: "Cancel", icon: .system("xmark"))
            }
            .secondaryActionButtonStyle()
            .disabled(model.isOperationInFlight)

            Button {
                Task {
                    if let identifier = await model.submit() {
                        onCreated(identifier)
                    }
                }
            } label: {
                ActionButtonLabel(
                    title: "Create pull request",
                    icon: .octicon(.pullRequest16)
                )
            }
            .primaryActionButtonStyle()
            .disabled(model.createButtonDisabled)
        }
        .frame(minHeight: 32)
    }
}
