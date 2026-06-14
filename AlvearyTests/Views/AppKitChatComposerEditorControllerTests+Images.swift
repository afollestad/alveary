import AppKit
import BlockInputKit
import XCTest

@testable import Alveary

@MainActor
extension AppKitChatComposerEditorControllerTests {
    func testBridgeConfigurationUsesTextualImagePresentationAndProductionInsets() {
        let controller = AppKitChatComposerEditorController()
        let bridgeConfiguration = controller.blockInputBridgeConfiguration(for: makeImageConfiguration(
            text: "Before ![Cat](cat.png) after"
        ))
        let bridgeController = BlockInputComposerBridgeController(configuration: bridgeConfiguration)
        let blockInputConfiguration = bridgeController.blockInputConfiguration(for: bridgeConfiguration)

        XCTAssertEqual(bridgeConfiguration.imagePresentation, .textLinksWithPreviewStrip)
        XCTAssertFalse(bridgeController.documentStore.document.containsImageBlock)
        XCTAssertEqual(blockInputConfiguration.imagePresentation, .textLinksWithPreviewStrip)
        XCTAssertEqual(blockInputConfiguration.editorHorizontalInset, AppKitChatComposerEditorController.editorHorizontalPadding)
        XCTAssertEqual(blockInputConfiguration.editorVerticalInset, 10)
    }

    func testFirstTextualImagePreviewHeightRevealAppliesImmediately() throws {
        let controller = AppKitChatComposerEditorController()
        controller.configure(makeImageConfiguration(text: "Ask"))
        controller.measuredEditorHeight = 80
        var invalidationAnimationFlags: [Bool] = []
        controller.onPreferredSizeInvalidated = { animateSurfaceHeight in
            invalidationAnimationFlags.append(animateSurfaceHeight)
        }
        let bridgeController = try XCTUnwrap(controller.bridgeController)
        bridgeController.documentStore.replaceDocument(BlockInputDocument(
            markdown: "Ask ![Cat](cat.png) ",
            imageParsingMode: .preserveSourceText
        ))

        controller.handlePreferredHeightTransition(BlockInputEditorHeightTransition(
            previousHeight: 80,
            targetHeight: 164,
            animation: BlockInputEditorHeightAnimation(duration: 1, curve: .linear),
            isInitial: false
        ))

        XCTAssertEqual(controller.measuredEditorHeight, 164)
        XCTAssertEqual(invalidationAnimationFlags, [false])
    }

    func testExistingTextualImagePreviewHeightChangesStillInterpolate() async throws {
        let controller = AppKitChatComposerEditorController()
        controller.configure(makeImageConfiguration(text: "![Cat](cat.png) "))
        controller.measuredEditorHeight = 80
        var invalidationAnimationFlags: [Bool] = []
        controller.onPreferredSizeInvalidated = { animateSurfaceHeight in
            invalidationAnimationFlags.append(animateSurfaceHeight)
        }

        controller.handlePreferredHeightTransition(BlockInputEditorHeightTransition(
            previousHeight: 80,
            targetHeight: 120,
            animation: BlockInputEditorHeightAnimation(duration: 0.04, curve: .linear),
            isInitial: false
        ))

        XCTAssertEqual(controller.measuredEditorHeight, 80)

        try await Task.sleep(nanoseconds: 80_000_000)

        XCTAssertEqual(controller.measuredEditorHeight, 120, accuracy: 0.5)
        XCTAssertFalse(invalidationAnimationFlags.isEmpty)
        XCTAssertTrue(invalidationAnimationFlags.allSatisfy { !$0 })
    }

    private func makeImageConfiguration(text: String) -> AppKitChatComposerBodyConfiguration {
        AppKitChatComposerBodyConfiguration(
            text: text,
            draftIdentity: "one",
            inputDraftRevision: 0,
            mode: .idle,
            defaultEnterBehavior: .queue,
            isStopConfirmationArmed: false,
            supportsMidTurnSteering: true,
            isProjectTrustBlocked: false,
            isHandoffSteeringPromptActive: false,
            isHandoffOutputPromptActive: false,
            handoffSteeringCountdown: nil,
            sendCountdown: nil,
            hasQueuedMessages: false,
            hasTopContent: false,
            workingDirectory: "/tmp/alveary",
            requestFirstResponder: nil,
            loadFileCompletions: { [] },
            loadSkillCompletions: { [] },
            onSubmit: {},
            onSteer: {},
            onStop: {},
            onStopConfirmationChange: { _ in },
            onFocusRequestConsumed: { _ in }
        )
    }
}

private extension BlockInputDocument {
    var containsImageBlock: Bool {
        blocks.contains { block in
            if case .image = block.kind {
                return true
            }
            return false
        }
    }
}
