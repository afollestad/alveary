import Foundation

struct ReasoningMenuVisualState: Equatable {
    let selection: ChatComposerActionRowView.ReasoningSelection
    let modelGroups: [ChatComposerActionRowView.ReasoningModelGroup]
    let hasStartedThread: Bool

    init(configuration: ChatComposerActionRowView.ReasoningConfiguration) {
        selection = configuration.selection
        modelGroups = configuration.modelGroups
        hasStartedThread = configuration.hasStartedThread
    }
}

extension ChatComposerActionRowView.ReasoningConfiguration {
    func updatingSelection(_ selection: ChatComposerActionRowView.ReasoningSelection) -> Self {
        var copy = self
        copy.selection = selection
        return copy
    }
}
