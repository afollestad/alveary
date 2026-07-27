import Foundation

extension ChatComposerActionRowView {
    struct ReasoningSelection: Equatable {
        let providerID: String
        let providerTitle: String
        let modelID: String
        let modelTitle: String
        let effortValue: String
        let effortTitle: String
        let effortOptions: [MenuOption]
        let defaultEffortValue: String?
        let speedMode: AgentSpeedMode
        let supportsSpeedMode: Bool

        var accessibilityValue: String {
            let reasoningValue = effortOptions.isEmpty ? modelTitle : "\(modelTitle), \(effortTitle)"
            guard supportsSpeedMode, speedMode == .fast else {
                return reasoningValue
            }
            return "\(reasoningValue), Fast"
        }
    }

    struct ReasoningModelOption: Equatable {
        let providerID: String
        let value: String
        let title: String
        /// Provider-supplied alias the `/model` command accepts as typed input.
        let shortName: String

        init(providerID: String, value: String, title: String, shortName: String? = nil) {
            self.providerID = providerID
            self.value = value
            self.title = title
            self.shortName = shortName ?? value
        }

        var identity: String {
            // Model IDs such as `default` can appear under multiple providers.
            "\(providerID):\(value)"
        }
    }

    struct ReasoningModelGroup: Equatable {
        let providerID: String
        let providerTitle: String?
        let options: [ReasoningModelOption]
    }
}
