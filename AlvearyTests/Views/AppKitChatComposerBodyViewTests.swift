import AppKit
import BlockInputKit
import QuartzCore
import XCTest

@testable import Alveary

@MainActor
final class AppKitChatComposerBodyViewTests: XCTestCase {
    func testConfigureClearsPreviousDraftSnapshotProviderBeforeInstallingNext() {
        let body = AppKitChatComposerBodyView(frame: NSRect(x: 0, y: 0, width: 400, height: 180))
        var firstInstalled = false
        var firstCleared = false
        var secondInstalled = false

        body.configure(makeConfiguration(
            onDraftSnapshotProviderChange: { provider in
                if provider == nil {
                    firstCleared = true
                } else {
                    firstInstalled = true
                }
            }
        ))
        body.configure(makeConfiguration(
            text: "Second",
            onDraftSnapshotProviderChange: { provider in
                if provider != nil {
                    secondInstalled = true
                }
            }
        ))

        XCTAssertTrue(firstInstalled)
        XCTAssertTrue(firstCleared)
        XCTAssertTrue(secondInstalled)
    }

    func testConfigureResetsBridgeWhenDraftIdentityChanges() {
        let body = AppKitChatComposerBodyView(frame: NSRect(x: 0, y: 0, width: 400, height: 180))

        body.configure(makeConfiguration(text: "First", draftIdentity: "one"))
        body.configure(makeConfiguration(text: "Second", draftIdentity: "two"))

        XCTAssertEqual(body.bridgeController?.currentMarkdown(), "Second")
    }

    func testBlockInputViewIsClippedToRoundedEditorShape() throws {
        let body = AppKitChatComposerBodyView(frame: NSRect(x: 0, y: 0, width: 400, height: 180))

        body.configure(makeConfiguration(text: "First"))
        body.layoutSubtreeIfNeeded()

        let bridgeView = try XCTUnwrap(body.bridgeController?.view)
        XCTAssertTrue(body.subviews.contains(body.editorClipView))
        XCTAssertTrue(body.editorClipView.subviews.contains { $0 === bridgeView })
        XCTAssertEqual(body.editorClipView.frame.minX, 0)
        XCTAssertEqual(bridgeView.frame.minX, 0)
        XCTAssertEqual(bridgeView.frame.width, body.editorClipView.frame.width)
        XCTAssertNotNil((body.editorClipView.layer?.mask as? CAShapeLayer)?.path)
    }

    func testCompletionPopupOverlayUsesChatSurfaceParentAndOldComposerFrame() throws {
        let surface = AppKitChatSurfaceView(frame: NSRect(x: 0, y: 0, width: 640, height: 480))
        let body = AppKitChatComposerBodyView(frame: NSRect(x: 24, y: 320, width: 400, height: 120))
        surface.addSubview(body)

        body.configure(makeConfiguration(text: "@"))
        body.layoutSubtreeIfNeeded()

        let bridgeView = try XCTUnwrap(body.bridgeController?.view)
        let context = BlockInputCompletionPopupOverlayContext(
            editorView: bridgeView,
            defaultContainer: bridgeView,
            defaultFrame: .zero,
            popupSize: NSSize(width: 260, height: 72)
        )
        let overlay = try XCTUnwrap(body.blockInputCompletionPopupOverlay(context: context))
        let editorFrame = context.editorFrame(in: surface)

        XCTAssertTrue(overlay.container === surface)
        XCTAssertEqual(overlay.frame.minX, editorFrame.minX)
        XCTAssertEqual(overlay.frame.maxY, editorFrame.minY - AppKitChatComposerBodyView.autocompleteVerticalOffset)
        XCTAssertEqual(overlay.frame.width, editorFrame.width)
        XCTAssertEqual(overlay.frame.height, 72)
    }

    func testOverlayCompletionProviderDoesNotRetainBodyView() {
        var bridgeConfiguration: BlockInputComposerBridgeConfiguration?
        weak var weakBody: AppKitChatComposerBodyView?

        autoreleasepool {
            let body = AppKitChatComposerBodyView(frame: NSRect(x: 0, y: 0, width: 400, height: 180))
            weakBody = body
            bridgeConfiguration = body.blockInputBridgeConfiguration(for: makeConfiguration(text: "@"))
        }

        XCTAssertNotNil(bridgeConfiguration?.completionPopupOverlayProvider)
        XCTAssertNil(weakBody)
    }

    private func makeConfiguration(
        text: String = "First",
        draftIdentity: String = "one",
        onDraftSnapshotProviderChange: @escaping (ComposerDraftSnapshotProvider?) -> Void = { _ in }
    ) -> AppKitChatComposerBodyConfiguration {
        AppKitChatComposerBodyConfiguration(
            text: text,
            draftIdentity: draftIdentity,
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
            onDraftSnapshotProviderChange: onDraftSnapshotProviderChange,
            onSubmit: {},
            onSteer: {},
            onStop: {},
            onStopConfirmationChange: { _ in },
            onFocusRequestConsumed: { _ in }
        )
    }
}
