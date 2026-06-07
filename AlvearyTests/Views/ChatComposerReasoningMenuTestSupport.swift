import AppKit

@testable import Alveary

@MainActor
func makeGroupedReasoningModelGroups() -> [ChatComposerActionRowView.ReasoningModelGroup] {
    [
        .init(
            providerID: "claude",
            providerTitle: "Claude Code",
            options: [.init(providerID: "claude", value: AppSettings.defaultModelValue, title: "Provider default")]
        ),
        .init(
            providerID: "codex",
            providerTitle: "Codex",
            options: [.init(providerID: "codex", value: "gpt-5.5", title: "GPT-5.5")]
        )
    ]
}

@MainActor
func makeGroupedReasoningModelMenu(
    onModelSelected: @escaping (ChatComposerActionRowView.ReasoningModelSelectionRequest) -> Void = { _ in }
) -> ComposerReasoningModelMenuViewController {
    ComposerReasoningModelMenuViewController(
        groups: makeGroupedReasoningModelGroups(),
        selectedProviderID: "claude",
        selectedModelID: AppSettings.defaultModelValue,
        showsProviderHeaders: true,
        onModelSelected: onModelSelected,
        onHoverChanged: { _ in },
        onCancel: {}
    )
}
