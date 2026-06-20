import AppKit
import XCTest

@testable import Alveary

@MainActor
final class ChatComposerActionRowTests: XCTestCase {
    func testIdlePrimaryActionRoutesSubmitAndHonorsDisabledState() throws {
        let row = ChatComposerActionRowView()
        var submitCount = 0
        row.configure(
            makeConfiguration(
                mode: .idle,
                isPrimaryActionDisabled: false,
                onSubmit: { submitCount += 1 }
            )
        )

        let enabledButton = try XCTUnwrap(row.descendants(of: ComposerActionButton.self).first)
        XCTAssertEqual(enabledButton.accessibilityLabel(), "Send")
        XCTAssertTrue(enabledButton.accessibilityPerformPress())
        XCTAssertEqual(submitCount, 1)

        row.configure(
            makeConfiguration(
                mode: .idle,
                isPrimaryActionDisabled: true,
                onSubmit: { submitCount += 1 }
            )
        )

        let disabledButton = try XCTUnwrap(row.descendants(of: ComposerActionButton.self).first)
        XCTAssertFalse(disabledButton.accessibilityPerformPress())
        XCTAssertEqual(submitCount, 1)
    }

    func testStopActionRoutesStopAndUsesConfirmationAccessibilityCopy() throws {
        let row = ChatComposerActionRowView()
        var stopCount = 0
        row.configure(
            makeConfiguration(
                mode: .busy(canStop: true),
                isStopConfirmationArmed: true,
                onStop: { stopCount += 1 }
            )
        )

        let stopButton = try XCTUnwrap(row.descendants(of: ComposerActionButton.self).first)
        XCTAssertEqual(stopButton.accessibilityLabel(), "Confirm stop")
        XCTAssertTrue(stopButton.accessibilityPerformPress())
        XCTAssertEqual(stopCount, 1)
    }

    func testBusyWithoutStopKeepsAccessibleDisabledSendingFootprint() throws {
        let row = ChatComposerActionRowView()
        row.configure(makeConfiguration(mode: .busy(canStop: false)))

        let sendingSlot = try XCTUnwrap(
            row.descendants(of: NSView.self).first { $0.accessibilityLabel() == "Sending message" }
        )
        XCTAssertEqual(sendingSlot.accessibilityRole(), .group)
        let footprintButton = try XCTUnwrap(row.descendants(of: ComposerActionButton.self).first)
        XCTAssertFalse(footprintButton.accessibilityPerformPress())
    }

    func testProgressOnlyWithoutStopShowsProgressLabelAndDisabledActionButton() throws {
        let row = ChatComposerActionRowView()
        row.configure(makeConfiguration(mode: .progressOnly(.sessionHandoff)))

        XCTAssertNotNil(row.descendants(of: NSTextField.self).first { $0.stringValue == "Handing off session..." })
        let actionButton = try XCTUnwrap(row.descendants(of: ComposerActionButton.self).first)
        XCTAssertFalse(actionButton.accessibilityPerformPress())
    }

    func testReconfiguringSessionProgressIsIntegratedIntoReasoningButton() throws {
        let row = ChatComposerActionRowView()
        row.configure(makeConfiguration(mode: .progressOnly(.reconfiguringSession)))

        XCTAssertNil(row.descendants(of: NSTextField.self).first { $0.stringValue == "Applying session changes..." })
        let actionButton = try XCTUnwrap(row.descendants(of: ComposerActionButton.self).first)
        XCTAssertFalse(actionButton.accessibilityPerformPress())
        let reasoningButton = try XCTUnwrap(row.descendants(of: ComposerReasoningButton.self).first)
        #if DEBUG
        XCTAssertTrue(reasoningButton.debugShowsProgress)
        XCTAssertGreaterThan(reasoningButton.debugTextAlpha, 0.5)
        #endif
    }

    func testReasoningButtonReplacesProviderModelAndEffortMenus() {
        let row = ChatComposerActionRowView()
        row.configure(
            makeConfiguration(
                mode: .idle,
                providerOptions: [
                    .init(value: "claude", title: "Claude Code"),
                    .init(value: "codex", title: "Codex")
                ],
                modelOptions: [.init(value: "sonnet", title: "Sonnet")],
                effortOptions: [.init(value: "medium", title: "Medium")],
                supportedPermissionModes: [.init(value: "default", title: "Default")]
            )
        )

        XCTAssertEqual(row.descendants(of: ComposerPermissionButton.self).first?.accessibilityLabel(), "Permissions")
        XCTAssertEqual(row.descendants(of: ComposerReasoningButton.self).first?.accessibilityLabel(), "Reasoning")
        XCTAssertEqual(row.descendants(of: ComposerWorktreeLocationButton.self).first?.accessibilityLabel(), "Thread location")
    }

    func testActionButtonDoesNotFireWhenDisabledBeforeMouseUp() {
        let button = ComposerActionButton(style: .primary)
        button.frame = NSRect(x: 0, y: 0, width: 76, height: 30)
        var submitCount = 0
        button.actionHandler = { submitCount += 1 }
        button.configure(
            title: "Send",
            symbolName: "paperplane.fill",
            isEnabled: true,
            accessibilityLabel: "Send"
        )

        button.mouseDown(with: mouseEvent(at: NSPoint(x: 10, y: 10)))
        button.configure(
            title: "Send",
            symbolName: "paperplane.fill",
            isEnabled: false,
            accessibilityLabel: "Send"
        )
        button.mouseUp(with: mouseEvent(at: NSPoint(x: 10, y: 10)))

        XCTAssertEqual(submitCount, 0)
    }

    func testDestructiveActionButtonFiresOnMouseDownOnce() {
        let button = ComposerActionButton(style: .destructive)
        button.frame = NSRect(x: 0, y: 0, width: 76, height: 30)
        var stopCount = 0
        button.actionHandler = { stopCount += 1 }
        button.configure(
            title: "Stop",
            symbolName: "stop.fill",
            isEnabled: true,
            accessibilityLabel: "Stop"
        )

        button.mouseDown(with: mouseEvent(type: .leftMouseDown, at: NSPoint(x: 10, y: 10)))
        XCTAssertEqual(stopCount, 1)

        button.mouseUp(with: mouseEvent(type: .leftMouseUp, at: NSPoint(x: 10, y: 10)))
        XCTAssertEqual(stopCount, 1)
    }

    func testDestructiveActionButtonStillFiresIfDisabledBeforeMouseUp() {
        let button = ComposerActionButton(style: .destructive)
        button.frame = NSRect(x: 0, y: 0, width: 76, height: 30)
        var stopCount = 0
        button.actionHandler = { stopCount += 1 }
        button.configure(
            title: "Stop",
            symbolName: "stop.fill",
            isEnabled: true,
            accessibilityLabel: "Stop"
        )

        button.mouseDown(with: mouseEvent(type: .leftMouseDown, at: NSPoint(x: 10, y: 10)))
        button.configure(
            title: "Stop",
            symbolName: "stop.fill",
            isEnabled: false,
            accessibilityLabel: "Stop"
        )
        button.mouseUp(with: mouseEvent(type: .leftMouseUp, at: NSPoint(x: 10, y: 10)))

        XCTAssertEqual(stopCount, 1)
    }

    func testWorktreeLocationButtonUsesPermissionStylePresentationAndMetrics() {
        let row = ChatComposerActionRowView(frame: NSRect(x: 0, y: 0, width: 480, height: 30))
        row.configure(
            makeConfiguration(
                mode: .idle,
                selectedUseWorktree: true
            )
        )

        let button = row.worktreeButton
        XCTAssertEqual(button.accessibilityLabel(), "Thread location")
        XCTAssertEqual(button.accessibilityValue() as? String, "New worktree")
        XCTAssertEqual(button.intrinsicContentSize.height, 24)
        XCTAssertGreaterThan(button.intrinsicContentSize.width, 120)
        #if DEBUG
        XCTAssertEqual(button.debugTitle, "New worktree")
        XCTAssertTrue(["arrow.trianglehead.branch", "arrow.triangle.branch"].contains(button.debugSymbolName ?? ""))
        XCTAssertEqual(button.debugIconRotationRadians, CGFloat.pi / 2, accuracy: 0.0001)
        XCTAssertFalse(button.debugIsWarning)
        XCTAssertEqual(button.debugTextChevronSpacing, button.debugIconTextSpacing)
        #endif
    }

    func testNarrowRowKeepsSettingsControlsInsideLeadingEdgeAndActionsInsideTrailingEdge() throws {
        let row = ChatComposerActionRowView(frame: NSRect(x: 0, y: 0, width: 340, height: 30))
        row.configure(
            makeConfiguration(
                mode: .idle,
                modelOptions: [
                    .init(value: "sonnet", title: "Sonnet"),
                    .init(value: "opus", title: "Extremely Wide Model Name")
                ],
                effortOptions: [.init(value: "medium", title: "Medium")],
                supportedPermissionModes: [.init(value: "default", title: "Default")]
            )
        )

        row.layoutSubtreeIfNeeded()

        let settingFrames = row.descendants(of: ComposerCompactDropdownButton.self)
            .map { $0.convert($0.bounds, to: row) }
        XCTAssertFalse(settingFrames.isEmpty)
        XCTAssertTrue(settingFrames.allSatisfy { $0.minX >= 0 })

        let actionButton = try XCTUnwrap(row.descendants(of: ComposerActionButton.self).first)
        let actionFrame = actionButton.convert(actionButton.bounds, to: row)
        XCTAssertLessThanOrEqual(actionFrame.maxX, row.bounds.maxX)
    }

    func testWideRowPinsAccessoryAndActionControlsToTrailingEdge() throws {
        let row = ChatComposerActionRowView(frame: NSRect(x: 0, y: 0, width: 900, height: 30))
        row.configure(
            makeConfiguration(
                mode: .idle,
                usageSummary: ConversationUsageSummary(
                    contextUsedTokens: 10_000,
                    contextWindowSize: 100_000,
                    totalCostUsd: 0.12,
                    hasReportedCost: true,
                    hasReportedUsage: true,
                    isUsingCachedContextWindow: false
                )
            )
        )

        row.layoutSubtreeIfNeeded()

        let actionButton = try XCTUnwrap(row.descendants(of: ComposerActionButton.self).first)
        let actionFrame = actionButton.convert(actionButton.bounds, to: row)
        XCTAssertEqual(actionFrame.maxX, row.bounds.maxX, accuracy: 1)

        let contextIndicator = try XCTUnwrap(row.descendants(of: AppKitContextWindowIndicatorView.self).first)
        let contextFrame = contextIndicator.convert(contextIndicator.bounds, to: row)
        XCTAssertGreaterThan(contextFrame.minX, row.bounds.midX)

        let reasoningButton = try XCTUnwrap(row.descendants(of: ComposerReasoningButton.self).first)
        let reasoningFrame = reasoningButton.convert(reasoningButton.bounds, to: row)
        XCTAssertGreaterThanOrEqual(reasoningFrame.minX, contextFrame.maxX)
        XCTAssertLessThan(reasoningFrame.maxX, actionFrame.minX)
    }

}

func makeConfiguration(
    mode: ComposerMode,
    providerOptions: [ChatComposerActionRowView.MenuOption] = [.init(value: "claude", title: "Claude Code")],
    modelOptions: [ChatComposerActionRowView.MenuOption] = [.init(value: "sonnet", title: "Sonnet")],
    effortOptions: [ChatComposerActionRowView.MenuOption] = [.init(value: "medium", title: "Medium")],
    supportedPermissionModes: [ChatComposerActionRowView.PermissionOptionPresentation] = [.init(value: "default", title: "Default")],
    selectedPermissionMode: String = "default",
    showWorktreePicker: Bool = true,
    selectedUseWorktree: Bool = false,
    isPlanModeEnabled: Bool = false,
    selectedSpeedMode: AgentSpeedMode = .standard,
    supportsSpeedMode: Bool = false,
    usageSummary: ConversationUsageSummary? = nil,
    areControlsDisabled: Bool = false,
    isPrimaryActionDisabled: Bool = false,
    isStopConfirmationArmed: Bool = false,
    onPlanModeChange: @escaping (Bool) -> Void = { _ in },
    onEffortChange: @escaping (String) -> Bool = { _ in true },
    onSpeedChange: @escaping (AgentSpeedMode) -> Bool = { _ in true },
    onModelChange: @escaping (ChatComposerActionRowView.ReasoningModelSelectionRequest)
        -> ChatComposerActionRowView.ReasoningModelSelectionOutcome = { _ in .rejected },
    onSubmit: @escaping () -> Void = {},
    onStop: @escaping () -> Void = {},
    onAddPhotosAndFiles: @escaping () -> Void = {}
) -> ChatComposerActionRowView.Configuration {
    ChatComposerActionRowView.Configuration(
        reasoning: makeReasoningConfiguration(
            providerOptions: providerOptions,
            modelOptions: modelOptions,
            effortOptions: effortOptions,
            selectedSpeedMode: selectedSpeedMode,
            supportsSpeedMode: supportsSpeedMode,
            onEffortChange: onEffortChange,
            onSpeedChange: onSpeedChange,
            onModelChange: onModelChange
        ),
        supportedPermissionModes: supportedPermissionModes,
        selectedPermissionMode: selectedPermissionMode,
        showWorktreePicker: showWorktreePicker,
        selectedUseWorktree: selectedUseWorktree,
        isPlanModeEnabled: isPlanModeEnabled,
        usageSummary: usageSummary,
        areControlsDisabled: areControlsDisabled,
        mode: mode,
        primaryActionTitle: "Send",
        primaryActionSystemImage: "paperplane.fill",
        isPrimaryActionDisabled: isPrimaryActionDisabled,
        isStopConfirmationArmed: isStopConfirmationArmed,
        composerActionRowHeight: ChatComposerActionRowView.defaultHeight,
        onPermissionModeChange: { _ in },
        onUseWorktreeChange: { _ in },
        onPlanModeChange: onPlanModeChange,
        onSubmit: onSubmit,
        onStop: onStop,
        onAddPhotosAndFiles: onAddPhotosAndFiles
    )
}

func makeReasoningConfiguration(
    providerOptions: [ChatComposerActionRowView.MenuOption] = [.init(value: "claude", title: "Claude Code")],
    modelOptions: [ChatComposerActionRowView.MenuOption] = [.init(value: "sonnet", title: "Sonnet")],
    effortOptions: [ChatComposerActionRowView.MenuOption] = [.init(value: "medium", title: "Medium")],
    selectedProvider: String = "claude",
    selectedModel: String = "sonnet",
    selectedEffort: String = "medium",
    selectedSpeedMode: AgentSpeedMode = .standard,
    supportsSpeedMode: Bool = false,
    hasStartedThread: Bool = false,
    onEffortChange: @escaping (String) -> Bool = { _ in true },
    onSpeedChange: @escaping (AgentSpeedMode) -> Bool = { _ in true },
    onModelChange: @escaping (ChatComposerActionRowView.ReasoningModelSelectionRequest)
        -> ChatComposerActionRowView.ReasoningModelSelectionOutcome = { _ in .rejected }
) -> ChatComposerActionRowView.ReasoningConfiguration {
    let selectedProviderOption = providerOptions.first { $0.value == selectedProvider } ?? providerOptions.first
    let selectedModelOption = modelOptions.first { $0.value == selectedModel } ?? modelOptions.first
    let selectedEffortOption = effortOptions.first { $0.value == selectedEffort } ?? effortOptions.first
    return ChatComposerActionRowView.ReasoningConfiguration(
        selection: .init(
            providerID: selectedProviderOption?.value ?? selectedProvider,
            providerTitle: selectedProviderOption?.title ?? selectedProvider.capitalized,
            modelID: selectedModelOption?.value ?? selectedModel,
            modelTitle: selectedModelOption?.title ?? ChatComposerTextSupport.modelLabel(for: selectedModel),
            effortValue: selectedEffortOption?.value ?? selectedEffort,
            effortTitle: selectedEffortOption?.title ?? ChatComposerTextSupport.effortLabel(for: selectedEffort),
            effortOptions: effortOptions,
            speedMode: selectedSpeedMode,
            supportsSpeedMode: supportsSpeedMode
        ),
        modelGroups: providerOptions.map { provider in
            ChatComposerActionRowView.ReasoningModelGroup(
                providerID: provider.value,
                providerTitle: hasStartedThread ? nil : provider.title,
                options: modelOptions.map { model in
                    ChatComposerActionRowView.ReasoningModelOption(
                        providerID: provider.value,
                        value: model.value,
                        title: model.title
                    )
                }
            )
        },
        hasStartedThread: hasStartedThread,
        onEffortChange: onEffortChange,
        onSpeedChange: onSpeedChange,
        onModelChange: onModelChange
    )
}

private extension NSView {
    func descendants<ViewType: NSView>(of type: ViewType.Type) -> [ViewType] {
        subviews.flatMap { child -> [ViewType] in
            var matches = child.descendants(of: type)
            if let typed = child as? ViewType {
                matches.insert(typed, at: 0)
            }
            return matches
        }
    }
}

private func mouseEvent(type: NSEvent.EventType = .leftMouseUp, at point: NSPoint) -> NSEvent {
    NSEvent.mouseEvent(
        with: type,
        location: point,
        modifierFlags: [],
        timestamp: 0,
        windowNumber: 0,
        context: nil,
        eventNumber: 0,
        clickCount: 1,
        pressure: 0
    ) ?? NSEvent()
}
