import Foundation

extension ChatComposerActionRowView {
    struct ReasoningSelection: Equatable {
        let harnessID: String
        let harnessTitle: String
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
        let harnessID: String
        let value: String
        let title: String
        /// Harness-supplied alias the `/model` command accepts as typed input.
        let shortName: String

        init(harnessID: String, value: String, title: String, shortName: String? = nil) {
            self.harnessID = harnessID
            self.value = value
            self.title = title
            self.shortName = shortName ?? value
        }

        var identity: String {
            // Model IDs such as `default` can appear under multiple harnesses.
            "\(harnessID):\(value)"
        }
    }

    struct ReasoningModelGroup: Equatable {
        let harnessID: String
        let harnessTitle: String?
        let options: [ReasoningModelOption]
    }
}
