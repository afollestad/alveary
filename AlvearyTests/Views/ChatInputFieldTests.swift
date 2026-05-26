import SwiftUI
import XCTest

@testable import Alveary

@MainActor
final class ChatInputFieldTests: XCTestCase {
    func testProjectTrustBlockedComposerDoesNotSubmitOrSteer() {
        var didSubmit = false
        var didSteer = false
        let input = makeInput(
            text: "Review the trust gate.",
            isProjectTrustBlocked: true,
            onSubmit: { didSubmit = true },
            onSteer: { didSteer = true }
        )

        input.performSubmit()
        input.performSteer()

        XCTAssertFalse(didSubmit)
        XCTAssertFalse(didSteer)
    }

    func testUnblockedComposerSubmitsAndSteers() {
        var didSubmit = false
        var didSteer = false
        let input = makeInput(
            text: "Review the trust gate.",
            isProjectTrustBlocked: false,
            onSubmit: { didSubmit = true },
            onSteer: { didSteer = true }
        )

        input.performSubmit()
        input.performSteer()

        XCTAssertTrue(didSubmit)
        XCTAssertTrue(didSteer)
    }

    func testHandoffSteeringComposerAllowsEmptySubmit() {
        var didSubmit = false
        let input = makeInput(
            text: "",
            isHandoffSteeringPromptActive: true,
            isProjectTrustBlocked: false,
            onSubmit: { didSubmit = true },
            onSteer: {}
        )

        input.performSubmit()

        XCTAssertTrue(didSubmit)
    }

    func testHandoffSteeringComposerUsesSubmitCopyAndPlaceholder() {
        let input = makeInput(
            text: "",
            isHandoffSteeringPromptActive: true,
            handoffSteeringCountdown: 10,
            isProjectTrustBlocked: false,
            onSubmit: {},
            onSteer: {}
        )

        XCTAssertEqual(input.primaryActionTitle, "Submit (10)")
        XCTAssertEqual(input.primaryActionSystemImage, "checkmark")
        XCTAssertEqual(input.placeholder, ComposerPresentation.handoffSteeringPlaceholder)
        XCTAssertFalse(input.isPrimaryActionDisabled)
        XCTAssertTrue(input.areControlsDisabled)
    }

    func testHandoffOutputComposerUsesSubmitCopy() {
        let input = makeInput(
            text: "Carry this context forward.",
            isHandoffOutputPromptActive: true,
            sendCountdown: 10,
            isProjectTrustBlocked: false,
            onSubmit: {},
            onSteer: {}
        )

        XCTAssertEqual(input.primaryActionTitle, "Submit (10)")
        XCTAssertEqual(input.primaryActionSystemImage, "checkmark")
        XCTAssertFalse(input.isPrimaryActionDisabled)
        XCTAssertFalse(input.areControlsDisabled)
    }

    func testEditedHandoffOutputComposerKeepsSubmitCopyAfterCountdownCancels() {
        let input = makeInput(
            text: "Edited handoff context.",
            isHandoffOutputPromptActive: true,
            sendCountdown: nil,
            isProjectTrustBlocked: false,
            onSubmit: {},
            onSteer: {}
        )

        XCTAssertEqual(input.primaryActionTitle, "Submit")
        XCTAssertEqual(input.primaryActionSystemImage, "checkmark")
        XCTAssertFalse(input.isPrimaryActionDisabled)
        XCTAssertFalse(input.areControlsDisabled)
    }

    func testBusyReturnUsesQueueDefaultAndOptionReturnSteers() {
        var didSubmit = false
        var didSteer = false
        let input = makeInput(
            text: "Review the active turn.",
            mode: .busy(canStop: true),
            defaultEnterBehavior: .queue,
            isProjectTrustBlocked: false,
            onSubmit: { didSubmit = true },
            onSteer: { didSteer = true }
        )

        XCTAssertEqual(input.handleKeyPress(returnKeyPress()), .handled)
        XCTAssertTrue(didSubmit)
        XCTAssertFalse(didSteer)

        didSubmit = false
        XCTAssertEqual(input.handleKeyPress(optionReturnKeyPress()), .handled)
        XCTAssertFalse(didSubmit)
        XCTAssertTrue(didSteer)
    }

    func testBusyReturnUsesSteerDefaultAndOptionReturnQueues() {
        var didSubmit = false
        var didSteer = false
        let input = makeInput(
            text: "Review the active turn.",
            mode: .busy(canStop: true),
            defaultEnterBehavior: .steer,
            isProjectTrustBlocked: false,
            onSubmit: { didSubmit = true },
            onSteer: { didSteer = true }
        )

        XCTAssertEqual(input.handleKeyPress(returnKeyPress()), .handled)
        XCTAssertFalse(didSubmit)
        XCTAssertTrue(didSteer)

        didSteer = false
        XCTAssertEqual(input.handleKeyPress(optionReturnKeyPress()), .handled)
        XCTAssertTrue(didSubmit)
        XCTAssertFalse(didSteer)
    }

    func testBusyReturnQueuesWhenSteeringIsUnsupported() {
        var didSubmit = false
        var didSteer = false
        let input = makeInput(
            text: "Review the active turn.",
            mode: .busy(canStop: true),
            defaultEnterBehavior: .steer,
            supportsMidTurnSteering: false,
            isProjectTrustBlocked: false,
            onSubmit: { didSubmit = true },
            onSteer: { didSteer = true }
        )

        XCTAssertEqual(input.handleKeyPress(optionReturnKeyPress()), .handled)
        XCTAssertTrue(didSubmit)
        XCTAssertFalse(didSteer)
    }

    func testIdleOptionReturnSubmits() {
        var didSubmit = false
        let input = makeInput(
            text: "Start a turn.",
            mode: .idle,
            defaultEnterBehavior: .steer,
            isProjectTrustBlocked: false,
            onSubmit: { didSubmit = true },
            onSteer: {}
        )

        XCTAssertEqual(input.handleKeyPress(optionReturnKeyPress()), .handled)
        XCTAssertTrue(didSubmit)
    }

    func testBusyPlaceholderReflectsDefaultEnterBehavior() {
        let queueInput = makeInput(
            text: "",
            mode: .busy(canStop: true),
            defaultEnterBehavior: .queue,
            isProjectTrustBlocked: false,
            onSubmit: {},
            onSteer: {}
        )
        let steerInput = makeInput(
            text: "",
            mode: .busy(canStop: true),
            defaultEnterBehavior: .steer,
            isProjectTrustBlocked: false,
            onSubmit: {},
            onSteer: {}
        )

        XCTAssertEqual(queueInput.placeholder, "Enter to queue for the next turn, or Option+Enter to steer...")
        XCTAssertEqual(steerInput.placeholder, "Enter to steer the current turn, or Option+Enter to queue...")
    }

    func testStopConfirmationDecisionArmsOnFirstEscape() {
        XCTAssertEqual(
            ChatInputStopConfirmationDecision.resolve(
                keyPress: escapeKeyPress(),
                canUseEscapeToStop: true,
                isConfirmationArmed: false
            ),
            .armConfirmation
        )
    }

    func testStopConfirmationDecisionConfirmsOnSecondEscape() {
        XCTAssertEqual(
            ChatInputStopConfirmationDecision.resolve(
                keyPress: escapeKeyPress(),
                canUseEscapeToStop: true,
                isConfirmationArmed: true
            ),
            .confirmStop
        )
    }

    func testStopConfirmationDecisionIgnoresWhenStopUnavailable() {
        XCTAssertEqual(
            ChatInputStopConfirmationDecision.resolve(
                keyPress: escapeKeyPress(),
                canUseEscapeToStop: false,
                isConfirmationArmed: true
            ),
            .ignored
        )
        XCTAssertTrue(ChatInputStopConfirmationDecision.shouldClearWhenStopUnavailable(false))
    }

    func testStopConfirmationDecisionIgnoresModifiedEscape() {
        XCTAssertEqual(
            ChatInputStopConfirmationDecision.resolve(
                keyPress: AppTextEditorKeyPress(key: .escape, modifiers: .option),
                canUseEscapeToStop: true,
                isConfirmationArmed: false
            ),
            .ignored
        )
    }

    func testStopConfirmationDecisionKeepsStateWhenStopAvailable() {
        XCTAssertFalse(ChatInputStopConfirmationDecision.shouldClearWhenStopUnavailable(true))
    }

    func testStopConfirmationDecisionClearsOnlyArmedTimeout() {
        XCTAssertTrue(ChatInputStopConfirmationDecision.shouldClearAfterConfirmationTimeout(true))
        XCTAssertFalse(ChatInputStopConfirmationDecision.shouldClearAfterConfirmationTimeout(false))
    }

    func testFocusRequestConsumptionDoesNotClearNewerToken() {
        let oldToken = UUID()
        let newToken = UUID()

        XCTAssertTrue(ChatInputField.shouldClearFocusRequestToken(current: oldToken, consumed: oldToken))
        XCTAssertFalse(ChatInputField.shouldClearFocusRequestToken(current: newToken, consumed: oldToken))
    }

    private func makeInput(
        text: String,
        mode: ComposerMode = .idle,
        defaultEnterBehavior: ThreadEnterDefaultBehavior = AppSettings.defaultEnterBehavior,
        supportsMidTurnSteering: Bool = true,
        isHandoffSteeringPromptActive: Bool = false,
        isHandoffOutputPromptActive: Bool = false,
        handoffSteeringCountdown: Int? = nil,
        sendCountdown: Int? = nil,
        isProjectTrustBlocked: Bool,
        onSubmit: @escaping () -> Void,
        onSteer: @escaping () -> Void
    ) -> ChatInputField {
        ChatInputField(
            text: .constant(text),
            mode: mode,
            defaultEnterBehavior: defaultEnterBehavior,
            onSubmit: onSubmit,
            onSteer: onSteer,
            onStop: nil,
            selectedModel: .constant("default"),
            selectedEffort: .constant("medium"),
            selectedPermissionMode: .constant("default"),
            supportedPermissionModes: [
                PermissionModeOption(
                    value: "default",
                    label: "Default permissions",
                    description: "Prompt before restricted tool actions."
                )
            ],
            supportedEffortLevels: ["low", "medium", "high"],
            supportsMidTurnSteering: supportsMidTurnSteering,
            isProjectTrustBlocked: isProjectTrustBlocked,
            isHandoffSteeringPromptActive: isHandoffSteeringPromptActive,
            isHandoffOutputPromptActive: isHandoffOutputPromptActive,
            handoffSteeringCountdown: handoffSteeringCountdown,
            sendCountdown: sendCountdown,
            workingDirectory: "/tmp/alveary",
            loadFileCompletions: { [] },
            loadSkillCompletions: { [] }
        )
    }

    private func escapeKeyPress() -> AppTextEditorKeyPress {
        AppTextEditorKeyPress(key: .escape, modifiers: [])
    }

    private func returnKeyPress() -> AppTextEditorKeyPress {
        AppTextEditorKeyPress(key: .return, modifiers: [])
    }

    private func optionReturnKeyPress() -> AppTextEditorKeyPress {
        AppTextEditorKeyPress(key: .return, modifiers: .option)
    }
}
