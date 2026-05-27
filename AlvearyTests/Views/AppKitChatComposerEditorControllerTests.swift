import AppKit
import BlockInputKit
import XCTest

@testable import Alveary

@MainActor
final class AppKitChatComposerEditorControllerTests: XCTestCase {
    func testConfigureClearsPreviousDraftSnapshotProviderBeforeInstallingNext() {
        let controller = AppKitChatComposerEditorController()
        var firstInstalled = false
        var firstCleared = false
        var secondInstalled = false

        controller.configure(makeConfiguration(
            onDraftSnapshotProviderChange: { provider in
                if provider == nil {
                    firstCleared = true
                } else {
                    firstInstalled = true
                }
            }
        ))
        controller.configure(makeConfiguration(
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
        let controller = AppKitChatComposerEditorController()

        controller.configure(makeConfiguration(text: "First", draftIdentity: "one"))
        controller.configure(makeConfiguration(text: "Second", draftIdentity: "two"))

        XCTAssertEqual(controller.bridgeController?.currentMarkdown(), "Second")
    }

    func testBlockInputViewIsHostedDirectlyWithComposerChrome() throws {
        let controller = AppKitChatComposerEditorController()

        controller.configure(makeConfiguration(text: "First"))

        let editor = try XCTUnwrap(controller.view)
        XCTAssertTrue(editor === controller.bridgeController?.view)
        let chrome = try XCTUnwrap(editor.style.editorSurface.chrome)
        XCTAssertEqual(chrome.cornerRadius, AppKitChatComposerEditorController.editorCornerRadius)
        XCTAssertEqual(chrome.borderWidth, AppKitChatComposerEditorController.borderWidth)
        XCTAssertEqual(chrome.clipsContentToShape, true)
    }

    func testQueuedMessagesSquareEditorTopCorners() throws {
        let controller = AppKitChatComposerEditorController()

        controller.configure(makeConfiguration(text: "First", hasQueuedMessages: true))

        let configuration = try XCTUnwrap(controller.bridgeController?.view.style.editorSurface.chrome)
        XCTAssertEqual(configuration.roundedCorners, .bottom)
    }

    func testBlockInputInitialHeightUsesMinimumVisibleLineCountAfterWidthArrives() throws {
        let controller = AppKitChatComposerEditorController()

        controller.configure(makeConfiguration(text: "ss\ns"))
        _ = controller.measuredHeight(width: 400)

        let editor = try XCTUnwrap(controller.view)
        XCTAssertEqual(controller.measuredEditorHeight, editor.preferredHeight(forWidth: 400), accuracy: 0.5)
        XCTAssertGreaterThan(controller.measuredEditorHeight, AppKitChatComposerEditorController.editorBaseHeight)
    }

    func testCompletionPopupOverlayUsesChatSurfaceParentAndEditorFrame() throws {
        let surface = AppKitChatSurfaceView(frame: NSRect(x: 0, y: 0, width: 640, height: 480))
        let panel = AppKitChatComposerPanelView(frame: NSRect(x: 0, y: 320, width: 448, height: 120))
        surface.addSubview(panel)
        panel.configure(AppKitChatComposerPanelConfiguration(
            bodyConfiguration: makeConfiguration(text: "@"),
            showsTopDivider: false,
            layout: AppKitChatComposerPanelView.Layout(
                horizontalPadding: NSEdgeInsets(top: 0, left: 24, bottom: 0, right: 24),
                topContentSpacing: 0,
                actionRowSpacing: 0
            )
        ))
        panel.layoutSubtreeIfNeeded()

        let editor = try XCTUnwrap(panel.subviews.first { $0 is BlockInputView } as? BlockInputView)
        let context = BlockInputCompletionPopupOverlayContext(
            editorView: editor,
            defaultContainer: editor,
            defaultFrame: .zero,
            popupSize: NSSize(width: 260, height: 72)
        )
        let overlay = try XCTUnwrap(panel.editorControllerForTesting.blockInputCompletionPopupOverlay(context: context))
        let editorFrame = context.editorFrame(in: surface)

        XCTAssertTrue(overlay.container === surface)
        XCTAssertEqual(overlay.frame.minX, editorFrame.minX)
        XCTAssertEqual(overlay.frame.maxY, editorFrame.minY - AppKitChatComposerEditorController.autocompleteVerticalOffset)
        XCTAssertEqual(overlay.frame.width, editorFrame.width)
        XCTAssertEqual(overlay.frame.height, 72)
    }

    func testPreferredHeightTransitionAppliesInitialHeightImmediately() {
        let controller = AppKitChatComposerEditorController()
        var invalidationCount = 0
        controller.onPreferredSizeInvalidated = {
            invalidationCount += 1
        }

        controller.handlePreferredHeightTransition(BlockInputEditorHeightTransition(
            previousHeight: nil,
            targetHeight: 91.2,
            animation: .default,
            isInitial: true
        ))

        XCTAssertEqual(controller.measuredEditorHeight, 92)
        XCTAssertEqual(invalidationCount, 1)
    }

    func testPreferredHeightTransitionInterpolatesNonInitialChanges() async throws {
        let controller = AppKitChatComposerEditorController()
        var invalidationCount = 0
        controller.measuredEditorHeight = 80
        controller.onPreferredSizeInvalidated = {
            invalidationCount += 1
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
        XCTAssertGreaterThan(invalidationCount, 1)
    }

    func testPreferredHeightTransitionRelayoutsComposerSurfaceImmediately() throws {
        let surface = AppKitChatSurfaceView(frame: NSRect(x: 0, y: 0, width: 420, height: 320))
        let content = NSView()
        let panel = AppKitChatComposerPanelView()
        panel.configure(AppKitChatComposerPanelConfiguration(
            bodyConfiguration: makeConfiguration(text: "First"),
            showsTopDivider: false,
            layout: AppKitChatComposerPanelView.Layout(
                horizontalPadding: NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0),
                topContentSpacing: 0,
                actionRowSpacing: 0
            )
        ))
        surface.configure(contentView: content, composerView: panel)
        surface.layoutSubtreeIfNeeded()
        let previousPanelHeight = panel.frame.height

        panel.editorControllerForTesting.handlePreferredHeightTransition(BlockInputEditorHeightTransition(
            previousHeight: panel.editorControllerForTesting.measuredEditorHeight,
            targetHeight: panel.editorControllerForTesting.measuredEditorHeight + 40,
            animation: nil,
            isInitial: false
        ))

        XCTAssertGreaterThan(panel.frame.height, previousPanelHeight)
        XCTAssertEqual(content.frame.maxY, panel.frame.minY)
    }

    func testOverlayCompletionProviderDoesNotRetainController() {
        var bridgeConfiguration: BlockInputComposerBridgeConfiguration?
        weak var weakController: AppKitChatComposerEditorController?

        autoreleasepool {
            let controller = AppKitChatComposerEditorController()
            weakController = controller
            bridgeConfiguration = controller.blockInputBridgeConfiguration(for: makeConfiguration(text: "@"))
        }

        XCTAssertNotNil(bridgeConfiguration?.completionPopupOverlayProvider)
        XCTAssertNil(weakController)
    }

    private func makeConfiguration(
        text: String = "First",
        draftIdentity: String = "one",
        hasQueuedMessages: Bool = false,
        hasTopContent: Bool = false,
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
            hasQueuedMessages: hasQueuedMessages,
            hasTopContent: hasTopContent,
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
