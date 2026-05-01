import XCTest

@testable import Alveary

final class ComposerPresentationTests: XCTestCase {
    func testProjectTrustBlocksComposerActionsAndControls() {
        let presentation = makePresentation(
            text: "Review this.",
            isProjectTrustBlocked: true
        )

        XCTAssertFalse(presentation.canSubmit)
        XCTAssertFalse(presentation.canSteer)
        XCTAssertTrue(presentation.isPrimaryActionDisabled)
        XCTAssertTrue(presentation.isTextEditorDisabled)
        XCTAssertTrue(presentation.areControlsDisabled)
        XCTAssertEqual(presentation.placeholder, "Trust this project to enable the composer")
    }

    func testHandoffSteeringAllowsEmptySubmitAndDisablesControls() {
        let presentation = makePresentation(
            text: "",
            isHandoffSteeringPromptActive: true,
            handoffSteeringCountdown: 3
        )

        XCTAssertTrue(presentation.canSubmit)
        XCTAssertFalse(presentation.canSteer)
        XCTAssertEqual(presentation.primaryActionTitle, "Submit (3)")
        XCTAssertEqual(presentation.primaryActionSystemImage, "checkmark")
        XCTAssertTrue(presentation.areControlsDisabled)
        XCTAssertEqual(presentation.placeholder, ComposerPresentation.handoffSteeringPlaceholder)
    }

    func testBusyReturnActionFollowsDefaultAndAlternateBehavior() {
        let queueDefault = makePresentation(
            text: "Steer or queue",
            mode: .busy(canStop: true),
            defaultEnterBehavior: .queue
        )
        let steerDefault = makePresentation(
            text: "Steer or queue",
            mode: .busy(canStop: true),
            defaultEnterBehavior: .steer
        )

        XCTAssertEqual(queueDefault.busyReturnAction(usesAlternateBehavior: false), .submit)
        XCTAssertEqual(queueDefault.busyReturnAction(usesAlternateBehavior: true), .steer)
        XCTAssertEqual(steerDefault.busyReturnAction(usesAlternateBehavior: false), .steer)
        XCTAssertEqual(steerDefault.busyReturnAction(usesAlternateBehavior: true), .submit)
    }

    func testBusyReturnFallsBackToSubmitWhenSteeringIsUnavailable() {
        let cannotStop = makePresentation(
            text: "Queue this.",
            mode: .busy(canStop: false),
            defaultEnterBehavior: .steer
        )
        let unsupported = makePresentation(
            text: "Queue this.",
            mode: .busy(canStop: true),
            defaultEnterBehavior: .steer,
            supportsMidTurnSteering: false
        )

        XCTAssertEqual(cannotStop.busyReturnAction(usesAlternateBehavior: false), .submit)
        XCTAssertEqual(unsupported.busyReturnAction(usesAlternateBehavior: false), .submit)
    }

    func testVisibleEffortLevelsIntersectProviderAndModelSupport() {
        XCTAssertEqual(
            ComposerSettingsPresentation.visibleEffortLevels(
                selectedModel: "sonnet",
                providerSupportedEffortLevels: ["low", "medium", "high", "xhigh", "max"]
            ),
            ["low", "medium", "high", "max"]
        )
        XCTAssertEqual(
            ComposerSettingsPresentation.visibleEffortLevels(
                selectedModel: "opus",
                providerSupportedEffortLevels: ["medium", "xhigh", "max"]
            ),
            ["medium", "xhigh", "max"]
        )
    }

    private func makePresentation(
        text: String,
        mode: ComposerMode = .idle,
        defaultEnterBehavior: ThreadEnterDefaultBehavior = .queue,
        supportsMidTurnSteering: Bool = true,
        isHandoffSteeringPromptActive: Bool = false,
        isHandoffOutputPromptActive: Bool = false,
        handoffSteeringCountdown: Int? = nil,
        sendCountdown: Int? = nil,
        isProjectTrustBlocked: Bool = false
    ) -> ComposerPresentation {
        ComposerPresentation(
            text: text,
            mode: mode,
            defaultEnterBehavior: defaultEnterBehavior,
            supportsMidTurnSteering: supportsMidTurnSteering,
            isHandoffSteeringPromptActive: isHandoffSteeringPromptActive,
            isHandoffOutputPromptActive: isHandoffOutputPromptActive,
            handoffSteeringCountdown: handoffSteeringCountdown,
            sendCountdown: sendCountdown,
            isProjectTrustBlocked: isProjectTrustBlocked
        )
    }
}
