import Foundation

struct ReasoningMenuVisualState: Equatable {
    let selection: ReasoningSelection
    let modelGroups: [ReasoningModelGroup]
    let inheritOption: ReasoningInheritOption?

    init(configuration: ReasoningConfiguration) {
        selection = configuration.selection
        modelGroups = configuration.modelGroups
        inheritOption = configuration.inheritChoice?.option
    }
}
