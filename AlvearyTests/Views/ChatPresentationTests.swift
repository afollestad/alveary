import XCTest

@testable import Alveary

@MainActor
final class ChatPresentationTests: XCTestCase {
    func testContentModeResolvesTrustPlaceholderBeforeEmptyThread() {
        XCTAssertEqual(
            ChatContentMode.resolve(
                projectTrustPrompt: nil,
                isProjectTrustBlocked: true,
                hasVisibleChatContent: false
            ),
            .projectTrustPlaceholder
        )
    }

    func testContentModeResolvesTranscriptWhenContentExists() {
        XCTAssertEqual(
            ChatContentMode.resolve(
                projectTrustPrompt: nil,
                isProjectTrustBlocked: false,
                hasVisibleChatContent: true
            ),
            .transcript
        )
        XCTAssertEqual(
            ChatContentMode.resolve(
                projectTrustPrompt: nil,
                isProjectTrustBlocked: false,
                hasVisibleChatContent: false
            ),
            .emptyThread
        )
    }

    func testComposerModePriority() {
        XCTAssertEqual(
            ChatPresentation.composerMode(for: ChatComposerModeState(
                isCancellingInitialSetup: true,
                hasSetupPhase: true,
                isReconfiguringSession: true,
                isAwaitingHandoffSteering: true,
                isHandingOffSession: true,
                pendingToolApprovalStatusText: .genericApproval,
                isTurnActive: true,
                isSendingMessage: true
            )),
            .progressOnly(.cancellingInitialSetup)
        )
        XCTAssertEqual(
            ChatPresentation.composerMode(for: ChatComposerModeState(
                isCancellingInitialSetup: false,
                hasSetupPhase: false,
                isReconfiguringSession: false,
                isAwaitingHandoffSteering: true,
                isHandingOffSession: true,
                pendingToolApprovalStatusText: .genericApproval,
                isTurnActive: true,
                isSendingMessage: true
            )),
            .idle
        )
        XCTAssertEqual(
            ChatPresentation.composerMode(for: ChatComposerModeState(
                isCancellingInitialSetup: false,
                hasSetupPhase: false,
                isReconfiguringSession: false,
                isAwaitingHandoffSteering: false,
                isHandingOffSession: false,
                pendingToolApprovalStatusText: nil,
                isTurnActive: false,
                isSendingMessage: true
            )),
            .busy(canStop: false)
        )
    }

    func testThreadPresentationShowsWorktreePickerBeforeSetup() {
        let project = Project(path: "/tmp/alveary", name: "Alveary", gitRemote: "git@github.com:test/alveary.git")
        let thread = AgentThread(
            name: "Native composer",
            hasCompletedInitialSetup: false,
            permissionMode: "acceptEdits",
            effort: "high",
            model: "opus",
            useWorktree: true,
            project: project
        )

        let presentation = ChatThreadPresentation(thread: thread, providerID: "claude")

        XCTAssertEqual(presentation.selectedModel, "opus")
        XCTAssertEqual(presentation.selectedEffort, "high")
        XCTAssertEqual(presentation.selectedPermissionMode, "acceptEdits")
        XCTAssertTrue(presentation.selectedUseWorktree)
        XCTAssertTrue(presentation.showWorktreePicker)
        XCTAssertNil(presentation.sessionLocationLabel)
        XCTAssertEqual(presentation.contextWindowCacheLookupID, "claude:opus")
    }

    func testThreadPresentationShowsSessionLocationAfterSetup() {
        let project = Project(path: "/tmp/alveary", name: "Alveary", gitRemote: "git@github.com:test/alveary.git")
        let thread = AgentThread(
            name: "Native composer",
            worktreePath: "/tmp/alveary-worktree",
            hasCompletedInitialSetup: true,
            model: nil,
            useWorktree: true,
            project: project
        )

        let presentation = ChatThreadPresentation(thread: thread, providerID: "claude")

        XCTAssertEqual(presentation.selectedModel, AppSettings.defaultModelValue)
        XCTAssertFalse(presentation.showWorktreePicker)
        XCTAssertEqual(presentation.sessionLocationLabel, "Worktree (alveary-worktree)")
        XCTAssertEqual(presentation.contextWindowCacheLookupID, "claude:\(AppSettings.defaultModelValue)")
    }
}
