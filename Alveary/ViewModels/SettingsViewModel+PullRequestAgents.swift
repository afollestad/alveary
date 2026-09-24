import AgentCLIKit
import SwiftUI

/// Each route owns its pins; the editor shares only harness-dependent picker behavior.
extension SettingsViewModel {
    var reviewAgentEditor: PullRequestAgentSettingsEditor {
        PullRequestAgentSettingsEditor(viewModel: self, kind: .review)
    }

    var addressFeedbackAgentEditor: PullRequestAgentSettingsEditor {
        PullRequestAgentSettingsEditor(viewModel: self, kind: .addressFeedback)
    }
}

/// A value adapter keeps edits in the view model and applies dependent resets atomically to one route.
@MainActor
struct PullRequestAgentSettingsEditor {
    let viewModel: SettingsViewModel
    let kind: PullRequestAgenticThreadService.Kind

    var effectiveHarnessID: String { effectiveHarnessID(pinned: settings.harness) }

    /// Resolves through `PullRequestAgenticThreadService.resolveSeedSettings`, so the button reads what the route
    /// launches, including a stale pin's fallback.
    var presentation: AgentReasoningPresentation {
        let harnessID = effectiveHarnessID
        let seed = PullRequestAgenticThreadService.resolveSeedSettings(
            settings: viewModel.settingsService.current,
            resolution: viewModel.threadDefaultResolution,
            harness: harnessID,
            modelOptions: viewModel.modelOptions(for: harnessID),
            kind: kind
        )
        return AgentReasoningPresentation(
            harnesses: viewModel.threadDefaultHarnessIDs.map { viewModel.agentReasoningHarness(for: $0) },
            pins: .init(harnessID: settings.harness, model: settings.model, effort: settings.effort),
            effective: .init(
                harness: viewModel.agentReasoningHarness(for: harnessID),
                model: seed.model ?? AppSettings.defaultModelValue,
                effort: seed.effort
            ),
            inheritance: .init(title: "Threads default", target: viewModel.threadDefaultResolvedAgent, isOffered: true),
            isChecking: viewModel.isCheckingThreadDefaultHarnesses
        )
    }

    /// Permissions are harness-scoped, so only a pick that changes the effective harness clears the permission pin.
    func apply(_ pins: AgentReasoningPins) -> Bool {
        let changesHarness = effectiveHarnessID(pinned: pins.harnessID) != effectiveHarnessID
        update {
            $0.harness = pins.harnessID
            $0.model = pins.model
            $0.effort = pins.effort
            if changesHarness {
                $0.permissionMode = nil
            }
        }
        return true
    }

    /// Unsupported pins display the inherited choice without mutating settings during a read.
    var permissionSelection: String {
        guard let stored = settings.permissionMode, permissionOptions.contains(stored) else { return inheritValue }
        return stored
    }

    var permissionOptions: [String] {
        [inheritValue] + viewModel.permissionModeOptions(for: effectiveHarnessID)
    }

    func setPermission(_ value: String) {
        update { $0.permissionMode = value == inheritValue ? nil : value }
    }

    func label(forPermission value: String) -> String {
        guard value != inheritValue else { return "Use thread default" }
        let harness = effectiveHarnessID
        if HarnessFeaturePolicy.launchIsolation(requested: kind.integrationIsolation, harnessID: harness).contains(.shellNetwork),
           let sandboxed = ChatComposerPermissionPresentation.sandboxedWording(harnessID: harness, value: value) {
            // Every review task launches sandboxed, so the route's pick means what the task will actually do.
            return sandboxed.title
        }
        let label = viewModel.permissionModeLabel(for: value, harnessId: harness)
        // A concrete harness default is different from inheriting Threads settings.
        return label == "Default" ? "Default (\(viewModel.harnessDisplayName(for: harness)))" : label
    }

    private var inheritValue: String { SettingsViewModel.pullRequestReviewInheritValue }
    private var path: WritableKeyPath<AppSettings, PullRequestAgentSettings> {
        kind == .review ? \.pullRequestReviewAgent : \.pullRequestAddressFeedbackAgent
    }
    private var settings: PullRequestAgentSettings { viewModel.settingsService.current[keyPath: path] }

    /// A pinned OpenCode stays effective while unavailable so its pin can be repaired; other pins fall back.
    private func effectiveHarnessID(pinned: String?) -> String {
        if pinned == "opencode" { return "opencode" }
        guard let pinned, viewModel.threadDefaultHarnessIDs.contains(pinned) else {
            return viewModel.threadDefaultHarnessSelection
        }
        return pinned
    }

    private func update(_ transform: (inout PullRequestAgentSettings) -> Void) {
        viewModel.settingsService.update { transform(&$0[keyPath: path]) }
    }
}
