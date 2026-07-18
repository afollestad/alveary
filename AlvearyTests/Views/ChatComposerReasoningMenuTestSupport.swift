import AppKit

@testable import Alveary

@MainActor
func makeGroupedReasoningModelGroups() -> [ChatComposerActionRowView.ReasoningModelGroup] {
    [
        .init(
            providerID: "claude",
            providerTitle: "Claude Code",
            options: [.init(providerID: "claude", value: "sonnet", title: "Sonnet")]
        ),
        .init(
            providerID: "codex",
            providerTitle: "Codex",
            options: [.init(providerID: "codex", value: "gpt-5.5", title: "GPT-5.5")]
        )
    ]
}

@MainActor
func makeGroupedReasoningConfiguration(
    selectedProviderID: String = "claude",
    selectedModelID: String = "sonnet",
    selectedEffort: String = "medium",
    selectedSpeedMode: AgentSpeedMode = .standard,
    supportsSpeedMode: Bool = false,
    onEffortChange: @escaping (String) -> Bool = { _ in true },
    onSpeedChange: @escaping (AgentSpeedMode) -> Bool = { _ in true },
    onModelChange: @escaping (ChatComposerActionRowView.ReasoningModelSelectionRequest)
        -> ChatComposerActionRowView.ReasoningModelSelectionOutcome = { _ in .rejected }
) -> ChatComposerActionRowView.ReasoningConfiguration {
    let groups = makeGroupedReasoningModelGroups()
    return makeReasoningConfiguration(
        providerOptions: groups.map {
            .init(value: $0.providerID, title: $0.providerTitle ?? $0.providerID.capitalized)
        },
        modelGroups: groups,
        effortOptions: [
            .init(value: "low", title: "Low"),
            .init(value: "medium", title: "Medium"),
            .init(value: "high", title: "High")
        ],
        selectedProvider: selectedProviderID,
        selectedModel: selectedModelID,
        selectedEffort: selectedEffort,
        selectedSpeedMode: selectedSpeedMode,
        supportsSpeedMode: supportsSpeedMode,
        onEffortChange: onEffortChange,
        onSpeedChange: onSpeedChange,
        onModelChange: onModelChange
    )
}

@MainActor
func makeGroupedReasoningMenu(
    isModelsExpanded: Bool = true,
    onModelSelected: @escaping (ChatComposerActionRowView.ReasoningModelSelectionRequest) -> Void = { _ in },
    onRequestCloseMainMenu: @escaping () -> Void = {}
) -> ComposerReasoningMenuViewController {
    let controller = ComposerReasoningMenuViewController(
        configuration: makeGroupedReasoningConfiguration(onModelChange: { request in
            onModelSelected(request)
            let selection = makeGroupedReasoningConfiguration(
                selectedProviderID: request.providerID,
                selectedModelID: request.modelID
            ).selection
            return .applied(selection: selection)
        }),
        onRequestCloseMainMenu: onRequestCloseMainMenu
    )
    controller.setModelsExpanded(isModelsExpanded)
    return controller
}

extension NSView {
    func modelsDescendants<ViewType: NSView>(of type: ViewType.Type) -> [ViewType] {
        subviews.flatMap { child -> [ViewType] in
            var matches = child.modelsDescendants(of: type)
            if let typed = child as? ViewType {
                matches.insert(typed, at: 0)
            }
            return matches
        }
    }
}

@MainActor
func modelRowMouseEvent(
    type: NSEvent.EventType,
    in row: NSView,
    window: NSWindow
) -> NSEvent {
    let location = row.convert(NSPoint(x: row.bounds.midX, y: row.bounds.midY), to: nil)
    return NSEvent.mouseEvent(
        with: type,
        location: location,
        modifierFlags: [],
        timestamp: 0,
        windowNumber: window.windowNumber,
        context: nil,
        eventNumber: 0,
        clickCount: 1,
        pressure: 0
    ) ?? NSEvent()
}

@MainActor
func modelRowKeyEvent(keyCode: UInt16, window: NSWindow) -> NSEvent {
    let characters = keyCode == 49 ? " " : "\r"
    return NSEvent.keyEvent(
        with: .keyDown,
        location: .zero,
        modifierFlags: [],
        timestamp: 0,
        windowNumber: window.windowNumber,
        context: nil,
        characters: characters,
        charactersIgnoringModifiers: characters,
        isARepeat: false,
        keyCode: keyCode
    ) ?? NSEvent()
}
