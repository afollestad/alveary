import AgentCLIKit
import Foundation

enum AgentModelOptionSelection {
    static func pickerValue(for option: AgentCLIKit.AgentModelOption) -> String {
        option.id
    }

    static func storedModelValue(for option: AgentCLIKit.AgentModelOption) -> String {
        option.model ?? AppSettings.defaultModelValue
    }

    static func option(
        in options: [AgentCLIKit.AgentModelOption],
        matching selection: String?
    ) -> AgentCLIKit.AgentModelOption? {
        let trimmed = selection?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let trimmed, !trimmed.isEmpty else {
            return defaultOption(in: options)
        }
        if let exact = options.first(where: { $0.id == trimmed || $0.model == trimmed }) {
            return exact
        }
        if trimmed == AppSettings.defaultModelValue {
            return defaultOption(in: options)
        }
        return nil
    }

    static func pickerValue(
        in options: [AgentCLIKit.AgentModelOption],
        matching selection: String?
    ) -> String {
        if let option = option(in: options, matching: selection) {
            return pickerValue(for: option)
        }
        return AppSettings.normalizedModelSelection(selection)
    }

    static func storedModelValue(
        in options: [AgentCLIKit.AgentModelOption],
        matching pickerValue: String
    ) -> String {
        if let option = option(in: options, matching: pickerValue) {
            return storedModelValue(for: option)
        }
        return AppSettings.normalizedModelSelection(pickerValue)
    }

    static func effortOptions(
        in options: [AgentCLIKit.AgentModelOption],
        selectedModel: String?
    ) -> [AgentCLIKit.AgentProviderOption] {
        option(in: options, matching: selectedModel)?.supportedEffortOptions ?? []
    }

    static func defaultEffortValue(
        in options: [AgentCLIKit.AgentModelOption],
        selectedModel: String?
    ) -> String {
        let selectedOption = option(in: options, matching: selectedModel)
        return selectedOption?.defaultEffortOption?.value
            ?? selectedOption?.supportedEffortOptions.first?.value
            ?? AppSettings.defaultEffortLevel
    }

    static func normalizedEffort(
        _ effort: String?,
        options: [AgentCLIKit.AgentModelOption],
        selectedModel: String?
    ) -> String {
        let normalized = AppSettings.normalizedEffortLevel(effort)
        let effortOptions = effortOptions(in: options, selectedModel: selectedModel)
        guard !effortOptions.isEmpty else {
            return normalized
        }
        if effortOptions.contains(where: { $0.value == normalized }) {
            return normalized
        }
        return defaultEffortValue(in: options, selectedModel: selectedModel)
    }

    private static func defaultOption(
        in options: [AgentCLIKit.AgentModelOption]
    ) -> AgentCLIKit.AgentModelOption? {
        options.first(where: \.isDefault)
            ?? options.first(where: { $0.id == AppSettings.defaultModelValue || $0.model == nil })
            ?? options.first
    }
}

extension AppSettings {
    static func normalizedModelSelection(_ model: String?) -> String {
        let trimmed = model?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? defaultModelValue : trimmed
    }
}
