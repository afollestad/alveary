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
        let controller = ComposerPlusMenuViewController(configuration: .init(
            isPlanModeEnabled: false,
            isPlanModeToggleEnabled: true,
            planModeDisabledTooltip: nil,
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
        let controller = ComposerPlusMenuViewController(configuration: .init(
            isPlanModeEnabled: false,
            isPlanModeToggleEnabled: false,
            planModeDisabledTooltip: "Unsupported",
            onAddPhotosAndFiles: {},
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
        let controller = ComposerPlusMenuViewController(configuration: .init(
            isPlanModeEnabled: false,
            isPlanModeToggleEnabled: true,
            planModeDisabledTooltip: nil,
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
        let controller = ComposerPlusMenuViewController(configuration: .init(
            isPlanModeEnabled: false,
            isPlanModeToggleEnabled: true,
            planModeDisabledTooltip: nil,
            onAddPhotosAndFiles: {},
            onPlanModeChange: { _ in }
        ))
        controller.loadViewIfNeeded()

        XCTAssertTrue(controller.view is AppKitComposerPopoverSurfaceView)
        XCTAssertFalse(controller.view is NSVisualEffectView)
        XCTAssertNil(controller.view.layer?.backgroundColor)
    }

    func testPlusMenuUsesSharedComposerPopoverDivider() throws {
        let controller = ComposerPlusMenuViewController(configuration: .init(
            isPlanModeEnabled: false,
            isPlanModeToggleEnabled: true,
            planModeDisabledTooltip: nil,
            onAddPhotosAndFiles: {},
            onPlanModeChange: { _ in }
        ))
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

    func testReasoningMenuEffortRowRoutesSelectionAndRequestsClose() throws {
        var selectedEffort: String?
        var closeCount = 0
        let controller = ComposerReasoningMenuViewController(
            configuration: makeReasoningConfiguration(
                effortOptions: [
                    .init(value: "low", title: "Low"),
                    .init(value: "medium", title: "Medium"),
                    .init(value: "high", title: "High")
                ],
                onEffortChange: {
                    selectedEffort = $0
                    return true
                }
            ),
            onRequestCloseMainMenu: { closeCount += 1 }
        )
        controller.loadViewIfNeeded()

        let highRow = try XCTUnwrap(
            controller.view.descendants(of: ComposerReasoningMenuRowView.self).first {
                $0.accessibilityLabel() == "High"
            }
        )
        XCTAssertTrue(highRow.accessibilityPerformPress())

        XCTAssertEqual(selectedEffort, "high")
        XCTAssertEqual(closeCount, 1)
    }

    func testReasoningMenuUpdatePreselectsNewDefaultEffort() throws {
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

        let mediumRow = try XCTUnwrap(
            controller.view.descendants(of: ComposerReasoningMenuRowView.self).first {
                $0.accessibilityLabel() == "Medium"
            }
        )
        let lowRow = try XCTUnwrap(
            controller.view.descendants(of: ComposerReasoningMenuRowView.self).first {
                $0.accessibilityLabel() == "Low"
            }
        )
        XCTAssertEqual(mediumRow.accessibilityValue() as? String, "Selected")
        XCTAssertNil(lowRow.accessibilityValue())
        #if DEBUG
        XCTAssertNil(mediumRow.debugIconName)
        XCTAssertEqual(mediumRow.debugTrailingIconName, "checkmark")
        #endif
    }

    func testReasoningMenuKeepsHeaderWhenModelHasNoEffortOptions() throws {
        let controller = ComposerReasoningMenuViewController(
            configuration: makeReasoningConfiguration(effortOptions: []),
            onRequestCloseMainMenu: {}
        )
        controller.loadViewIfNeeded()
        controller.view.layoutSubtreeIfNeeded()

        let header = try XCTUnwrap(
            controller.view.descendants(of: NSTextField.self).first {
                $0.stringValue == "Reasoning"
            }
        )
        XCTAssertFalse(header.isHidden)
        XCTAssertGreaterThan(header.frame.height, 0)
    }

    func testReasoningMenuRowsAlignTextWithHeaderInsets() {
        XCTAssertEqual(
            ComposerReasoningMenuMetrics.horizontalInset + ComposerReasoningMenuMetrics.titleLeading,
            ComposerReasoningMenuMetrics.headerInset
        )
        XCTAssertEqual(
            ComposerReasoningMenuMetrics.horizontalInset + ComposerReasoningMenuMetrics.titleTrailing,
            ComposerReasoningMenuMetrics.headerInset
        )
    }

    func testReasoningModelSubmenuGroupsProvidersAndRoutesSelection() throws {
        var selectedRequest: ChatComposerActionRowView.ReasoningModelSelectionRequest?
        let controller = makeGroupedReasoningModelMenu { selectedRequest = $0 }
        controller.loadViewIfNeeded()

        let headers = controller.view.descendants(of: ComposerReasoningHeaderView.self).map(\.stringValue)
        XCTAssertEqual(headers, ["Claude Code", "Codex"])

        let selectedRow = try XCTUnwrap(
            controller.view.descendants(of: ComposerReasoningMenuRowView.self).first {
                $0.accessibilityLabel() == "Provider default"
            }
        )
        XCTAssertEqual(selectedRow.accessibilityValue() as? String, "Selected")
        #if DEBUG
        XCTAssertNil(selectedRow.debugIconName)
        XCTAssertEqual(selectedRow.debugTrailingIconName, "checkmark")
        #endif

        let codexRow = try XCTUnwrap(
            controller.view.descendants(of: ComposerReasoningMenuRowView.self).first {
                $0.accessibilityLabel() == "GPT-5.5"
            }
        )
        XCTAssertTrue(codexRow.accessibilityPerformPress())
        XCTAssertEqual(selectedRequest, .init(providerID: "codex", modelID: "gpt-5.5"))
    }

    func testReasoningModelSubmenuPlacesHeadersAboveRowsAndDividersBetweenGroups() throws {
        let controller = makeGroupedReasoningModelMenu()
        controller.loadViewIfNeeded()
        controller.view.layoutSubtreeIfNeeded()

        let headerViews = controller.view.descendants(of: ComposerReasoningHeaderView.self)
        let claudeHeader = try XCTUnwrap(headerViews.first { $0.stringValue == "Claude Code" })
        let codexHeader = try XCTUnwrap(headerViews.first { $0.stringValue == "Codex" })
        let selectedRow = try XCTUnwrap(
            controller.view.descendants(of: ComposerReasoningMenuRowView.self).first {
                $0.accessibilityLabel() == "Provider default"
            }
        )
        let codexRow = try XCTUnwrap(
            controller.view.descendants(of: ComposerReasoningMenuRowView.self).first {
                $0.accessibilityLabel() == "GPT-5.5"
            }
        )
        let divider = try XCTUnwrap(controller.view.descendants(of: AppKitComposerPopoverDividerView.self).first)
        XCTAssertEqual(claudeHeader.superview?.isFlipped, true)
        XCTAssertLessThan(claudeHeader.frame.minY, selectedRow.frame.minY)
        XCTAssertLessThan(selectedRow.frame.minY, divider.frame.minY)
        XCTAssertLessThan(divider.frame.minY, codexHeader.frame.minY)
        XCTAssertLessThan(codexHeader.frame.minY, codexRow.frame.minY)
    }

    func testReasoningModelSubmenuHidesProviderHeadersAfterThreadStart() {
        let controller = ComposerReasoningModelMenuViewController(
            groups: [
                .init(
                    providerID: "claude",
                    providerTitle: nil,
                    options: [.init(providerID: "claude", value: "sonnet", title: "Sonnet")]
                )
            ],
            selectedProviderID: "claude",
            selectedModelID: "sonnet",
            showsProviderHeaders: false,
            onModelSelected: { _ in },
            onHoverChanged: { _ in },
            onCancel: {}
        )
        controller.loadViewIfNeeded()

        XCTAssertTrue(controller.view.descendants(of: ComposerReasoningHeaderView.self).isEmpty)
    }

    func testReasoningModelSubmenuShowsDisabledEmptyRow() throws {
        let controller = ComposerReasoningModelMenuViewController(
            groups: [],
            selectedProviderID: "claude",
            selectedModelID: AppSettings.defaultModelValue,
            showsProviderHeaders: true,
            onModelSelected: { _ in XCTFail("Empty row should not select a model") },
            onHoverChanged: { _ in },
            onCancel: {}
        )
        controller.loadViewIfNeeded()

        let row = try XCTUnwrap(
            controller.view.descendants(of: ComposerReasoningMenuRowView.self).first {
                $0.accessibilityLabel() == "No models available"
            }
        )
        XCTAssertFalse(row.accessibilityPerformPress())
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
