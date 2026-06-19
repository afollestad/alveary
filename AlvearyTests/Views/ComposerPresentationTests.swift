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

    func testEmptyCodeBlockCountsAsEmptyComposerText() {
        let presentation = makePresentation(text: "```\n")

        XCTAssertTrue(presentation.isTextEffectivelyEmpty)
        XCTAssertFalse(presentation.canSubmit)
        XCTAssertFalse(presentation.canSteer)
        XCTAssertTrue(presentation.isPrimaryActionDisabled)
    }

    func testWhitespaceOnlyCodeBlockCountsAsEmptyComposerText() {
        let presentation = makePresentation(text: " \n```swift\n  \n```\n ")

        XCTAssertTrue(presentation.isTextEffectivelyEmpty)
        XCTAssertFalse(presentation.canSubmit)
        XCTAssertFalse(presentation.canSteer)
        XCTAssertTrue(presentation.isPrimaryActionDisabled)
    }

    func testCodeBlockWithContentCanSubmit() {
        let presentation = makePresentation(text: "```\nlet value = 1\n```")

        XCTAssertFalse(presentation.isTextEffectivelyEmpty)
        XCTAssertTrue(presentation.canSubmit)
        XCTAssertTrue(presentation.canSteer)
        XCTAssertFalse(presentation.isPrimaryActionDisabled)
    }

    func testCachedEffectiveEmptyStateDrivesSubmitAvailability() {
        let presentation = makePresentation(
            text: "Pending BlockInput markdown publish",
            isTextEffectivelyEmpty: true
        )

        XCTAssertTrue(presentation.isTextEffectivelyEmpty)
        XCTAssertFalse(presentation.canSubmit)
        XCTAssertFalse(presentation.canSteer)
        XCTAssertTrue(presentation.isPrimaryActionDisabled)
    }

    func testTextAroundEmptyCodeBlockCanSubmit() {
        let presentation = makePresentation(text: "Review this\n```\n```")

        XCTAssertFalse(presentation.isTextEffectivelyEmpty)
        XCTAssertTrue(presentation.canSubmit)
        XCTAssertTrue(presentation.canSteer)
        XCTAssertFalse(presentation.isPrimaryActionDisabled)
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

    func testBusyPlaceholdersUseCmdEnterCopy() {
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

        XCTAssertEqual(queueDefault.placeholder, "Enter to queue for the next turn, or Cmd+Enter to steer...")
        XCTAssertEqual(steerDefault.placeholder, "Enter to steer the current turn, or Cmd+Enter to queue...")
    }

    func testAlternateSteerRoutingIsOnlyForQueueDefaultAlternateSteer() {
        let emptyQueueDefault = makePresentation(
            text: "",
            isTextEffectivelyEmpty: true,
            mode: .busy(canStop: true),
            defaultEnterBehavior: .queue
        )
        let queueDefaultPlainReturn = makePresentation(
            text: "Queue",
            mode: .busy(canStop: true),
            defaultEnterBehavior: .queue
        )
        let steerDefault = makePresentation(
            text: "Steer",
            mode: .busy(canStop: true),
            defaultEnterBehavior: .steer
        )
        let trustBlocked = makePresentation(
            text: "Blocked",
            mode: .busy(canStop: true),
            defaultEnterBehavior: .queue,
            isProjectTrustBlocked: true
        )
        let unsupported = makePresentation(
            text: "Unsupported",
            mode: .busy(canStop: true),
            defaultEnterBehavior: .queue,
            supportsMidTurnSteering: false
        )

        XCTAssertTrue(emptyQueueDefault.canUseAlternateSteer(usesAlternateBehavior: true))
        XCTAssertFalse(emptyQueueDefault.canSteer)
        XCTAssertFalse(queueDefaultPlainReturn.canUseAlternateSteer(usesAlternateBehavior: false))
        XCTAssertFalse(steerDefault.canUseAlternateSteer(usesAlternateBehavior: true))
        XCTAssertFalse(trustBlocked.canUseAlternateSteer(usesAlternateBehavior: true))
        XCTAssertFalse(unsupported.canUseAlternateSteer(usesAlternateBehavior: true))
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
        let notReady = makePresentation(
            text: "Queue this.",
            mode: .busy(canStop: true),
            defaultEnterBehavior: .steer,
            canSteerCurrentTurn: false
        )

        XCTAssertEqual(cannotStop.busyReturnAction(usesAlternateBehavior: false), .submit)
        XCTAssertEqual(unsupported.busyReturnAction(usesAlternateBehavior: false), .submit)
        XCTAssertEqual(notReady.busyReturnAction(usesAlternateBehavior: false), .submit)
        XCTAssertFalse(notReady.canSteer)
        XCTAssertEqual(notReady.placeholder, "Type a message to queue for the next turn...")
    }

    func testBusyTurnWithStopKeepsSettingControlsEnabled() {
        let presentation = makePresentation(
            text: "Queue this.",
            mode: .busy(canStop: true)
        )

        XCTAssertFalse(presentation.areControlsDisabled)
    }

    func testToolApprovalKeepsSettingControlsEnabled() {
        let presentation = makePresentation(
            text: "Approve this.",
            mode: .progressOnly(.toolApproval(.genericApproval))
        )

        XCTAssertFalse(presentation.areControlsDisabled)
    }

    func testSendInFlightAndHandoffStillDisableSettingControls() {
        let sendInFlight = makePresentation(
            text: "Pending send.",
            mode: .busy(canStop: false)
        )
        let handoff = makePresentation(
            text: "",
            mode: .progressOnly(.sessionHandoff)
        )

        XCTAssertTrue(sendInFlight.areControlsDisabled)
        XCTAssertTrue(handoff.areControlsDisabled)
    }

    private func makePresentation(
        text: String,
        isTextEffectivelyEmpty: Bool? = nil,
        mode: ComposerMode = .idle,
        defaultEnterBehavior: ThreadEnterDefaultBehavior = .queue,
        supportsMidTurnSteering: Bool = true,
        canSteerCurrentTurn: Bool = true,
        isHandoffSteeringPromptActive: Bool = false,
        isHandoffOutputPromptActive: Bool = false,
        handoffSteeringCountdown: Int? = nil,
        sendCountdown: Int? = nil,
        isProjectTrustBlocked: Bool = false
    ) -> ComposerPresentation {
        ComposerPresentation(
            text: text,
            isTextEffectivelyEmpty: isTextEffectivelyEmpty,
            mode: mode,
            defaultEnterBehavior: defaultEnterBehavior,
            supportsMidTurnSteering: supportsMidTurnSteering,
            canSteerCurrentTurn: canSteerCurrentTurn,
            isHandoffSteeringPromptActive: isHandoffSteeringPromptActive,
            isHandoffOutputPromptActive: isHandoffOutputPromptActive,
            handoffSteeringCountdown: handoffSteeringCountdown,
            sendCountdown: sendCountdown,
            isProjectTrustBlocked: isProjectTrustBlocked
        )
    }
}
