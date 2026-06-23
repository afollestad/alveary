import AppKit
import XCTest

@testable import Alveary

@MainActor
extension ChatComposerPlusMenuTests {
    func testPlusMenuGoalRowRoutesActions() throws {
        var goalModeChanges: [Bool] = []
        let controller = ComposerPlusMenuViewController(configuration: goalModePlusMenuConfiguration(
            onGoalModeChange: { goalModeChanges.append($0) }
        ))
        controller.loadViewIfNeeded()

        let goalRow = try XCTUnwrap(
            controller.view.goalModeDescendants(of: NSView.self).first { $0.accessibilityLabel() == "Toggle goal mode" }
        )
        XCTAssertTrue(goalRow.accessibilityPerformPress())
        XCTAssertTrue(goalRow.accessibilityPerformPress())
        XCTAssertEqual(goalModeChanges, [true, false])
    }

    func testPlusMenuGoalRowIgnoresPressesWhenDisabled() throws {
        var goalModeChanges: [Bool] = []
        let controller = ComposerPlusMenuViewController(configuration: goalModePlusMenuConfiguration(
            isGoalModeToggleEnabled: false,
            goalModeDisabledTooltip: "Unsupported",
            onGoalModeChange: { goalModeChanges.append($0) }
        ))
        controller.loadViewIfNeeded()

        let goalRow = try XCTUnwrap(
            controller.view.goalModeDescendants(of: NSView.self).first { $0.accessibilityLabel() == "Toggle goal mode" }
        )
        XCTAssertFalse(goalRow.accessibilityPerformPress())
        XCTAssertTrue(goalModeChanges.isEmpty)
    }

    func testPlusMenuGoalRowActivatesFromKeyboard() throws {
        var goalModeChanges: [Bool] = []
        let controller = ComposerPlusMenuViewController(configuration: goalModePlusMenuConfiguration(
            onGoalModeChange: { goalModeChanges.append($0) }
        ))
        controller.loadViewIfNeeded()

        let goalRow = try XCTUnwrap(
            controller.view.goalModeDescendants(of: ComposerPlusMenuRowView.self).first {
                $0.accessibilityLabel() == "Toggle goal mode"
            }
        )

        goalRow.keyDown(with: goalModeKeyEvent(keyCode: 49))

        XCTAssertEqual(goalModeChanges, [true])
    }

    func testPlusMenuGoalRowTurnsOffVisiblePlanSwitchWhenEnabled() throws {
        var goalModeChanges: [Bool] = []
        var planModeChanges: [Bool] = []
        let controller = ComposerPlusMenuViewController(configuration: goalModePlusMenuConfiguration(
            isPlanModeEnabled: true,
            onPlanModeChange: { planModeChanges.append($0) },
            onGoalModeChange: { goalModeChanges.append($0) }
        ))
        controller.loadViewIfNeeded()

        let goalRow = try XCTUnwrap(
            controller.view.goalModeDescendants(of: NSView.self).first { $0.accessibilityLabel() == "Toggle goal mode" }
        )
        let goalSwitch = try XCTUnwrap(goalModeSwitch(in: controller.view, label: "Goal mode"))
        let planSwitch = try XCTUnwrap(goalModeSwitch(in: controller.view, label: "Plan mode"))

        XCTAssertEqual(goalSwitch.state, .off)
        XCTAssertEqual(planSwitch.state, .on)

        XCTAssertTrue(goalRow.accessibilityPerformPress())

        XCTAssertEqual(goalSwitch.state, .on)
        XCTAssertEqual(goalSwitch.accessibilityValue(), "On")
        XCTAssertEqual(planSwitch.state, .off)
        XCTAssertEqual(planSwitch.accessibilityValue(), "Off")
        XCTAssertEqual(goalModeChanges, [true])
        XCTAssertTrue(planModeChanges.isEmpty)
    }

    func testPlusMenuPlanRowTurnsOffVisibleGoalSwitchWhenEnabled() throws {
        var goalModeChanges: [Bool] = []
        var planModeChanges: [Bool] = []
        let controller = ComposerPlusMenuViewController(configuration: goalModePlusMenuConfiguration(
            isGoalModeArmed: true,
            onPlanModeChange: { planModeChanges.append($0) },
            onGoalModeChange: { goalModeChanges.append($0) }
        ))
        controller.loadViewIfNeeded()

        let planRow = try XCTUnwrap(
            controller.view.goalModeDescendants(of: NSView.self).first { $0.accessibilityLabel() == "Toggle plan mode" }
        )
        let goalSwitch = try XCTUnwrap(goalModeSwitch(in: controller.view, label: "Goal mode"))
        let planSwitch = try XCTUnwrap(goalModeSwitch(in: controller.view, label: "Plan mode"))

        XCTAssertEqual(goalSwitch.state, .on)
        XCTAssertEqual(planSwitch.state, .off)

        XCTAssertTrue(planRow.accessibilityPerformPress())

        XCTAssertEqual(goalSwitch.state, .off)
        XCTAssertEqual(goalSwitch.accessibilityValue(), "Off")
        XCTAssertEqual(planSwitch.state, .on)
        XCTAssertEqual(planSwitch.accessibilityValue(), "On")
        XCTAssertEqual(planModeChanges, [true])
        XCTAssertTrue(goalModeChanges.isEmpty)
    }
}

private func goalModePlusMenuConfiguration(
    isGoalModeArmed: Bool = false,
    isGoalModeToggleEnabled: Bool = true,
    goalModeDisabledTooltip: String? = nil,
    isPlanModeEnabled: Bool = false,
    onPlanModeChange: @escaping (Bool) -> Void = { _ in },
    onGoalModeChange: @escaping (Bool) -> Void = { _ in }
) -> ComposerPlusMenuViewController.Configuration {
    .init(
        isGoalModeArmed: isGoalModeArmed,
        isGoalModeToggleEnabled: isGoalModeToggleEnabled,
        goalModeDisabledTooltip: goalModeDisabledTooltip,
        isPlanModeEnabled: isPlanModeEnabled,
        isPlanModeToggleEnabled: true,
        planModeDisabledTooltip: nil,
        onAddPhotosAndFiles: {},
        onPlanModeChange: onPlanModeChange,
        onGoalModeChange: onGoalModeChange
    )
}

@MainActor
private func goalModeSwitch(in view: NSView, label: String) -> NSSwitch? {
    view.goalModeDescendants(of: NSSwitch.self).first { $0.accessibilityLabel() == label }
}

private extension NSView {
    func goalModeDescendants<ViewType: NSView>(of type: ViewType.Type) -> [ViewType] {
        subviews.flatMap { child -> [ViewType] in
            var matches = child.goalModeDescendants(of: type)
            if let typed = child as? ViewType {
                matches.insert(typed, at: 0)
            }
            return matches
        }
    }
}

private func goalModeKeyEvent(keyCode: UInt16) -> NSEvent {
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
