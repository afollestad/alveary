import AppKit
import XCTest

@testable import Alveary

@MainActor
extension ChatComposerActionRowTests {
    func testPermissionButtonUsesMetadataPresentationAndCompactDropdownMetrics() throws {
        let row = ChatComposerActionRowView(frame: NSRect(x: 0, y: 0, width: 480, height: 30))
        row.configure(
            makeConfiguration(
                mode: .idle,
                supportedPermissionModes: [
                    .init(
                        value: "never",
                        title: "Full access",
                        description: "Unrestricted access to the internet and any file on your computer.",
                        symbolName: "exclamationmark.shield",
                        isWarning: true
                    )
                ],
                selectedPermissionMode: "never"
            )
        )

        let button = row.permissionButton
        XCTAssertEqual(button.accessibilityLabel(), "Permissions")
        XCTAssertEqual(button.accessibilityValue() as? String, "Full access")
        XCTAssertEqual(button.intrinsicContentSize.height, 24)
        #if DEBUG
        XCTAssertEqual(button.debugTitle, "Full access")
        XCTAssertEqual(button.debugSymbolName, "exclamationmark.shield")
        XCTAssertEqual(button.debugIconRotationRadians, 0, accuracy: 0.0001)
        XCTAssertTrue(button.debugIsWarning)
        XCTAssertEqual(button.debugTextChevronSpacing, button.debugIconTextSpacing)
        assertColorComponentsMatch(
            button.debugChevronColor,
            try XCTUnwrap(button.debugForegroundColor)
        )
        #endif
    }

    func testReasoningButtonShowsFastIconWithPermissionLeadingMetricsAndAccessibility() throws {
        let row = ChatComposerActionRowView(frame: NSRect(x: 0, y: 0, width: 520, height: 30))
        row.configure(makeConfiguration(
            mode: .idle,
            effortOptions: [.init(value: "medium", title: "Medium")],
            supportedPermissionModes: [.init(value: "default", title: "Default", symbolName: "hand.raised")]
        ))
        let reasoningButton = row.reasoningButton
        let permissionButton = row.permissionButton

        #if DEBUG
        XCTAssertFalse(reasoningButton.debugShowsFastIcon)
        #endif

        row.configure(makeConfiguration(
            mode: .idle,
            effortOptions: [.init(value: "medium", title: "Medium")],
            supportedPermissionModes: [.init(value: "default", title: "Default", symbolName: "hand.raised")],
            selectedSpeedMode: .fast,
            supportsSpeedMode: true
        ))
        row.layoutSubtreeIfNeeded()

        #if DEBUG
        XCTAssertTrue(reasoningButton.debugShowsFastIcon)
        XCTAssertEqual(reasoningButton.debugFastIconSlotSize, permissionButton.debugIconSlotSize)
        XCTAssertEqual(reasoningButton.debugFastIconTextSpacing, permissionButton.debugIconTextSpacing)
        let fastIconFrame = try XCTUnwrap(reasoningButton.debugFastIconFrame)
        let modelFrame = try XCTUnwrap(reasoningButton.debugModelFrame)
        XCTAssertEqual(fastIconFrame.minX, reasoningButton.contentDrawingRect.minX, accuracy: 0.5)
        XCTAssertEqual(modelFrame.minX - fastIconFrame.maxX, reasoningButton.debugFastIconTextSpacing, accuracy: 0.5)
        #endif
        XCTAssertEqual(reasoningButton.accessibilityValue() as? String, "Sonnet, Medium, Fast")
    }

    func testPlanModeButtonAppearsOnlyWhilePlanModeIsDisplayed() {
        let row = ChatComposerActionRowView(frame: NSRect(x: 0, y: 0, width: 480, height: 30))

        row.configure(makeConfiguration(mode: .idle, isPlanModeEnabled: false))
        XCTAssertNil(row.planModeButton.superview)

        row.configure(makeConfiguration(mode: .idle, isPlanModeEnabled: true))
        XCTAssertTrue(row.planModeButton.superview === row.stack)

        row.configure(makeConfiguration(mode: .idle, isPlanModeEnabled: false))
        XCTAssertNil(row.planModeButton.superview)
    }

    func testPlanModeButtonAppearsWhenPermissionModesAreUnavailable() {
        let row = ChatComposerActionRowView(frame: NSRect(x: 0, y: 0, width: 480, height: 30))
        row.configure(
            makeConfiguration(
                mode: .idle,
                supportedPermissionModes: [],
                isPlanModeEnabled: true
            )
        )

        XCTAssertNil(row.permissionButton.superview)
        XCTAssertTrue(row.planModeButton.superview === row.stack)
    }

    func testPlanModeButtonUsesPermissionStyleWithoutChevron() {
        let row = ChatComposerActionRowView(frame: NSRect(x: 0, y: 0, width: 480, height: 30))
        row.configure(makeConfiguration(mode: .idle, isPlanModeEnabled: true))

        let button = row.planModeButton
        XCTAssertEqual(button.accessibilityLabel(), "Exit plan mode")
        XCTAssertEqual(button.accessibilityValue() as? String, "Plan")
        XCTAssertEqual(button.intrinsicContentSize.height, 24)
        #if DEBUG
        XCTAssertEqual(button.debugTitle, "Plan")
        XCTAssertEqual(button.debugSymbolName, "checklist")
        XCTAssertEqual(button.debugIconRotationRadians, 0, accuracy: 0.0001)
        XCTAssertFalse(button.debugIsWarning)
        XCTAssertFalse(button.debugReservesTrailingSlot)
        XCTAssertFalse(button.debugDrawsChevron)
        #endif
    }

    func testBypassPermissionsShowsPlanOverrideTooltipWhilePlanModeIsActive() {
        let row = ChatComposerActionRowView(frame: NSRect(x: 0, y: 0, width: 480, height: 30))
        row.configure(
            makeConfiguration(
                mode: .idle,
                supportedPermissionModes: [
                    .init(
                        value: "bypassPermissions",
                        title: "Bypass permissions",
                        symbolName: "exclamationmark.shield",
                        isWarning: true
                    )
                ],
                selectedPermissionMode: "bypassPermissions",
                isPlanModeEnabled: true
            )
        )

        let expectedTooltip = "Plan mode is active, so Claude still asks for permission until Plan is turned off."
        XCTAssertEqual(row.permissionButton.toolTip, expectedTooltip)
        XCTAssertEqual(row.permissionButton.accessibilityValue() as? String, "Bypass permissions. \(expectedTooltip)")
    }

    func testBypassPermissionsDoesNotShowPlanOverrideTooltipOutsidePlanMode() {
        let row = ChatComposerActionRowView(frame: NSRect(x: 0, y: 0, width: 480, height: 30))
        row.configure(
            makeConfiguration(
                mode: .idle,
                supportedPermissionModes: [
                    .init(
                        value: "bypassPermissions",
                        title: "Bypass permissions",
                        symbolName: "exclamationmark.shield",
                        isWarning: true
                    )
                ],
                selectedPermissionMode: "bypassPermissions",
                isPlanModeEnabled: false
            )
        )

        XCTAssertNil(row.permissionButton.toolTip)
        XCTAssertEqual(row.permissionButton.accessibilityValue() as? String, "Bypass permissions")
    }

    func testPlanModeButtonHoverAndClickUpdateSymbolAndRouteExit() {
        let row = ChatComposerActionRowView(frame: NSRect(x: 0, y: 0, width: 480, height: 30))
        var changes: [Bool] = []
        row.configure(
            makeConfiguration(
                mode: .idle,
                isPlanModeEnabled: true,
                onPlanModeChange: { changes.append($0) }
            )
        )
        let button = row.planModeButton
        button.frame = NSRect(origin: .zero, size: button.intrinsicContentSize)
        button.display()

        button.mouseEntered(with: mouseEvent(type: .mouseEntered, at: NSPoint(x: 4, y: 4)))
        #if DEBUG
        XCTAssertEqual(button.debugSymbolName, "xmark")
        #endif
        button.display()
        #if DEBUG
        XCTAssertTrue(button.debugHasSymbolTransition)
        #endif

        button.mouseExited(with: mouseEvent(type: .mouseExited, at: NSPoint(x: -1, y: -1)))
        #if DEBUG
        XCTAssertEqual(button.debugSymbolName, "checklist")
        #endif
        button.display()
        #if DEBUG
        XCTAssertTrue(button.debugHasSymbolTransition)
        #endif

        button.mouseEntered(with: mouseEvent(type: .mouseEntered, at: NSPoint(x: 4, y: 4)))
        button.mouseDown(with: mouseEvent(type: .leftMouseDown, at: NSPoint(x: 4, y: 4)))
        button.mouseUp(with: mouseEvent(type: .leftMouseUp, at: NSPoint(x: 4, y: 4)))

        XCTAssertEqual(changes, [false])
        #if DEBUG
        XCTAssertEqual(button.debugSymbolName, "checklist")
        XCTAssertFalse(button.debugHasSymbolTransition)
        #endif
    }

    func testPlanModeButtonKeyboardAndAccessibilityActivationRouteExit() {
        let row = ChatComposerActionRowView(frame: NSRect(x: 0, y: 0, width: 480, height: 30))
        var changes: [Bool] = []
        row.configure(
            makeConfiguration(
                mode: .idle,
                isPlanModeEnabled: true,
                onPlanModeChange: { changes.append($0) }
            )
        )

        row.planModeButton.keyDown(with: keyEvent(keyCode: 36))
        XCTAssertTrue(row.planModeButton.accessibilityPerformPress())

        XCTAssertEqual(changes, [false, false])
    }

    func testGoalModeButtonAppearsOnlyWhenConfiguredVisible() {
        let row = ChatComposerActionRowView(frame: NSRect(x: 0, y: 0, width: 480, height: 30))

        row.configure(makeConfiguration(mode: .idle, isGoalModeChipVisible: false))
        XCTAssertNil(row.goalModeButton.superview)

        row.configure(makeConfiguration(mode: .idle, isGoalModeChipVisible: true, isGoalModeChipEnabled: true))
        XCTAssertTrue(row.goalModeButton.superview === row.stack)

        row.configure(makeConfiguration(mode: .idle, isGoalModeChipVisible: false))
        XCTAssertNil(row.goalModeButton.superview)
    }

    func testGoalModeButtonUsesPlanChipStyleWithoutChevron() {
        let row = ChatComposerActionRowView(frame: NSRect(x: 0, y: 0, width: 480, height: 30))
        row.configure(makeConfiguration(mode: .idle, isGoalModeChipVisible: true, isGoalModeChipEnabled: true))

        let button = row.goalModeButton
        XCTAssertEqual(button.accessibilityLabel(), "Disable goal mode")
        XCTAssertEqual(button.accessibilityValue() as? String, "Goal")
        XCTAssertEqual(button.intrinsicContentSize.height, 24)
        #if DEBUG
        XCTAssertEqual(button.debugTitle, "Goal")
        XCTAssertEqual(button.debugSymbolName, "target")
        XCTAssertEqual(button.debugIconRotationRadians, 0, accuracy: 0.0001)
        XCTAssertFalse(button.debugIsWarning)
        XCTAssertFalse(button.debugReservesTrailingSlot)
        XCTAssertFalse(button.debugDrawsChevron)
        #endif
    }

    func testGoalModeButtonHoverAndClickRouteDismiss() {
        let row = ChatComposerActionRowView(frame: NSRect(x: 0, y: 0, width: 480, height: 30))
        var dismissCount = 0
        row.configure(
            makeConfiguration(
                mode: .idle,
                isGoalModeChipVisible: true,
                isGoalModeChipEnabled: true,
                onGoalModeChipDismiss: { dismissCount += 1 }
            )
        )
        let button = row.goalModeButton
        button.frame = NSRect(origin: .zero, size: button.intrinsicContentSize)
        button.display()

        button.mouseEntered(with: mouseEvent(type: .mouseEntered, at: NSPoint(x: 4, y: 4)))
        #if DEBUG
        XCTAssertEqual(button.debugSymbolName, "xmark")
        #endif

        button.mouseDown(with: mouseEvent(type: .leftMouseDown, at: NSPoint(x: 4, y: 4)))
        button.mouseUp(with: mouseEvent(type: .leftMouseUp, at: NSPoint(x: 4, y: 4)))

        XCTAssertEqual(dismissCount, 1)
        #if DEBUG
        XCTAssertEqual(button.debugSymbolName, "target")
        XCTAssertFalse(button.debugHasSymbolTransition)
        #endif
    }

    func testDisabledGoalModeButtonStaysVisibleWithoutHoverOrAction() {
        let row = ChatComposerActionRowView(frame: NSRect(x: 0, y: 0, width: 480, height: 30))
        var dismissCount = 0
        row.configure(
            makeConfiguration(
                mode: .idle,
                isGoalModeChipVisible: true,
                isGoalModeChipEnabled: false,
                onGoalModeChipDismiss: { dismissCount += 1 }
            )
        )

        let button = row.goalModeButton
        XCTAssertTrue(button.superview === row.stack)
        button.mouseEntered(with: mouseEvent(type: .mouseEntered, at: NSPoint(x: 4, y: 4)))

        #if DEBUG
        XCTAssertEqual(button.debugSymbolName, "target")
        #endif
        XCTAssertFalse(button.accessibilityPerformPress())
        XCTAssertEqual(dismissCount, 0)
    }

    func testDisabledPlanModeButtonStaysVisibleWithoutHoverOrAction() {
        let row = ChatComposerActionRowView(frame: NSRect(x: 0, y: 0, width: 480, height: 30))
        var changes: [Bool] = []
        row.configure(
            makeConfiguration(
                mode: .idle,
                isPlanModeEnabled: true,
                areControlsDisabled: true,
                onPlanModeChange: { changes.append($0) }
            )
        )

        let button = row.planModeButton
        XCTAssertTrue(button.superview === row.stack)
        button.mouseEntered(with: mouseEvent(type: .mouseEntered, at: NSPoint(x: 4, y: 4)))

        #if DEBUG
        XCTAssertEqual(button.debugSymbolName, "checklist")
        #endif
        XCTAssertFalse(button.accessibilityPerformPress())
        XCTAssertTrue(changes.isEmpty)
    }

    func testNarrowRowWithPlanModeButtonKeepsControlsInBounds() throws {
        let row = ChatComposerActionRowView(frame: NSRect(x: 0, y: 0, width: 340, height: 30))
        row.configure(
            makeConfiguration(
                mode: .idle,
                modelOptions: [
                    .init(value: "sonnet", title: "Sonnet"),
                    .init(value: "opus", title: "Extremely Wide Model Name")
                ],
                effortOptions: [.init(value: "medium", title: "Medium")],
                supportedPermissionModes: [.init(value: "default", title: "Default")],
                isPlanModeEnabled: true
            )
        )

        row.layoutSubtreeIfNeeded()

        let settingFrames = row.permissionDescendants(of: ComposerCompactDropdownButton.self)
            .map { $0.convert($0.bounds, to: row) }
        XCTAssertFalse(settingFrames.isEmpty)
        XCTAssertTrue(settingFrames.allSatisfy { $0.minX >= 0 })

        let actionButton = try XCTUnwrap(row.permissionDescendants(of: ComposerActionButton.self).first)
        let actionFrame = actionButton.convert(actionButton.bounds, to: row)
        XCTAssertLessThanOrEqual(actionFrame.maxX, row.bounds.maxX)
    }
}

private extension NSView {
    func permissionDescendants<ViewType: NSView>(of type: ViewType.Type) -> [ViewType] {
        subviews.flatMap { child -> [ViewType] in
            var matches = child.permissionDescendants(of: type)
            if let typed = child as? ViewType {
                matches.insert(typed, at: 0)
            }
            return matches
        }
    }
}

private func assertColorComponentsMatch(
    _ firstColor: NSColor,
    _ secondColor: NSColor,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    guard let firstColor = firstColor.usingColorSpace(.sRGB),
          let secondColor = secondColor.usingColorSpace(.sRGB) else {
        XCTFail("Expected colors to resolve to sRGB", file: file, line: line)
        return
    }

    XCTAssertEqual(
        firstColor.redComponent,
        secondColor.redComponent,
        accuracy: 0.0001,
        file: file,
        line: line
    )
    XCTAssertEqual(
        firstColor.greenComponent,
        secondColor.greenComponent,
        accuracy: 0.0001,
        file: file,
        line: line
    )
    XCTAssertEqual(
        firstColor.blueComponent,
        secondColor.blueComponent,
        accuracy: 0.0001,
        file: file,
        line: line
    )
    XCTAssertEqual(
        firstColor.alphaComponent,
        secondColor.alphaComponent,
        accuracy: 0.0001,
        file: file,
        line: line
    )
}

private func mouseEvent(type: NSEvent.EventType = .leftMouseUp, at point: NSPoint) -> NSEvent {
    let mouseEventType: NSEvent.EventType = switch type {
    case .mouseEntered, .mouseExited:
        .mouseMoved
    default:
        type
    }
    return NSEvent.mouseEvent(
        with: mouseEventType,
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

private func keyEvent(keyCode: UInt16) -> NSEvent {
    NSEvent.keyEvent(
        with: .keyDown,
        location: .zero,
        modifierFlags: [],
        timestamp: 0,
        windowNumber: 0,
        context: nil,
        characters: "\r",
        charactersIgnoringModifiers: "\r",
        isARepeat: false,
        keyCode: keyCode
    ) ?? NSEvent()
}
