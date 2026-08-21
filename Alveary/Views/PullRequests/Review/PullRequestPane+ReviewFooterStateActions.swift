import SwiftUI

/// The footer's state-change half: which of GitHub's close/reopen/draft transitions this pull
/// request currently allows, and the button that runs the selected one.
///
/// Split from `PullRequestPane+ReviewFooter.swift` to keep both files inside the 500-line limit;
/// `PullRequestStateAction` owns the availability policy itself. `stateActions`,
/// `effectiveStateAction`, and `stateActionButton` are internal rather than private because the
/// footer's own `actionRow` and `footerNotes` call them from that file.
extension PullRequestPaneReviewFooter {
    /// While the detail is unavailable the row still shows its even split, with
    /// a disabled stand-in titled from the list row's known status — otherwise
    /// the footer paints a lone trailing button and snaps once the detail lands.
    /// An identifier-opened pane has no status to title one with until then.
    var stateActions: [PullRequestStateAction] {
        guard session.detail != nil else {
            guard let status = session.summary?.status else {
                return []
            }
            return PullRequestStateAction.placeholder(for: status).map { [$0] } ?? []
        }
        return PullRequestStateAction.available(for: session.detail)
    }

    /// The selection falls back to the default whenever it no longer matches an
    /// available action — which is what retires "Ready for review" the moment
    /// the pull request leaves draft. Same guard as `effectiveEvent`.
    var effectiveStateAction: PullRequestStateAction? {
        let actions = stateActions
        return actions.first { $0.kind == selectedStateKind } ?? actions.first
    }

    /// A single available action stays a plain button; more than one becomes the
    /// shared split button, whose menu selects (never runs) the other action.
    @ViewBuilder
    func stateActionButton(
        _ action: PullRequestStateAction,
        in actions: [PullRequestStateAction]
    ) -> some View {
        if actions.count > 1 {
            SplitActionButton(
                title: action.title,
                icon: action.icon,
                emphasis: action.isDestructive ? .destructive : .secondary,
                expandsHorizontally: true,
                selectedOption: action.kind,
                options: actions.map(\.kind),
                optionTitle: { kind in actions.first { $0.kind == kind }?.title ?? "" },
                action: { run(action) },
                selectOption: { selectedStateKind = $0 }
            )
            .disabled(!action.isEnabled || session.isChangingState)
            .help(action.disabledNote ?? action.title)
        } else {
            plainStateActionButton(action)
        }
    }

    @ViewBuilder
    private func plainStateActionButton(_ action: PullRequestStateAction) -> some View {
        let button = Button {
            run(action)
        } label: {
            ActionButtonLabel(title: action.title, icon: action.icon)
        }
        .disabled(!action.isEnabled || session.isChangingState)
        .help(action.disabledNote ?? action.title)

        if action.isDestructive {
            button.destructiveActionButtonStyle(expandsHorizontally: true)
        } else {
            button.secondaryActionButtonStyle(expandsHorizontally: true)
        }
    }

    private func run(_ action: PullRequestStateAction) {
        switch action.kind {
        case .close:
            viewModel.setPullRequestClosed(true)
        case .reopen:
            viewModel.setPullRequestClosed(false)
        case .markReady:
            viewModel.markPullRequestReadyForReview()
        case .markDraft:
            viewModel.convertPullRequestToDraft()
        }
    }
}
