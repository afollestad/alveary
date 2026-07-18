import AppKit
import XCTest

@testable import Alveary

@MainActor
final class ChatComposerPlusMenuTests: XCTestCase {
    func testPlusButtonMatchesMenuHeightAndPinsToLeadingEdge() throws {
        let row = ChatComposerActionRowView(frame: NSRect(x: 0, y: 0, width: 480, height: 30))
        row.configure(makeConfiguration(mode: .idle))

        row.layoutSubtreeIfNeeded()

        let plusButton = try XCTUnwrap(row.descendants(of: ComposerPlusButton.self).first)
        XCTAssertEqual(plusButton.accessibilityLabel(), "Open composer actions")
        XCTAssertEqual(plusButton.intrinsicContentSize.width, 24)
        XCTAssertEqual(plusButton.intrinsicContentSize.height, 24)

        let plusFrame = plusButton.convert(plusButton.bounds, to: row)
        XCTAssertEqual(plusFrame.minX, 0, accuracy: 1)
        XCTAssertEqual(plusFrame.height, 24, accuracy: 1)
        XCTAssertEqual(plusFrame.midY, row.bounds.midY, accuracy: 1)
    }

    func testPlusMenuRowsRouteActionsAndPlanRowToggles() throws {
        var addFilesCount = 0
        var planModeChanges: [Bool] = []
        let controller = ComposerPlusMenuViewController(configuration: makePlusMenuConfiguration(
            onAddPhotosAndFiles: { addFilesCount += 1 },
            onPlanModeChange: { planModeChanges.append($0) }
        ))
        controller.loadViewIfNeeded()

        let addFilesRow = try XCTUnwrap(
            controller.view.descendants(of: NSView.self).first { $0.accessibilityLabel() == "Add photos and files" }
        )
        XCTAssertTrue(addFilesRow.accessibilityPerformPress())
        XCTAssertEqual(addFilesCount, 1)

        let planRow = try XCTUnwrap(
            controller.view.descendants(of: NSView.self).first { $0.accessibilityLabel() == "Toggle plan mode" }
        )
        XCTAssertTrue(planRow.accessibilityPerformPress())
        XCTAssertTrue(planRow.accessibilityPerformPress())
        XCTAssertEqual(planModeChanges, [true, false])
    }

    func testPlusMenuPlanRowIgnoresPressesWhenDisabled() throws {
        var planModeChanges: [Bool] = []
        let controller = ComposerPlusMenuViewController(configuration: makePlusMenuConfiguration(
            isPlanModeToggleEnabled: false,
            planModeDisabledTooltip: "Unsupported",
            onPlanModeChange: { planModeChanges.append($0) }
        ))
        controller.loadViewIfNeeded()

        let planRow = try XCTUnwrap(
            controller.view.descendants(of: NSView.self).first { $0.accessibilityLabel() == "Toggle plan mode" }
        )
        XCTAssertFalse(planRow.accessibilityPerformPress())
        XCTAssertTrue(planModeChanges.isEmpty)
    }

    func testPlusMenuRowsActivateFromKeyboard() throws {
        var addFilesCount = 0
        var planModeChanges: [Bool] = []
        let controller = ComposerPlusMenuViewController(configuration: makePlusMenuConfiguration(
            onAddPhotosAndFiles: { addFilesCount += 1 },
            onPlanModeChange: { planModeChanges.append($0) }
        ))
        controller.loadViewIfNeeded()

        let addFilesRow = try XCTUnwrap(
            controller.view.descendants(of: ComposerPlusMenuRowView.self).first {
                $0.accessibilityLabel() == "Add photos and files"
            }
        )
        let planRow = try XCTUnwrap(
            controller.view.descendants(of: ComposerPlusMenuRowView.self).first {
                $0.accessibilityLabel() == "Toggle plan mode"
            }
        )

        addFilesRow.keyDown(with: keyEvent(keyCode: 36))
        planRow.keyDown(with: keyEvent(keyCode: 49))

        XCTAssertEqual(addFilesCount, 1)
        XCTAssertEqual(planModeChanges, [true])
    }

    func testPlusMenuUsesSharedComposerPopoverSurface() {
        let controller = ComposerPlusMenuViewController(configuration: makePlusMenuConfiguration())
        controller.loadViewIfNeeded()

        XCTAssertTrue(controller.view is AppKitComposerPopoverSurfaceView)
        XCTAssertFalse(controller.view is NSVisualEffectView)
        XCTAssertNil(controller.view.layer?.backgroundColor)
    }

    func testPlusMenuUsesSharedComposerPopoverDivider() throws {
        let controller = ComposerPlusMenuViewController(configuration: makePlusMenuConfiguration())
        controller.loadViewIfNeeded()
        controller.view.layoutSubtreeIfNeeded()

        let divider = try XCTUnwrap(controller.view.descendants(of: AppKitComposerPopoverDividerView.self).first)
        XCTAssertEqual(divider.frame.minX, AppKitComposerPopoverDividerView.horizontalInset, accuracy: 1)
        XCTAssertEqual(divider.frame.height, AppKitComposerPopoverDividerView.height, accuracy: 1)
    }

    func testPopoverDidCloseReleasesPlusButtonFocus() throws {
        let fixture = makeWindowBackedActionRow()
        let row = fixture.row
        let plusButton = try XCTUnwrap(row.descendants(of: ComposerPlusButton.self).first)
        let window = fixture.window
        XCTAssertTrue(window.makeFirstResponder(plusButton))

        let popover = NSPopover()
        row.plusPopover = popover

        row.popoverDidClose(Notification(name: NSPopover.didCloseNotification, object: popover))

        XCTAssertFalse(window.firstResponder === plusButton)
        XCTAssertNil(row.plusPopover)
    }

    func testPopoverDidCloseLeavesUnrelatedFirstResponderIntact() throws {
        let fixture = makeWindowBackedActionRow()
        let row = fixture.row
        let focusTarget = FocusTargetView(frame: NSRect(x: 0, y: 0, width: 10, height: 10))
        row.addSubview(focusTarget)
        let window = fixture.window
        XCTAssertTrue(window.makeFirstResponder(focusTarget))

        let popover = NSPopover()
        row.plusPopover = popover

        row.popoverDidClose(Notification(name: NSPopover.didCloseNotification, object: popover))

        XCTAssertTrue(window.firstResponder === focusTarget)
        XCTAssertNil(row.plusPopover)
    }

    func testStalePopoverDidCloseDoesNotClearCurrentPopover() throws {
        let fixture = makeWindowBackedActionRow()
        let row = fixture.row
        let plusButton = try XCTUnwrap(row.descendants(of: ComposerPlusButton.self).first)
        let window = fixture.window
        XCTAssertTrue(window.makeFirstResponder(plusButton))

        let currentPopover = NSPopover()
        row.plusPopover = currentPopover

        row.popoverDidClose(Notification(name: NSPopover.didCloseNotification, object: NSPopover()))

        XCTAssertTrue(row.plusPopover === currentPopover)
        XCTAssertTrue(window.firstResponder === plusButton)
    }

    func testDisablingControlsReleasesPlusButtonFocusWithoutPopover() throws {
        let fixture = makeWindowBackedActionRow()
        let row = fixture.row
        let plusButton = try XCTUnwrap(row.descendants(of: ComposerPlusButton.self).first)
        let window = fixture.window
        XCTAssertNil(row.plusPopover)
        XCTAssertTrue(window.makeFirstResponder(plusButton))

        row.configure(makeConfiguration(mode: .idle, areControlsDisabled: true))

        XCTAssertFalse(window.firstResponder === plusButton)
        XCTAssertNil(row.plusPopover)
    }

    func testReasoningButtonUsesCompactTextDropdownMetrics() throws {
        let row = ChatComposerActionRowView(frame: NSRect(x: 0, y: 0, width: 480, height: 30))
        row.configure(makeConfiguration(mode: .idle))

        let reasoningButton = try XCTUnwrap(row.descendants(of: ComposerReasoningButton.self).first)
        XCTAssertEqual(reasoningButton.accessibilityLabel(), "Reasoning")
        XCTAssertEqual(reasoningButton.accessibilityValue() as? String, "Sonnet, Medium")
        XCTAssertEqual(reasoningButton.intrinsicContentSize.height, 24)
        XCTAssertGreaterThanOrEqual(reasoningButton.intrinsicContentSize.width, ComposerReasoningButton.minWidth)
        XCTAssertLessThanOrEqual(reasoningButton.intrinsicContentSize.width, ComposerReasoningButton.maxWidth)
    }

    func testReasoningSliderPreviewsThenCommitsOnceAndKeepsMenuOpen() throws {
        var selectedEffort: String?
        var closeCount = 0
        var displayedEfforts: [String] = []
        let controller = ComposerReasoningMenuViewController(
            configuration: makeReasoningConfiguration(
                effortOptions: [
                    .init(value: "low", title: "Low"),
                    .init(value: "medium", title: "Medium"),
                    .init(value: "high", title: "High")
                ],
                selectedEffort: "ultra",
                defaultEffort: "medium",
                onEffortChange: {
                    selectedEffort = $0
                    return true
                }
            ),
            onRequestCloseMainMenu: { closeCount += 1 },
            onDisplaySelectionChanged: { selection in
                if let effort = selection?.effortValue {
                    displayedEfforts.append(effort)
                }
            }
        )
        controller.loadViewIfNeeded()

        let slider = try XCTUnwrap(controller.debugEffortSlider)
        slider.beginTrackingInteraction()
        slider.updateTrackingInteraction(to: 1)
        XCTAssertTrue(slider.endTrackingInteraction(commit: true))

        XCTAssertEqual(selectedEffort, "medium")
        XCTAssertEqual(displayedEfforts, ["medium", "medium"])
        XCTAssertEqual(closeCount, 0)
    }

    func testRejectedReasoningSliderCommitRollsBackAndCloses() throws {
        var closeCount = 0
        let controller = ComposerReasoningMenuViewController(
            configuration: makeReasoningConfiguration(
                effortOptions: [
                    .init(value: "low", title: "Low"),
                    .init(value: "medium", title: "Medium")
                ],
                selectedEffort: "ultra",
                defaultEffort: "medium",
                onEffortChange: { _ in false }
            ),
            onRequestCloseMainMenu: { closeCount += 1 }
        )
        controller.loadViewIfNeeded()
        let slider = try XCTUnwrap(controller.debugEffortSlider)

        slider.beginTrackingInteraction()
        slider.updateTrackingInteraction(to: 1)
        XCTAssertTrue(slider.endTrackingInteraction(commit: true))

        XCTAssertEqual(closeCount, 1)
        XCTAssertEqual(slider.displayedIndex, 1)
        XCTAssertEqual(slider.accessibilityValueDescription(), "Medium")
        XCTAssertFalse(slider.debugCanonicalValueIsRepresented)
    }

    func testReasoningMenuUpdateSelectsAuthoritativeSliderEffort() throws {
        let controller = ComposerReasoningMenuViewController(
            configuration: makeReasoningConfiguration(
                effortOptions: [
                    .init(value: "low", title: "Low"),
                    .init(value: "medium", title: "Medium")
                ],
                selectedEffort: "low"
            ),
            onRequestCloseMainMenu: {}
        )
        controller.loadViewIfNeeded()

        controller.update(configuration: makeReasoningConfiguration(
            effortOptions: [
                .init(value: "low", title: "Low"),
                .init(value: "medium", title: "Medium")
            ],
            selectedEffort: "medium"
        ))

        let slider = try XCTUnwrap(controller.debugEffortSlider)
        XCTAssertEqual(slider.displayedIndex, 1)
        XCTAssertEqual(slider.accessibilityValueDescription(), "Medium")
    }

    func testReasoningMenuWithNoEffortOptionsHasNoReasoningHeaderOrSlider() throws {
        let controller = ComposerReasoningMenuViewController(
            configuration: makeReasoningConfiguration(effortOptions: []),
            onRequestCloseMainMenu: {}
        )
        controller.loadViewIfNeeded()
        controller.view.layoutSubtreeIfNeeded()

        XCTAssertTrue(try XCTUnwrap(controller.debugEffortSlider).isHidden)
        XCTAssertTrue(controller.view.descendants(of: ComposerReasoningHeaderView.self).isEmpty)
    }

    func testFastToggleAcceptedChangeUpdatesPresentationAndKeepsMenuOpen() throws {
        var selectedSpeed: AgentSpeedMode?
        var closeCount = 0
        let controller = ComposerReasoningMenuViewController(
            configuration: makeReasoningConfiguration(
                supportsSpeedMode: true,
                onSpeedChange: {
                    selectedSpeed = $0
                    return true
                }
            ),
            onRequestCloseMainMenu: { closeCount += 1 }
        )
        controller.loadViewIfNeeded()
        let fast = try XCTUnwrap(controller.debugFastToggle)

        fast.performActivationForTesting()

        XCTAssertEqual(selectedSpeed, .fast)
        XCTAssertEqual(closeCount, 0)
        XCTAssertEqual(fast.debugSymbolName, "bolt.fill")
        XCTAssertEqual(fast.toolTip, "Disable fast mode")
        XCTAssertEqual(fast.accessibilityValue() as? String, "On")
    }

    func testFastToggleRejectedChangeRollsBackAndCloses() throws {
        var closeCount = 0
        let controller = ComposerReasoningMenuViewController(
            configuration: makeReasoningConfiguration(
                supportsSpeedMode: true,
                onSpeedChange: { _ in false }
            ),
            onRequestCloseMainMenu: { closeCount += 1 }
        )
        controller.loadViewIfNeeded()
        let fast = try XCTUnwrap(controller.debugFastToggle)

        fast.performActivationForTesting()

        XCTAssertEqual(closeCount, 1)
        XCTAssertEqual(fast.debugSymbolName, "bolt")
        XCTAssertEqual(fast.toolTip, "Enable fast mode")
        XCTAssertEqual(fast.accessibilityValue() as? String, "Off")
    }

    func testFastToggleOffUsesNormalLabelTint() throws {
        let fast = ComposerReasoningFastToggleControl(frame: NSRect(x: 0, y: 0, width: 30, height: 30))
        fast.configure(isOn: false, isEnabled: true, onToggle: { _ in })
        let tint = try XCTUnwrap(fast.debugSymbolTintColor.usingColorSpace(.deviceRGB))
        let label = try XCTUnwrap(
            NSColor.labelColor
                .resolved(for: fast.appKitRenderingAppearance)
                .usingColorSpace(.deviceRGB)
        )

        XCTAssertEqual(tint.redComponent, label.redComponent, accuracy: 0.001)
        XCTAssertEqual(tint.greenComponent, label.greenComponent, accuracy: 0.001)
        XCTAssertEqual(tint.blueComponent, label.blueComponent, accuracy: 0.001)
        XCTAssertEqual(tint.alphaComponent, 0.80, accuracy: 0.001)
    }

    func testRejectedModelSelectionRestoresCanonicalMenuAndCloses() throws {
        var closeCount = 0
        var displayedModels: [String?] = []
        let controller = ComposerReasoningMenuViewController(
            configuration: makeGroupedReasoningConfiguration(
                selectedSpeedMode: .fast,
                supportsSpeedMode: true,
                onModelChange: { _ in .rejected }
            ),
            onRequestCloseMainMenu: { closeCount += 1 },
            onDisplaySelectionChanged: { displayedModels.append($0?.modelID) }
        )
        controller.loadViewIfNeeded()
        controller.setModelsExpanded(true)
        let list = try XCTUnwrap(controller.debugModelList)
        let selectedIndex = try XCTUnwrap(list.debugModelRowIdentities.firstIndex(of: "claude:sonnet"))
        let rejectedIndex = try XCTUnwrap(list.debugModelRowIdentities.firstIndex(of: "codex:gpt-5.5"))

        XCTAssertTrue(list.focusableRows[rejectedIndex].accessibilityPerformPress())

        XCTAssertEqual(closeCount, 1)
        XCTAssertEqual(displayedModels, [nil])
        XCTAssertEqual(list.focusableRows[selectedIndex].debugTrailingIconName, "checkmark")
        XCTAssertNil(list.focusableRows[rejectedIndex].debugTrailingIconName)
        XCTAssertEqual(try XCTUnwrap(controller.debugEffortSlider).accessibilityValueDescription(), "Medium")
        XCTAssertEqual(try XCTUnwrap(controller.debugFastToggle).debugSymbolName, "bolt.fill")
    }

    func testReasoningPopoverDidCloseReleasesReasoningButtonFocus() throws {
        let fixture = makeWindowBackedActionRow()
        let row = fixture.row
        let reasoningButton = try XCTUnwrap(row.descendants(of: ComposerReasoningButton.self).first)
        let window = fixture.window
        XCTAssertTrue(window.makeFirstResponder(reasoningButton))

        let popover = NSPopover()
        row.reasoningPopover = popover

        row.popoverDidClose(Notification(name: NSPopover.didCloseNotification, object: popover))

        XCTAssertFalse(window.firstResponder === reasoningButton)
        XCTAssertNil(row.reasoningPopover)
        XCTAssertNil(row.reasoningMenuController)
    }

    func testDisablingControlsReleasesReasoningButtonFocusWithoutPopover() throws {
        let fixture = makeWindowBackedActionRow()
        let row = fixture.row
        let reasoningButton = try XCTUnwrap(row.descendants(of: ComposerReasoningButton.self).first)
        let window = fixture.window
        XCTAssertNil(row.reasoningPopover)
        XCTAssertTrue(window.makeFirstResponder(reasoningButton))

        row.configure(makeConfiguration(mode: .idle, areControlsDisabled: true))

        XCTAssertFalse(window.firstResponder === reasoningButton)
        XCTAssertNil(row.reasoningPopover)
    }

    func testReasoningModelOptionIdentityIncludesProviderToAvoidDefaultCollisions() {
        let claudeDefault = ChatComposerActionRowView.ReasoningModelOption(
            providerID: "claude",
            value: AppSettings.defaultModelValue,
            title: "Provider default"
        )
        let codexDefault = ChatComposerActionRowView.ReasoningModelOption(
            providerID: "codex",
            value: AppSettings.defaultModelValue,
            title: "Provider default"
        )

        XCTAssertNotEqual(claudeDefault.identity, codexDefault.identity)
        XCTAssertEqual(claudeDefault.identity, "claude:default")
        XCTAssertEqual(codexDefault.identity, "codex:default")
    }
}

private final class FocusTargetView: NSView {
    override var acceptsFirstResponder: Bool { true }
}

private struct WindowBackedActionRow {
    let row: ChatComposerActionRowView
    let window: NSWindow
}

private func makePlusMenuConfiguration(
    isGoalModeArmed: Bool = false,
    isGoalModeToggleEnabled: Bool = true,
    goalModeDisabledTooltip: String? = nil,
    isPlanModeEnabled: Bool = false,
    isPlanModeToggleEnabled: Bool = true,
    planModeDisabledTooltip: String? = nil,
    onAddPhotosAndFiles: @escaping () -> Void = {},
    onGoalModeChange: @escaping (Bool) -> Void = { _ in },
    onPlanModeChange: @escaping (Bool) -> Void = { _ in }
) -> ComposerPlusMenuViewController.Configuration {
    .init(
        isGoalModeArmed: isGoalModeArmed,
        isGoalModeToggleEnabled: isGoalModeToggleEnabled,
        goalModeDisabledTooltip: goalModeDisabledTooltip,
        isPlanModeEnabled: isPlanModeEnabled,
        isPlanModeToggleEnabled: isPlanModeToggleEnabled,
        planModeDisabledTooltip: planModeDisabledTooltip,
        onAddPhotosAndFiles: onAddPhotosAndFiles,
        onPlanModeChange: onPlanModeChange,
        onGoalModeChange: onGoalModeChange
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
private func makeWindowBackedActionRow() -> WindowBackedActionRow {
    let row = ChatComposerActionRowView(frame: NSRect(x: 0, y: 0, width: 480, height: 30))
    row.configure(makeConfiguration(mode: .idle))
    let window = NSWindow(contentRect: row.frame, styleMask: .borderless, backing: .buffered, defer: false)
    window.contentView = row
    row.layoutSubtreeIfNeeded()
    return WindowBackedActionRow(row: row, window: window)
}

private func keyEvent(keyCode: UInt16) -> NSEvent {
    NSEvent.keyEvent(
        with: .keyDown,
        location: .zero,
        modifierFlags: [],
        timestamp: 0,
        windowNumber: 0,
        context: nil,
        characters: keyCode == 49 ? " " : "\r",
        charactersIgnoringModifiers: keyCode == 49 ? " " : "\r",
        isARepeat: false,
        keyCode: keyCode
    ) ?? NSEvent()
}
