import SwiftUI

/// The Git changes pane's action footer: one full-width button walking the
/// branch workflow (Commit → Push changes → Create PR / View PR), with the
/// other still-valid actions behind the split button's caret.
struct DiffViewerPaneFooter: View {
    let actions: [DiffViewerFooterAction]
    /// Disables the row while a push runs so it cannot double-fire.
    let isPerformingAction: Bool
    let onAction: (DiffViewerFooterAction.Kind) -> Void

    /// Nil takes the default action; a stale pick falls back the same way.
    @State private var selectedKind: DiffViewerFooterAction.Kind?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            actionRow
        }
        .contextualPaneFooterChrome()
    }

    /// The selection falls back to the first available action whenever it no
    /// longer matches one — which is what retires a vanished rung the moment
    /// the repository moves past it. Same guard as the pull-request footer's
    /// `effectiveStateAction`.
    private var effectiveAction: DiffViewerFooterAction? {
        actions.first { $0.kind == selectedKind } ?? actions.first
    }

    @ViewBuilder
    private var actionRow: some View {
        if let action = effectiveAction {
            if actions.count > 1 {
                splitButton(for: action)
            } else {
                Button(action.title) {
                    onAction(action.kind)
                }
                .primaryActionButtonStyle(expandsHorizontally: true)
                .disabled(!action.isEnabled || isPerformingAction)
            }
        } else {
            Button(DiffViewerFooterAction.placeholder.title) {}
                .primaryActionButtonStyle(expandsHorizontally: true)
                .disabled(true)
        }
    }

    /// `.primary` is correct here even though the PR footer's split button
    /// takes `.secondary`: this is the row's only button, so there is no
    /// second accent voice to avoid.
    private func splitButton(for action: DiffViewerFooterAction) -> some View {
        SplitActionButton(
            title: action.title,
            emphasis: .primary,
            expandsHorizontally: true,
            selectedOption: action.kind,
            options: actions.map(\.kind),
            optionTitle: { kind in actions.first { $0.kind == kind }?.title ?? "" },
            action: { onAction(action.kind) },
            selectOption: { selectedKind = $0 }
        )
        .disabled(!action.isEnabled || isPerformingAction)
        .help(action.title)
    }
}
