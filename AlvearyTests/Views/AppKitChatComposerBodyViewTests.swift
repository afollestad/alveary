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

    func testBlockInputInitialHeightUsesMinimumVisibleLineCountAfterLayout() async throws {
        let body = AppKitChatComposerBodyView(frame: NSRect(x: 0, y: 0, width: 400, height: 180))

        body.configure(makeConfiguration(text: "ss\ns"))
        body.layoutSubtreeIfNeeded()
        body.bridgeController?.view.layoutSubtreeIfNeeded()
        await Task.yield()

        let editor = try XCTUnwrap(body.bridgeController?.view)
        XCTAssertEqual(body.measuredEditorHeight, editor.preferredHeight(forWidth: body.bounds.width), accuracy: 0.5)
        XCTAssertGreaterThan(body.measuredEditorHeight, AppKitChatComposerBodyView.editorBaseHeight)
    }

    func testBlockInputInitialEmptyHeightUsesMinimumVisibleLineCountAfterWidthArrives() throws {
        let body = AppKitChatComposerBodyView(frame: NSRect(x: 0, y: 0, width: 0, height: 180))

        body.configure(makeConfiguration(text: ""))
        body.frame.size.width = 400
        body.layoutSubtreeIfNeeded()

        let editor = try XCTUnwrap(body.bridgeController?.view)
        XCTAssertEqual(body.measuredEditorHeight, editor.preferredHeight(forWidth: body.bounds.width), accuracy: 0.5)
        XCTAssertGreaterThan(body.measuredEditorHeight, AppKitChatComposerBodyView.editorBaseHeight)
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

    func testCompletionPopupOverlayRemainsAlignedAfterHeightResize() throws {
        let surface = AppKitChatSurfaceView(frame: NSRect(x: 0, y: 0, width: 640, height: 480))
        let body = AppKitChatComposerBodyView(frame: NSRect(x: 24, y: 320, width: 400, height: 120))
        surface.addSubview(body)

        body.configure(makeConfiguration(text: "@"))
        body.handlePreferredHeightTransition(BlockInputEditorHeightTransition(
            previousHeight: body.measuredEditorHeight,
            targetHeight: 96,
            animation: nil,
            isInitial: false
        ))
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
    }

    func testPreferredHeightTransitionAppliesInitialHeightImmediately() {
        let body = AppKitChatComposerBodyView(frame: NSRect(x: 0, y: 0, width: 400, height: 180))
        var invalidationCount = 0
        body.onPreferredSizeInvalidated = {
            invalidationCount += 1
        }

        body.handlePreferredHeightTransition(BlockInputEditorHeightTransition(
            previousHeight: nil,
            targetHeight: 91.2,
            animation: .default,
            isInitial: true
        ))

        XCTAssertEqual(body.measuredEditorHeight, 92)
        XCTAssertEqual(invalidationCount, 1)
    }

    func testPreferredHeightTransitionInterpolatesNonInitialChanges() async throws {
        let body = AppKitChatComposerBodyView(frame: NSRect(x: 0, y: 0, width: 400, height: 180))
        var invalidationCount = 0
        body.measuredEditorHeight = 80
        body.onPreferredSizeInvalidated = {
            invalidationCount += 1
        }

        body.handlePreferredHeightTransition(BlockInputEditorHeightTransition(
            previousHeight: 80,
            targetHeight: 120,
            animation: BlockInputEditorHeightAnimation(duration: 0.04, curve: .linear),
            isInitial: false
        ))

        XCTAssertEqual(body.measuredEditorHeight, 80)

        try await Task.sleep(nanoseconds: 80_000_000)

        XCTAssertEqual(body.measuredEditorHeight, 120, accuracy: 0.5)
        XCTAssertGreaterThan(invalidationCount, 1)
    }

    func testPreferredHeightTransitionSkipsAnimationWhenAnimationIsNil() {
        let body = AppKitChatComposerBodyView(frame: NSRect(x: 0, y: 0, width: 400, height: 180))
        var invalidationCount = 0
        body.measuredEditorHeight = 80
        body.onPreferredSizeInvalidated = {
            invalidationCount += 1
        }

        body.handlePreferredHeightTransition(BlockInputEditorHeightTransition(
            previousHeight: 80,
            targetHeight: 120,
            animation: nil,
            isInitial: false
        ))

        XCTAssertEqual(body.measuredEditorHeight, 120)
        XCTAssertEqual(invalidationCount, 1)
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
        let body = try XCTUnwrap(panel.subviews.first { $0 is AppKitChatComposerBodyView } as? AppKitChatComposerBodyView)
        let previousPanelHeight = panel.frame.height

        body.handlePreferredHeightTransition(BlockInputEditorHeightTransition(
            previousHeight: body.measuredEditorHeight,
            targetHeight: body.measuredEditorHeight + 40,
            animation: nil,
            isInitial: false
        ))

        XCTAssertGreaterThan(panel.frame.height, previousPanelHeight)
        XCTAssertEqual(content.frame.maxY, panel.frame.minY)
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
