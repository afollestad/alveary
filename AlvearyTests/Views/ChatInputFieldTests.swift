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

    private func makeInput(
        text: String,
        isProjectTrustBlocked: Bool,
        onSubmit: @escaping () -> Void,
        onSteer: @escaping () -> Void
    ) -> ChatInputField {
        ChatInputField(
            text: .constant(text),
            mode: .idle,
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
            supportsMidTurnSteering: true,
            isProjectTrustBlocked: isProjectTrustBlocked,
            workingDirectory: "/tmp/alveary",
            loadFileCompletions: { [] },
            loadSkillCompletions: { [] }
        )
    }

    private func escapeKeyPress() -> AppTextEditorKeyPress {
        AppTextEditorKeyPress(key: .escape, modifiers: [])
    }
}
