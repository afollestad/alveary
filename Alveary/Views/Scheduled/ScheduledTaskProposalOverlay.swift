import SwiftUI

struct ScheduledTaskProposalOverlay: View {
    let proposal: ScheduledTaskProposalPresentation
    let coordinator: ScheduledTaskProposalQueueCoordinator
    let scheduledTasksViewModel: ScheduledTasksViewModel

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color.black.opacity(0.46)
                    .ignoresSafeArea()

                modalContent
                    .frame(maxWidth: ScheduledTaskProposalLayout.maximumContentWidth)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    .padding(.horizontal, ScheduledTaskProposalLayout.horizontalInset)
                    .padding(
                        .top,
                        max(
                            ScheduledTaskProposalLayout.titleBarClearance,
                            proxy.safeAreaInsets.top + ScheduledTaskProposalLayout.verticalInset
                        )
                    )
                    .padding(.bottom, ScheduledTaskProposalLayout.verticalInset)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .zIndex(1_000)
        .task(id: proposal.id) {
            await scheduledTasksViewModel.load()
        }
    }

    @ViewBuilder
    private var modalContent: some View {
        if proposal.isEditorProposal,
           proposal.conflictMessage == nil,
           let definitionDraft = proposal.definitionDraft {
            ScheduledTaskProposalEditorModal(
                proposal: proposal,
                definitionDraft: definitionDraft,
                coordinator: coordinator,
                viewModel: scheduledTasksViewModel
            )
            .background(Color(nsColor: .windowBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.standard, style: .continuous))
            .shadow(color: .black.opacity(0.34), radius: 28, x: 0, y: 18)
            .overlay(
                RoundedRectangle(cornerRadius: AppCornerRadius.standard, style: .continuous)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )
        } else {
            actionConfirmationPanel
        }
    }

    private var actionConfirmationPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text(proposal.actionTitle)
                    .font(.title2.weight(.semibold))
                Text(actionDescription)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let conflictMessage = proposal.conflictMessage {
                InlineBanner(
                    message: conflictMessage,
                    severity: .error,
                    autoDismissAfter: nil
                )
                .padding(.top, 20)
            } else if let errorMessage = coordinator.errorMessage {
                InlineBanner(
                    message: errorMessage,
                    severity: .error,
                    autoDismissAfter: nil,
                    onDismiss: coordinator.clearError
                )
                .padding(.top, 20)
            }

            if proposal.targetTitle != nil || proposal.targetScheduleSummary != nil {
                VStack(alignment: .leading, spacing: 6) {
                    if let targetTitle = proposal.targetTitle {
                        Text(targetTitle)
                            .font(.headline)
                    }
                    if let targetScheduleSummary = proposal.targetScheduleSummary {
                        Text(targetScheduleSummary)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.primary.opacity(0.045))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .padding(.top, 20)
            }

            HStack(spacing: 12) {
                Spacer()
                Button("Reject", action: rejectProposal)
                    .secondaryActionButtonStyle()
                    .disabled(coordinator.isResolving)

                confirmButton
            }
            .padding(.top, 24)
        }
        .padding(28)
        .frame(width: 520, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: AppCornerRadius.standard, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor))
                .shadow(color: .black.opacity(0.34), radius: 28, x: 0, y: 18)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppCornerRadius.standard, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Scheduled task proposal")
    }

    @ViewBuilder
    private var confirmButton: some View {
        let button = Button(confirmButtonTitle) {
            coordinator.confirmActionProposal(proposalID: proposal.id)
        }
        .disabled(proposal.conflictMessage != nil || coordinator.isResolving)

        if proposal.action == .delete {
            button.destructiveActionButtonStyle()
        } else {
            button.primaryActionButtonStyle()
        }
    }

    private var confirmButtonTitle: String {
        switch proposal.action {
        case .pause:
            "Confirm pause"
        case .resume:
            "Confirm resume"
        case .delete:
            "Confirm delete"
        case .runNow:
            "Confirm run now"
        case .create, .edit, nil:
            "Confirm"
        }
    }

    private var actionDescription: String {
        switch proposal.action {
        case .pause:
            "Future occurrences will stop until you resume this task. A run already in progress is not changed."
        case .resume:
            "Alveary will resume future occurrences from the current time without replaying paused occurrences."
        case .delete:
            "Future runs will stop. Existing run history and Task threads are retained."
        case .runNow:
            "Alveary will start one run now without resuming or shifting the task's normal cadence."
        case .create, .edit:
            "Review the proposed schedule before applying it."
        case nil:
            "This proposal cannot be read and was not applied."
        }
    }

    private func rejectProposal() {
        coordinator.reject(proposalID: proposal.id)
    }
}

private struct ScheduledTaskProposalEditorModal: View {
    let proposal: ScheduledTaskProposalPresentation
    let coordinator: ScheduledTaskProposalQueueCoordinator
    let viewModel: ScheduledTasksViewModel

    @State private var draft: ScheduledTaskEditorDraft
    @State private var localErrorMessage: String?

    init(
        proposal: ScheduledTaskProposalPresentation,
        definitionDraft: ScheduledTaskProposalDefinitionDraft,
        coordinator: ScheduledTaskProposalQueueCoordinator,
        viewModel: ScheduledTasksViewModel
    ) {
        self.proposal = proposal
        self.coordinator = coordinator
        self.viewModel = viewModel
        _draft = State(initialValue: viewModel.makeProposalDraft(
            definitionDraft,
            definitionID: proposal.targetDefinitionID,
            expectedRevision: proposal.expectedDefinitionRevision
        ))
        _localErrorMessage = State(initialValue: coordinator.errorMessage)
    }

    var body: some View {
        ScheduledTaskEditorContent(
            viewModel: viewModel,
            draft: $draft,
            title: "Review scheduled task proposal",
            subtitle: "Review or adjust the details before Alveary applies anything.",
            submitTitle: proposal.action == .create ? "Confirm and create" : "Confirm changes",
            errorMessage: localErrorMessage ?? coordinator.errorMessage,
            isSubmitting: coordinator.isResolving,
            surface: .modal,
            onDismissError: {
                localErrorMessage = nil
                coordinator.clearError()
            },
            onSubmit: submit,
            onClose: reject
        )
    }

    private func reject() {
        guard !coordinator.reject(proposalID: proposal.id) else {
            return
        }
        localErrorMessage = coordinator.errorMessage
    }

    private func submit() {
        let didConfirm = coordinator.confirmEditorProposal(
            proposalID: proposal.id,
            draft: draft,
            viewModel: viewModel
        )
        if !didConfirm {
            localErrorMessage = coordinator.errorMessage
        }
    }
}

private enum ScheduledTaskProposalLayout {
    static let maximumContentWidth: CGFloat = 700
    static let horizontalInset: CGFloat = 24
    static let verticalInset: CGFloat = 24
    static let titleBarClearance: CGFloat = 52
}
