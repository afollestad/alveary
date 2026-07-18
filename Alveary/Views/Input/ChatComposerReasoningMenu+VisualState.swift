import Foundation

struct ReasoningMenuVisualState: Equatable {
    let selection: ChatComposerActionRowView.ReasoningSelection
    let modelGroups: [ChatComposerActionRowView.ReasoningModelGroup]

    init(configuration: ChatComposerActionRowView.ReasoningConfiguration) {
        selection = configuration.selection
        modelGroups = configuration.modelGroups
    }
}
