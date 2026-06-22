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
}

private func goalModePlusMenuConfiguration(
    isGoalModeArmed: Bool = false,
    isGoalModeToggleEnabled: Bool = true,
    goalModeDisabledTooltip: String? = nil,
    onGoalModeChange: @escaping (Bool) -> Void = { _ in }
) -> ComposerPlusMenuViewController.Configuration {
    .init(
        isGoalModeArmed: isGoalModeArmed,
        isGoalModeToggleEnabled: isGoalModeToggleEnabled,
        goalModeDisabledTooltip: goalModeDisabledTooltip,
        isPlanModeEnabled: false,
        isPlanModeToggleEnabled: true,
        planModeDisabledTooltip: nil,
        onAddPhotosAndFiles: {},
        onPlanModeChange: { _ in },
        onGoalModeChange: onGoalModeChange
    )
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
