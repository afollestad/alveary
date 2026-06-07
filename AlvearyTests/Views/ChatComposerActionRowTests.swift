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

    func testProgressOnlyWithoutStopShowsProgressLabelWithoutActionButtons() throws {
        let row = ChatComposerActionRowView()
        row.configure(makeConfiguration(mode: .progressOnly(.sessionHandoff)))

        XCTAssertNotNil(row.descendants(of: NSTextField.self).first { $0.stringValue == "Handing off session..." })
        XCTAssertTrue(row.descendants(of: ComposerActionButton.self).isEmpty)
    }

    func testProviderPickerCanBeHiddenWhileOtherSettingsRemainVisible() {
        let row = ChatComposerActionRowView()
        row.configure(
            makeConfiguration(
                mode: .idle,
                providerOptions: [
                    .init(value: "claude", title: "Claude Code"),
                    .init(value: "codex", title: "Codex")
                ],
                showsProviderPicker: false,
                modelOptions: [.init(value: "sonnet", title: "Sonnet")],
                effortOptions: [.init(value: "medium", title: "Medium")],
                supportedPermissionModes: [.init(value: "default", title: "Default")]
            )
        )

        let menus = row.descendants(of: ComposerMenuButton.self)
        XCTAssertFalse(menus.contains { $0.accessibilityLabel() == "Provider" })
        XCTAssertTrue(menus.contains { $0.accessibilityLabel() == "Model" })
        XCTAssertTrue(menus.contains { $0.accessibilityLabel() == "Effort" })
        XCTAssertTrue(menus.contains { $0.accessibilityLabel() == "Permissions" })
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

    func testMenuButtonUsesSwiftUIPickerHeightAndWidestOptionWidth() {
        let button = ComposerMenuButton()
        button.configure(
            title: "Default",
            options: [
                .init(value: "default", title: "Default"),
                .init(value: "acceptEdits", title: "Accept edits")
            ],
            selectedValue: "default",
            isEnabled: true,
            onSelect: { _ in }
        )

        let size = button.intrinsicContentSize
        XCTAssertEqual(size.height, 24)
        XCTAssertGreaterThan(size.width, 110)
    }

    func testComposerModelMenuUsesCodexProviderStatusLabelsAndEfforts() {
        let menuItems = AgentModelOptionSelection.menuItems(
            in: AgentModelOptionTestFixtures.codexModelOptions,
            selectedModel: "gpt-5.4-mini",
            fallbackTitle: ChatComposerTextSupport.modelLabel(for:)
        )
        let effortOptions = AgentModelOptionSelection.effortOptions(
            in: AgentModelOptionTestFixtures.codexModelOptions,
            selectedModel: "gpt-5.4-mini"
        )

        XCTAssertEqual(menuItems.map(\.value), ["gpt-5.5", "gpt-5.4-mini"])
        XCTAssertEqual(menuItems.map(\.title), ["GPT-5.5", "GPT-5.4-Mini"])
        XCTAssertEqual(effortOptions.map(\.value), ["low", "medium"])
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

        let menuFrames = row.descendants(of: ComposerMenuButton.self).map { $0.convert($0.bounds, to: row) }
        XCTAssertFalse(menuFrames.isEmpty)
        XCTAssertTrue(menuFrames.allSatisfy { $0.minX >= 0 })

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

        let keyboardButton = try XCTUnwrap(
            row.descendants(of: ComposerIconButton.self).first {
                $0.accessibilityLabel() == "Show chat keyboard shortcuts"
            }
        )
        let keyboardFrame = keyboardButton.convert(keyboardButton.bounds, to: row)
        XCTAssertGreaterThan(keyboardFrame.minX, row.bounds.midX)
        XCTAssertLessThan(keyboardFrame.maxX, actionFrame.minX)

        let contextIndicator = try XCTUnwrap(row.descendants(of: AppKitContextWindowIndicatorView.self).first)
        let contextFrame = contextIndicator.convert(contextIndicator.bounds, to: row)
        XCTAssertGreaterThan(contextFrame.minX, row.bounds.midX)
        XCTAssertLessThan(contextFrame.maxX, keyboardFrame.minX)
    }

    func testSessionLocationLabelKeepsIntrinsicWidthWhenDropdownsCompress() throws {
        let row = ChatComposerActionRowView(frame: NSRect(x: 0, y: 0, width: 930, height: 30))
        row.configure(
            makeConfiguration(
                mode: .idle,
                showWorktreePicker: false,
                sessionLocationLabel: "Local",
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

        let locationLabel = try XCTUnwrap(row.descendants(of: NSTextField.self).first { $0.stringValue == "Local" })
        let locationFrame = locationLabel.convert(locationLabel.bounds, to: row)
        XCTAssertGreaterThanOrEqual(locationFrame.width, measuredTextWidth(for: locationLabel))
    }

    func testSessionLocationLabelKeepsIntrinsicWidthWhenRowOverflowsMinimums() throws {
        let row = ChatComposerActionRowView(frame: NSRect(x: 0, y: 0, width: 300, height: 30))
        row.configure(
            makeConfiguration(
                mode: .idle,
                showWorktreePicker: false,
                sessionLocationLabel: "Local",
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

        let locationLabel = try XCTUnwrap(row.descendants(of: NSTextField.self).first { $0.stringValue == "Local" })
        let locationFrame = locationLabel.convert(locationLabel.bounds, to: row)
        XCTAssertGreaterThanOrEqual(locationFrame.width, measuredTextWidth(for: locationLabel))
    }

    func testSessionLocationWorktreeLabelKeepsNaturalWidthWhenDropdownsCompress() throws {
        let row = ChatComposerActionRowView(frame: NSRect(x: 0, y: 0, width: 930, height: 30))
        row.configure(
            makeConfiguration(
                mode: .idle,
                showWorktreePicker: false,
                sessionLocationLabel: "Worktree",
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

        let locationLabel = try XCTUnwrap(row.descendants(of: NSTextField.self).first { $0.stringValue == "Worktree" })
        let locationFrame = locationLabel.convert(locationLabel.bounds, to: row)
        XCTAssertGreaterThanOrEqual(locationFrame.width, measuredTextWidth(for: locationLabel))
    }

    func testKeyboardButtonRoutesKeymapAction() throws {
        let row = ChatComposerActionRowView()
        var showKeymapCount = 0
        row.configure(makeConfiguration(mode: .idle, onShowKeymap: { showKeymapCount += 1 }))

        let keyboardButton = try XCTUnwrap(
            row.descendants(of: ComposerIconButton.self).first {
                $0.accessibilityLabel() == "Show chat keyboard shortcuts"
            }
        )
        XCTAssertTrue(keyboardButton.accessibilityPerformPress())
        XCTAssertEqual(showKeymapCount, 1)
    }

}

func makeConfiguration(
    mode: ComposerMode,
    providerOptions: [ChatComposerActionRowView.MenuOption] = [.init(value: "claude", title: "Claude Code")],
    showsProviderPicker: Bool = true,
    modelOptions: [ChatComposerActionRowView.MenuOption] = [.init(value: "sonnet", title: "Sonnet")],
    effortOptions: [ChatComposerActionRowView.MenuOption] = [.init(value: "medium", title: "Medium")],
    supportedPermissionModes: [ChatComposerActionRowView.MenuOption] = [.init(value: "default", title: "Default")],
    showWorktreePicker: Bool = true,
    sessionLocationLabel: String? = nil,
    usageSummary: ConversationUsageSummary? = nil,
    areControlsDisabled: Bool = false,
    isPrimaryActionDisabled: Bool = false,
    isStopConfirmationArmed: Bool = false,
    onSubmit: @escaping () -> Void = {},
    onStop: @escaping () -> Void = {},
    onShowKeymap: @escaping () -> Void = {},
    onAddPhotosAndFiles: @escaping () -> Void = {}
) -> ChatComposerActionRowView.Configuration {
    ChatComposerActionRowView.Configuration(
        providerOptions: providerOptions,
        showsProviderPicker: showsProviderPicker,
        selectedProvider: "claude",
        modelOptions: modelOptions,
        selectedModel: "sonnet",
        effortOptions: effortOptions,
        selectedEffort: "medium",
        supportedPermissionModes: supportedPermissionModes,
        selectedPermissionMode: "default",
        showWorktreePicker: showWorktreePicker,
        selectedUseWorktree: false,
        sessionLocationLabel: sessionLocationLabel,
        usageSummary: usageSummary,
        isTextEditorDisabled: false,
        areControlsDisabled: areControlsDisabled,
        mode: mode,
        primaryActionTitle: "Send",
        primaryActionSystemImage: "paperplane.fill",
        isPrimaryActionDisabled: isPrimaryActionDisabled,
        isStopConfirmationArmed: isStopConfirmationArmed,
        composerActionRowHeight: ChatComposerActionRowView.defaultHeight,
        contextIndicatorKeyboardSpacing: ChatComposerActionRowView.defaultContextIndicatorKeyboardSpacing,
        onProviderChange: { _ in },
        onModelChange: { _ in },
        onEffortChange: { _ in },
        onPermissionModeChange: { _ in },
        onUseWorktreeChange: { _ in },
        onSubmit: onSubmit,
        onStop: onStop,
        onShowKeymap: onShowKeymap,
        onAddPhotosAndFiles: onAddPhotosAndFiles
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

@MainActor
private func measuredTextWidth(for field: NSTextField) -> CGFloat {
    let font = field.font ?? .preferredFont(forTextStyle: .callout)
    let textWidth = (field.stringValue as NSString).size(withAttributes: [.font: font]).width
    let cellWidth = field.cell?.cellSize.width ?? 0
    let intrinsicWidth = field.intrinsicContentSize.width
    return ceil(max(textWidth, cellWidth, intrinsicWidth)) + 4
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
