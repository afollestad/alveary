import AgentCLIKit
import SwiftUI

/// The Git tab's agentic-review agent settings. Each picker offers a leading "Default" row
/// meaning "follow the Threads tab", which is what `nil` persists as; only an explicit pick
/// pins the review to a provider, model, or effort of its own.
extension SettingsViewModel {
    /// Distinct from `AppSettings.defaultModelValue`, which means "the provider's default
    /// model" — a narrower claim than "follow the Threads defaults".
    static let pullRequestReviewInheritValue = "alveary.inherit"

    var pullRequestReviewPrompt: String {
        get { settingsService.current.pullRequestReviewPrompt }
        set { settingsService.update { $0.pullRequestReviewPrompt = newValue } }
    }

    /// The provider the review's model and effort options are read from: the pinned one while
    /// it is ready, otherwise whatever the Threads defaults resolve to.
    var pullRequestReviewEffectiveProviderID: String {
        guard let pinned = settingsService.current.pullRequestReviewProvider,
              threadDefaultProviderIDs.contains(pinned) else {
            return threadDefaultProviderSelection
        }
        return pinned
    }

    var pullRequestReviewProviderSelection: String {
        settingsService.current.pullRequestReviewProvider ?? Self.pullRequestReviewInheritValue
    }

    var pullRequestReviewProviderOptions: [String] {
        [Self.pullRequestReviewInheritValue] + threadDefaultProviderIDs
    }

    /// Model and effort are provider-scoped, so pinning a different provider clears both in the
    /// same write — a model from the old provider would not exist on the new one.
    func setPullRequestReviewProvider(_ value: String) {
        settingsService.update { settings in
            settings.pullRequestReviewProvider = value == Self.pullRequestReviewInheritValue ? nil : value
            settings.pullRequestReviewModel = nil
            settings.pullRequestReviewEffort = nil
        }
    }

    var pullRequestReviewModelSelection: String {
        guard let stored = settingsService.current.pullRequestReviewModel else {
            return Self.pullRequestReviewInheritValue
        }
        return AgentModelOptionSelection.pickerValue(
            in: modelOptions(for: pullRequestReviewEffectiveProviderID),
            matching: stored
        )
    }

    var pullRequestReviewModelOptions: [String] {
        let values = modelOptionValues(for: pullRequestReviewEffectiveProviderID)
        // The filter keeps the sentinel unique in the picker. The sentinel is `alveary.inherit`
        // rather than `default` because providers offer `default` as a real catalog row meaning
        // their own default model — a different claim than "follow the Threads defaults".
        return [Self.pullRequestReviewInheritValue] + values.filter { $0 != Self.pullRequestReviewInheritValue }
    }

    func setPullRequestReviewModel(_ value: String) {
        guard value != Self.pullRequestReviewInheritValue else {
            settingsService.update { settings in
                settings.pullRequestReviewModel = nil
                settings.pullRequestReviewEffort = nil
            }
            return
        }
        let options = modelOptions(for: pullRequestReviewEffectiveProviderID)
        let storedModel = AgentModelOptionSelection.storedModelValue(in: options, matching: value)
        settingsService.update { settings in
            settings.pullRequestReviewModel = storedModel
            // An effort the new model does not support would silently degrade at spawn time;
            // clearing it here makes the picker show what will actually be used.
            let supported = AgentModelOptionSelection.effortOptions(in: options, selectedModel: storedModel)
            if let effort = settings.pullRequestReviewEffort,
               !supported.isEmpty,
               !supported.contains(where: { $0.value == effort }) {
                settings.pullRequestReviewEffort = nil
            }
        }
    }

    var pullRequestReviewEffortSelection: String {
        settingsService.current.pullRequestReviewEffort ?? Self.pullRequestReviewInheritValue
    }

    var pullRequestReviewEffortOptions: [AgentProviderOption] {
        AgentModelOptionSelection.effortOptions(
            in: modelOptions(for: pullRequestReviewEffectiveProviderID),
            selectedModel: settingsService.current.pullRequestReviewModel
        )
    }

    func setPullRequestReviewEffort(_ value: String) {
        settingsService.update { settings in
            settings.pullRequestReviewEffort = value == Self.pullRequestReviewInheritValue ? nil : value
        }
    }

    /// One label for every picker's inherit row, so all three read the same.
    func pullRequestReviewLabel(forProvider value: String) -> String {
        value == Self.pullRequestReviewInheritValue ? "Default" : providerDisplayName(for: value)
    }

    func pullRequestReviewLabel(forModel value: String) -> String {
        value == Self.pullRequestReviewInheritValue
            ? "Default"
            : modelLabel(for: value, providerId: pullRequestReviewEffectiveProviderID)
    }

    func pullRequestReviewLabel(forEffort value: String) -> String {
        guard value != Self.pullRequestReviewInheritValue else {
            return "Default"
        }
        return pullRequestReviewEffortOptions.first { $0.value == value }?.label
            ?? ChatComposerTextSupport.effortLabel(for: value)
    }
}
