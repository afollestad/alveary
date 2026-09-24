import AgentCLIKit
import Foundation

/// A host's stored agent choice; a `nil` field inherits.
struct AgentReasoningPins: Equatable {
    var harnessID: String?
    var model: String?
    var effort: String?

    static let inherited = AgentReasoningPins()
}

/// Renderer-neutral agent choice for a settings-style host, which supplies its own catalogs and stored pins. It decides
/// what the reasoning popover lists and the button reads, and turns each popover pick into the pins the host stores.
///
/// Every pick writes either `AgentReasoningPins.inherited` or a full pin. A stored partial pin still resolves and
/// displays through `effective`, but the popover never creates one, because its model list and effort slider always
/// describe one whole selection.
struct AgentReasoningPresentation: Equatable {
    struct Harness: Equatable {
        let id: String
        let title: String
        /// Already filtered by the host, e.g. to concrete models only.
        let modelOptions: [AgentModelOption]
        /// Set by hosts that launch only concrete models. A stored model such a host would reject reads as a repair row,
        /// not as the catalog model the configured-default fallback would otherwise pick.
        var requiresConcreteModel = false
    }

    /// A whole harness, model, and effort selection, in stored form.
    struct Resolved: Equatable {
        let harness: Harness
        let model: String
        let effort: String
    }

    struct Inheritance: Equatable {
        let title: String
        let target: Resolved
        /// `false` once the host can no longer inherit `target`; a stored inherited choice still shows the row for repair.
        let isOffered: Bool
    }

    enum Availability: Equatable {
        case ready
        case checking
        case unavailable
    }

    /// Harnesses the popover offers, in display order.
    let harnesses: [Harness]
    var pins: AgentReasoningPins
    /// What `pins` resolve to now, which the button and checkmarks describe.
    var effective: Resolved
    var inheritance: Inheritance?
    var isChecking = false

    var isInherited: Bool {
        inheritance != nil && pins == .inherited
    }

    var availability: Availability {
        if isChecking {
            return .checking
        }
        return harnesses.isEmpty ? .unavailable : .ready
    }

    var buttonTitle: String {
        switch availability {
        case .checking:
            return "Checking harnesses…"
        case .unavailable:
            return "No ready harnesses"
        case .ready:
            let title = "\(effective.harness.title) · \(selection.modelTitle)"
            return isInherited ? "Default (\(title))" : title
        }
    }

    /// Effort stays hidden unless the effective model is one the host offers, so the slider cannot pin a harness or
    /// model the popover would not let the user pick.
    var selection: ReasoningSelection {
        Self.selection(for: effective, showsEffort: offersModel(of: effective))
    }

    /// Harnesses with an empty catalog are omitted, except the effective one, whose group keeps a repair row. A model
    /// a concrete-only harness rejects gets a repair row after that harness's catalog.
    var modelGroups: [ReasoningModelGroup] {
        let repair = ReasoningModelOption(harnessID: effective.harness.id, value: selection.modelID, title: selection.modelTitle)
        return harnesses.compactMap { harness in
            let isEffective = harness.id == effective.harness.id
            guard isEffective || !harness.modelOptions.isEmpty else {
                return nil
            }
            let group = ReasoningModelGroup(
                harnessID: harness.id,
                harnessTitle: harness.title,
                modelOptions: harness.modelOptions,
                selectedModel: isEffective ? effective.model : nil
            )
            guard isEffective, isUnmatchedConcreteModel, !group.options.contains(where: { $0.value == repair.value }) else {
                return group
            }
            return ReasoningModelGroup(harnessID: harness.id, harnessTitle: harness.title, options: group.options + [repair])
        }
    }

    var inheritOption: ReasoningInheritOption? {
        guard let inheritance, inheritance.isOffered || isInherited else {
            return nil
        }
        let target = Self.selection(for: inheritance.target, showsEffort: true)
        let detail = [target.harnessTitle, target.modelTitle] + (target.effortOptions.isEmpty ? [] : [target.effortTitle])
        return ReasoningInheritOption(
            title: inheritance.title,
            detail: detail.joined(separator: " · "),
            isSelected: isInherited,
            isEnabled: inheritance.isOffered
        )
    }

    /// The full pin a model-row pick writes, or `nil` for a row this host does not offer. Effort carries over when the
    /// new model supports it and otherwise falls to the model's default, matching the composer.
    func pins(for request: ReasoningModelSelectionRequest) -> AgentReasoningPins? {
        guard let harness = harnesses.first(where: { $0.id == request.harnessID }),
              modelGroups.contains(where: { group in
                  group.harnessID == request.harnessID && group.options.contains { $0.value == request.modelID }
              }) else {
            return nil
        }
        // The repair row has no catalog model to rewrite it as.
        if isUnmatchedConcreteModel, request.harnessID == effective.harness.id, request.modelID == selection.modelID {
            return pins
        }
        let options = harness.modelOptions
        let model = AgentModelOptionSelection.storedModelValue(in: options, matching: request.modelID)
        // Another harness's effort has no meaning here when this model advertises none to check it against.
        let carriesEffort = harness.id == effective.harness.id
            || !AgentModelOptionSelection.effortOptions(in: options, selectedModel: model).isEmpty
        let effort = carriesEffort
            ? AgentModelOptionSelection.normalizedEffort(effective.effort, options: options, selectedModel: model)
            : AgentModelOptionSelection.defaultEffortValue(in: options, selectedModel: model)
        return AgentReasoningPins(harnessID: harness.id, model: model, effort: effort)
    }

    /// Dragging effort pins whatever is effective, including an inherited selection.
    func pins(forEffort effort: String) -> AgentReasoningPins {
        AgentReasoningPins(harnessID: effective.harness.id, model: effective.model, effort: effort)
    }

    /// What the host shows once it stores `pins`, so an accepted pick reports its selection before the host re-renders.
    func applying(_ pins: AgentReasoningPins) -> AgentReasoningPresentation {
        var next = self
        next.pins = pins
        if pins == .inherited, let target = inheritance?.target {
            next.effective = target
        } else if let harness = harnesses.first(where: { $0.id == pins.harnessID }),
                  let model = pins.model,
                  let effort = pins.effort {
            next.effective = Resolved(harness: harness, model: model, effort: effort)
        }
        return next
    }

    private var isUnmatchedConcreteModel: Bool {
        Self.catalog(for: effective).isEmpty && !effective.harness.modelOptions.isEmpty
    }

    private func offersModel(of resolved: Resolved) -> Bool {
        harnesses.contains { $0.id == resolved.harness.id }
            && AgentModelOptionSelection.option(in: Self.catalog(for: resolved), matching: resolved.model) != nil
    }

    /// The catalog `resolved.model` is judged against. It is empty when a concrete-only harness would reject that model,
    /// so the shared matching reads it as unknown instead of falling back to the catalog's first model.
    private static func catalog(for resolved: Resolved) -> [AgentModelOption] {
        let harness = resolved.harness
        guard harness.requiresConcreteModel else {
            return harness.modelOptions
        }
        let model = AppSettings.normalizedModelSelection(resolved.model)
        let matchesExactly = harness.modelOptions.contains { $0.id == model || $0.model == model }
        // Mirrors `PullRequestReviewTeamResolver.resolvedModel`: the configured default counts only as a flagged
        // concrete default, and never for OpenCode.
        let matchesDefault = model == AppSettings.defaultModelValue
            && harness.id != AgentHarnessID.opencode.rawValue
            && harness.modelOptions.contains(where: \.isDefault)
        return matchesExactly || matchesDefault ? harness.modelOptions : []
    }

    private static func selection(for resolved: Resolved, showsEffort: Bool) -> ReasoningSelection {
        let options = catalog(for: resolved)
        let isOpenCode = resolved.harness.id == AgentHarnessID.opencode.rawValue
        return ReasoningSelection(
            harnessID: resolved.harness.id,
            harnessTitle: resolved.harness.title,
            modelOptions: options,
            modelID: AgentModelOptionSelection.pickerValue(in: options, matching: resolved.model),
            effortOptions: showsEffort ? AgentModelOptionSelection.effortOptions(in: options, selectedModel: resolved.model) : [],
            effortValue: isOpenCode ? AppSettings.openCodePickerEffort(stored: resolved.effort) : resolved.effort
        )
    }
}
