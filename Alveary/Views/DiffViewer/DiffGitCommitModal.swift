import SwiftUI

/// Octicons do not size by font, so the Commit glyph states its own box; this
/// matches the optical weight of the adjacent SF Symbol at the button's size.
private let diffGitCommitModalOcticonSize: CGFloat = 17

struct DiffGitCommitModal: View {
    @Bindable var model: DiffGitCommitModalModel
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            VStack(alignment: .leading, spacing: 12) {
                if model.branchSelection == .new {
                    AppTextField("Branch name", text: $model.newBranchName)
                        .disabled(model.controlsDisabled)
                }

                AppTextEditor(
                    text: $model.commitMessage,
                    minHeight: model.branchSelection == .new ? 94 : 128,
                    idealHeight: model.branchSelection == .new ? 108 : 142,
                    maxHeight: 180,
                    placeholder: DiffGitCommitModalModel.commitMessagePlaceholder,
                    isDisabled: model.controlsDisabled
                )

                Toggle("Include unstaged changes", isOn: $model.includeUnstagedChanges)
                    .toggleStyle(.checkbox)
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

private extension DiffGitCommitModal {
    var header: some View {
        HStack(alignment: .center, spacing: 12) {
            branchMenu

            Spacer()

            ModalCloseButton("Close git commit modal", action: onClose)
                .disabled(model.isOperationInFlight)
        }
    }

    var branchMenu: some View {
        DiffBranchSelectionMenu(
            baseBranch: model.baseBranch,
            currentBranch: model.currentBranch,
            selectedTitle: model.selectedBranchTitle,
            isBaseSelectable: model.isBaseBranchSelectable,
            isCurrentSelectable: model.isCurrentBranchSelectable,
            isDisabled: model.controlsDisabled,
            accessibilityLabel: "Commit branch",
            onSelectBase: model.selectBaseBranch,
            onSelectCurrent: model.selectCurrentBranch,
            onSelectNew: model.selectNewBranch
        )
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

            Button {
                Task {
                    if await model.perform(commitAndPush: false) {
                        onClose()
                    }
                }
            } label: {
                Label {
                    Text("Commit")
                } icon: {
                    OcticonImage(name: "GitCommitOcticon", size: diffGitCommitModalOcticonSize)
                }
            }
            .secondaryActionButtonStyle()
            .disabled(model.commitButtonDisabled)

            Button {
                Task {
                    if await model.performPrimaryAction() {
                        onClose()
                    }
                }
            } label: {
                Label(model.primaryActionButtonTitle, systemImage: "arrow.up.circle")
            }
            .primaryActionButtonStyle()
            .disabled(model.primaryActionButtonDisabled)
        }
        .frame(minHeight: 32)
    }
}
