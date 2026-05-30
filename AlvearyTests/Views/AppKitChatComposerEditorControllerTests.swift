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

    func testQueuedMessagesAttachedEditorRendersSquareTopCorners() throws {
        let panel = AppKitChatComposerPanelView(frame: NSRect(x: 0, y: 0, width: 300, height: 160))
        panel.configure(AppKitChatComposerPanelConfiguration(
            bodyConfiguration: makeConfiguration(text: "First", hasQueuedMessages: true),
            queuedMessagesConfiguration: AppKitChatQueuedMessagesConfiguration(
                queuedMessages: [QueuedMessage(text: "Queued follow-up", stagedContext: nil)],
                supportsMidTurnSteering: true,
                isTurnActive: true,
                inFlightQueuedMessageID: nil,
                borderWidth: 1,
                onSteer: { _ in },
                onEdit: { _ in },
                onDismiss: { _ in }
            ),
            showsTopDivider: false,
            layout: AppKitChatComposerPanelView.Layout(
                horizontalPadding: NSEdgeInsets(top: 0, left: 20, bottom: 0, right: 20),
                topContentSpacing: 8,
                actionRowSpacing: 14
            )
        ))
        panel.layoutSubtreeIfNeeded()

        let editor = try XCTUnwrap(panel.subviews.first { $0 is BlockInputView } as? BlockInputView)
        let samples = try renderedEditorCornerSamples(editor)

        assertFilled(samples.topLeft, "top-left")
        assertFilled(samples.topRight, "top-right")
        assertClipped(samples.bottomLeft, "bottom-left")
        assertClipped(samples.bottomRight, "bottom-right")
    }

    func testBlockInputInitialHeightUsesMinimumVisibleLineCountAfterWidthArrives() throws {
        let controller = AppKitChatComposerEditorController()

        controller.configure(makeConfiguration(text: "ss\ns"))
        _ = controller.measuredHeight(width: 400)

        let editor = try XCTUnwrap(controller.view)
        XCTAssertEqual(controller.measuredEditorHeight, editor.preferredHeight(forWidth: 400), accuracy: 0.5)
        XCTAssertGreaterThan(controller.measuredEditorHeight, AppKitChatComposerEditorController.editorBaseHeight)
    }

    func testFocusRequestAfterClearRevisionConsumesToken() throws {
        let controller = AppKitChatComposerEditorController()
        var consumedToken: UUID?
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 160),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )

        controller.configure(makeConfiguration(text: "Before", inputDraftRevision: 0))
        let editor = try XCTUnwrap(controller.view)
        editor.frame = NSRect(x: 0, y: 0, width: 480, height: 160)
        window.contentView = NSView(frame: NSRect(x: 0, y: 0, width: 480, height: 160))
        window.contentView?.addSubview(editor)

        let token = UUID()
        controller.configure(makeConfiguration(
            text: "",
            inputDraftRevision: 1,
            requestFirstResponder: token,
            onFocusRequestConsumed: { consumedToken = $0 }
        ))

        XCTAssertEqual(controller.bridgeController?.currentMarkdown(), "")
        XCTAssertEqual(consumedToken, token)
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

    func testModalOverlayUsesChatSurfaceParentAndContextFrame() throws {
        let surface = AppKitChatSurfaceView(frame: NSRect(x: 0, y: 0, width: 640, height: 480))
        let panel = AppKitChatComposerPanelView(frame: NSRect(x: 0, y: 320, width: 448, height: 120))
        surface.addSubview(panel)
        panel.configure(AppKitChatComposerPanelConfiguration(
            bodyConfiguration: makeConfiguration(text: "Link"),
            showsTopDivider: false,
            layout: AppKitChatComposerPanelView.Layout(
                horizontalPadding: NSEdgeInsets(top: 0, left: 24, bottom: 0, right: 24),
                topContentSpacing: 0,
                actionRowSpacing: 0
            )
        ))
        panel.layoutSubtreeIfNeeded()

        let editor = try XCTUnwrap(panel.subviews.first { $0 is BlockInputView } as? BlockInputView)
        let anchorWindowRect = surface.convert(NSRect(x: 560, y: 440, width: 72, height: 22), to: nil)
        let context = BlockInputModalOverlayContext(
            editorView: editor,
            kind: .link,
            defaultContainer: editor,
            defaultFrame: .zero,
            modalSize: NSSize(width: 300, height: 148),
            anchorWindowRect: anchorWindowRect
        )
        let overlay = try XCTUnwrap(panel.editorControllerForTesting.blockInputModalOverlay(context: context))
        let expectedFrame = context.modalFrame(
            in: surface,
            horizontalOffset: AppKitChatComposerEditorController.modalHorizontalOffset,
            verticalSpacing: AppKitChatComposerEditorController.modalVerticalSpacing
        )

        XCTAssertTrue(overlay.container === surface)
        XCTAssertEqual(overlay.frame, expectedFrame)
        XCTAssertGreaterThanOrEqual(overlay.frame.minX, surface.bounds.minX + 12)
        XCTAssertLessThanOrEqual(overlay.frame.maxX, surface.bounds.maxX - 12)
        XCTAssertGreaterThanOrEqual(overlay.frame.minY, surface.bounds.minY + 12)
        XCTAssertLessThanOrEqual(overlay.frame.maxY, surface.bounds.maxY - 12)

        let upperLeftContext = BlockInputModalOverlayContext(
            editorView: editor,
            kind: .link,
            defaultContainer: editor,
            defaultFrame: .zero,
            modalSize: NSSize(width: 300, height: 148),
            anchorWindowRect: surface.convert(NSRect(x: 0, y: 0, width: 72, height: 22), to: nil)
        )
        let upperLeftOverlay = try XCTUnwrap(panel.editorControllerForTesting.blockInputModalOverlay(context: upperLeftContext))
        XCTAssertGreaterThanOrEqual(upperLeftOverlay.frame.minX, surface.bounds.minX + 12)
        XCTAssertGreaterThanOrEqual(upperLeftOverlay.frame.minY, surface.bounds.minY + 12)
    }

    func testModalOverlayOffsetsUpAndRightWhenSpaceAllows() throws {
        let surface = AppKitChatSurfaceView(frame: NSRect(x: 0, y: 0, width: 640, height: 480))
        let panel = AppKitChatComposerPanelView(frame: NSRect(x: 0, y: 320, width: 448, height: 120))
        surface.addSubview(panel)
        panel.configure(AppKitChatComposerPanelConfiguration(
            bodyConfiguration: makeConfiguration(text: "Link"),
            showsTopDivider: false,
            layout: AppKitChatComposerPanelView.Layout(
                horizontalPadding: NSEdgeInsets(top: 0, left: 24, bottom: 0, right: 24),
                topContentSpacing: 0,
                actionRowSpacing: 0
            )
        ))
        panel.layoutSubtreeIfNeeded()

        let editor = try XCTUnwrap(panel.subviews.first { $0 is BlockInputView } as? BlockInputView)
        let anchorWindowRect = surface.convert(NSRect(x: 220, y: 440, width: 72, height: 22), to: nil)
        let context = BlockInputModalOverlayContext(
            editorView: editor,
            kind: .link,
            defaultContainer: editor,
            defaultFrame: .zero,
            modalSize: NSSize(width: 300, height: 148),
            anchorWindowRect: anchorWindowRect
        )
        let overlay = try XCTUnwrap(panel.editorControllerForTesting.blockInputModalOverlay(context: context))
        let defaultFrame = context.modalFrame(in: surface)

        XCTAssertGreaterThan(overlay.frame.minX, defaultFrame.minX)
        XCTAssertLessThan(overlay.frame.minY, defaultFrame.minY)
        XCTAssertGreaterThanOrEqual(overlay.frame.minX, surface.bounds.minX + 12)
        XCTAssertLessThanOrEqual(overlay.frame.maxX, surface.bounds.maxX - 12)
        XCTAssertGreaterThanOrEqual(overlay.frame.minY, surface.bounds.minY + 12)
        XCTAssertLessThanOrEqual(overlay.frame.maxY, surface.bounds.maxY - 12)
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

    func testKeyboardShortcutsUseLatestConfigurationAfterReconfigure() {
        let controller = AppKitChatComposerEditorController()
        var submitCount = 0
        controller.configure(makeConfiguration(
            text: "First",
            mode: .idle,
            onSubmit: { submitCount += 1 }
        ))
        let shortcuts = controller.blockInputKeyboardShortcuts()

        controller.configure(makeConfiguration(
            text: "First",
            mode: .progressOnly(.initialSetup),
            onSubmit: { submitCount += 1 }
        ))
        let result = shortcuts[.returnKey]?(BlockInputKeyboardShortcutContext(
            shortcut: .returnKey,
            selection: nil,
            activeBlock: nil,
            focusSource: .blockText,
            isRepeat: false
        ))

        XCTAssertEqual(result, .handled)
        XCTAssertEqual(submitCount, 0)
    }

    private func makeConfiguration(
        text: String = "First",
        draftIdentity: String = "one",
        inputDraftRevision: Int = 0,
        mode: ComposerMode = .idle,
        hasQueuedMessages: Bool = false,
        hasTopContent: Bool = false,
        requestFirstResponder: UUID? = nil,
        onDraftSnapshotProviderChange: @escaping (ComposerDraftSnapshotProvider?) -> Void = { _ in },
        onSubmit: @escaping () -> Void = {},
        onFocusRequestConsumed: @escaping (UUID?) -> Void = { _ in }
    ) -> AppKitChatComposerBodyConfiguration {
        AppKitChatComposerBodyConfiguration(
            text: text,
            draftIdentity: draftIdentity,
            inputDraftRevision: inputDraftRevision,
            mode: mode,
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
            requestFirstResponder: requestFirstResponder,
            loadFileCompletions: { [] },
            loadSkillCompletions: { [] },
            onDraftSnapshotProviderChange: onDraftSnapshotProviderChange,
            onSubmit: onSubmit,
            onSteer: {},
            onStop: {},
            onStopConfirmationChange: { _ in },
            onFocusRequestConsumed: onFocusRequestConsumed
        )
    }
}

private struct EditorCornerSamples {
    let topLeft: NSColor
    let topRight: NSColor
    let bottomLeft: NSColor
    let bottomRight: NSColor
}

@MainActor
private func renderedEditorCornerSamples(
    _ editor: BlockInputView,
    file: StaticString = #filePath,
    line: UInt = #line
) throws -> EditorCornerSamples {
    editor.displayIfNeeded()
    editor.layoutSubtreeIfNeeded()
    editor.updateLayer()
    editor.layer?.layoutIfNeeded()

    let size = editor.bounds.size
    let bitmap = try XCTUnwrap(
        NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(size.width),
            pixelsHigh: Int(size.height),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ),
        file: file,
        line: line
    )
    bitmap.size = size
    let context = try XCTUnwrap(NSGraphicsContext(bitmapImageRep: bitmap), file: file, line: line)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    editor.layer?.render(in: context.cgContext)
    NSGraphicsContext.restoreGraphicsState()

    return EditorCornerSamples(
        topLeft: try XCTUnwrap(bitmap.colorAt(x: 2, y: 2), file: file, line: line),
        topRight: try XCTUnwrap(bitmap.colorAt(x: Int(size.width) - 3, y: 2), file: file, line: line),
        bottomLeft: try XCTUnwrap(bitmap.colorAt(x: 2, y: Int(size.height) - 3), file: file, line: line),
        bottomRight: try XCTUnwrap(bitmap.colorAt(x: Int(size.width) - 3, y: Int(size.height) - 3), file: file, line: line)
    )
}

private func assertFilled(
    _ color: NSColor,
    _ corner: String,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    let resolved = color.usingColorSpace(.deviceRGB) ?? color
    XCTAssertGreaterThan(
        resolved.alphaComponent,
        0.02,
        "Expected \(corner) to be filled for attached queued composer, got alpha \(resolved.alphaComponent)",
        file: file,
        line: line
    )
}

private func assertClipped(
    _ color: NSColor,
    _ corner: String,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    let resolved = color.usingColorSpace(.deviceRGB) ?? color
    XCTAssertLessThan(
        resolved.alphaComponent,
        0.01,
        "Expected \(corner) to be clipped for attached queued composer, got alpha \(resolved.alphaComponent)",
        file: file,
        line: line
    )
}
