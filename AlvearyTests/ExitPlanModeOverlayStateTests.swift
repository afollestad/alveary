import XCTest

@testable import Alveary

@MainActor
final class ExitPlanModeOverlayStateTests: XCTestCase {
    func testDefaultSelectionCanSubmit() {
        let state = ExitPlanModeOverlayState()

        XCTAssertEqual(state.selection, .implement)
        XCTAssertTrue(state.canSubmit)
    }

    func testCustomDenialRequiresText() {
        var state = ExitPlanModeOverlayState(selection: .customDenial)

        XCTAssertFalse(state.canSubmit)
        XCTAssertFalse(state.isHiddenAfterSubmit)

        state.customResponse = "  Explain more first.  "

        XCTAssertTrue(state.canSubmit)
        XCTAssertEqual(state.trimmedCustomResponse, "Explain more first.")
    }

    func testSubmittedCustomDenialSuppressesOverlayAndApprovalComposerStatus() throws {
        let approval = ToolApprovalRequest(
            sessionId: "session-123",
            toolUseId: "exit-plan-1",
            toolName: "ExitPlanMode",
            toolInput: ##"{"plan":"# Plan\n\n- Do the work."}"##
        )
        let pendingApproval = PendingToolApproval(request: approval, status: .denying)

        XCTAssertNotNil(ExitPlanModeOverlayPresentation.composerStatusText(
            pendingApproval: pendingApproval,
            overlayState: nil
        ))
        XCTAssertNotNil(ExitPlanModeOverlayPresentation.activeApproval(
            pendingApproval: pendingApproval,
            hasActiveAskUserQuestionPrompt: false,
            overlayState: nil
        ))

        let hiddenState = ExitPlanModeOverlayState(
            selection: .customDenial,
            customResponse: "Test",
            isSubmitting: true,
            isHiddenAfterSubmit: true
        )

        XCTAssertNil(ExitPlanModeOverlayPresentation.activeApproval(
            pendingApproval: pendingApproval,
            hasActiveAskUserQuestionPrompt: false,
            overlayState: hiddenState
        ))
        XCTAssertNil(ExitPlanModeOverlayPresentation.composerStatusText(
            pendingApproval: pendingApproval,
            overlayState: hiddenState
        ))
        XCTAssertEqual(
            ChatPresentation.composerMode(for: ChatComposerModeState(
                isCancellingInitialSetup: false,
                hasSetupPhase: false,
                isReconfiguringSession: false,
                isAwaitingHandoffSteering: false,
                isHandingOffSession: false,
                isAwaitingExitPlanModeFollowUp: false,
                pendingToolApprovalStatusText: ExitPlanModeOverlayPresentation.composerStatusText(
                    pendingApproval: pendingApproval,
                    overlayState: hiddenState
                ),
                isTurnActive: false,
                runtimeStatus: .neutral,
                isSendingMessage: false
            )),
            .idle
        )
    }

    func testSubmittedImplementationSuppressesOverlayAndApprovalComposerStatus() {
        let approval = ToolApprovalRequest(
            sessionId: "session-123",
            toolUseId: "exit-plan-1",
            toolName: "ExitPlanMode",
            toolInput: ##"{"plan":"# Plan\n\n- Do the work."}"##
        )
        let pendingApproval = PendingToolApproval(request: approval, status: .approving)
        let hiddenState = ExitPlanModeOverlayState(
            selection: .implement,
            isSubmitting: true,
            isHiddenAfterSubmit: true
        )

        XCTAssertNil(ExitPlanModeOverlayPresentation.activeApproval(
            pendingApproval: pendingApproval,
            hasActiveAskUserQuestionPrompt: false,
            overlayState: hiddenState
        ))
        XCTAssertNil(ExitPlanModeOverlayPresentation.composerStatusText(
            pendingApproval: pendingApproval,
            overlayState: hiddenState
        ))
    }

    func testSubmittedCustomDenialAwaitingFollowUpShowsBusyComposer() {
        let approval = ToolApprovalRequest(
            sessionId: "session-123",
            toolUseId: "exit-plan-1",
            toolName: "ExitPlanMode",
            toolInput: ##"{"plan":"# Plan\n\n- Do the work."}"##
        )
        let pendingApproval = PendingToolApproval(request: approval, status: .denying)
        let hiddenState = ExitPlanModeOverlayState(
            selection: .customDenial,
            customResponse: "Test",
            isSubmitting: true,
            isHiddenAfterSubmit: true
        )

        XCTAssertEqual(
            ChatPresentation.composerMode(for: ChatComposerModeState(
                isCancellingInitialSetup: false,
                hasSetupPhase: false,
                isReconfiguringSession: false,
                isAwaitingHandoffSteering: false,
                isHandingOffSession: false,
                isAwaitingExitPlanModeFollowUp: true,
                pendingToolApprovalStatusText: ExitPlanModeOverlayPresentation.composerStatusText(
                    pendingApproval: pendingApproval,
                    overlayState: hiddenState
                ),
                isTurnActive: false,
                runtimeStatus: .neutral,
                isSendingMessage: false
            )),
            .busy(canStop: false)
        )
    }

    func testHiddenExitPlanModeStateDoesNotSuppressOtherApprovalComposerStatus() {
        let approval = ToolApprovalRequest(
            sessionId: "session-123",
            toolUseId: "tool-1",
            toolName: "Bash",
            toolInput: "{}"
        )
        let pendingApproval = PendingToolApproval(request: approval, status: .pending)
        let hiddenState = ExitPlanModeOverlayState(
            selection: .customDenial,
            customResponse: "Test",
            isSubmitting: true,
            isHiddenAfterSubmit: true
        )

        XCTAssertNotNil(ExitPlanModeOverlayPresentation.composerStatusText(
            pendingApproval: pendingApproval,
            overlayState: hiddenState
        ))
        XCTAssertNil(ExitPlanModeOverlayPresentation.activeApproval(
            pendingApproval: pendingApproval,
            hasActiveAskUserQuestionPrompt: false,
            overlayState: hiddenState
        ))
    }
}
