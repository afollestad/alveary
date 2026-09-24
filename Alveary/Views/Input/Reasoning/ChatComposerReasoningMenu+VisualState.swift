import Foundation

struct ReasoningMenuVisualState: Equatable {
    let selection: ReasoningSelection
    let modelGroups: [ReasoningModelGroup]

    init(configuration: ReasoningConfiguration) {
        selection = configuration.selection
        modelGroups = configuration.modelGroups
    }
}
