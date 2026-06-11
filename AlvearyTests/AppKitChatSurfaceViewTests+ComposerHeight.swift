@preconcurrency import AppKit
import BlockInputKit
import XCTest

@testable import Alveary

@MainActor
extension AppKitChatSurfaceViewTests {
    func testPreferredComposerHeightChangeShrinksComposerImmediatelyWhenRequested() {
        let surface = AppKitChatSurfaceView(frame: NSRect(x: 0, y: 0, width: 300, height: 220))
        let content = SurfaceLayoutCountingView(height: 80)
        let composer = SurfaceMutableHeightView(height: 100)
        surface.configure(contentView: content, composerView: composer)
        surface.layoutSubtreeIfNeeded()

        composer.height = 44
        surface.layoutPreferredComposerHeightChange(animated: false)

        XCTAssertEqual(content.frame, NSRect(x: 0, y: 0, width: 300, height: 176))
        XCTAssertEqual(composer.frame, NSRect(x: 0, y: 176, width: 300, height: 44))
        XCTAssertGreaterThan(content.layoutCount, 0)
    }

    func testPreferredComposerHeightChangeRestoresComposerImmediatelyWhenAnimationIsDisabledForTesting() {
        let surface = AppKitChatSurfaceView(frame: NSRect(x: 0, y: 0, width: 300, height: 220))
        surface.heightAnimationEnabledForTesting = false
        let content = SurfaceFixedHeightView(height: 80)
        let composer = SurfaceMutableHeightView(height: 44)
        surface.configure(contentView: content, composerView: composer)
        surface.layoutSubtreeIfNeeded()

        composer.height = 100
        surface.layoutPreferredComposerHeightChange()

        XCTAssertEqual(content.frame, NSRect(x: 0, y: 0, width: 300, height: 120))
        XCTAssertEqual(composer.frame, NSRect(x: 0, y: 120, width: 300, height: 100))
    }

    func testEditorPreferredHeightChangeKeepsComposerControlsBottomPinnedWhenSurfaceAnimationIsAvailable() async throws {
        let surface = AppKitChatSurfaceView(frame: NSRect(x: 0, y: 0, width: 420, height: 320))
        surface.heightAnimationEnabledForTesting = true
        let window = NSWindow(contentRect: surface.frame, styleMask: .borderless, backing: .buffered, defer: false)
        let content = NSView()
        let panel = AppKitChatComposerPanelView()
        panel.configure(AppKitChatComposerPanelConfiguration(
            bodyConfiguration: makeHeightTestComposerBodyConfiguration(),
            actionRowConfiguration: makeActionRowConfiguration(),
            showsTopDivider: false,
            layout: AppKitChatComposerPanelView.Layout(
                horizontalPadding: NSEdgeInsetsZero,
                topContentSpacing: 0,
                actionRowSpacing: 14,
                bottomPadding: 16
            )
        ))
        window.contentView = surface
        surface.configure(contentView: content, composerView: panel)
        surface.layoutSubtreeIfNeeded()

        let editor = try XCTUnwrap(heightTestViews(in: panel, ofType: BlockInputView.self).first)
        let actionRow = try XCTUnwrap(panel.subviews.first { $0 is ChatComposerActionRowView })
        let initialMetrics = PinnedComposerMetrics(
            editorBottom: surfaceBottomY(of: editor, in: surface),
            actionRowBottom: surfaceBottomY(of: actionRow, in: surface)
        )

        panel.editorControllerForTesting.handlePreferredHeightTransition(BlockInputEditorHeightTransition(
            previousHeight: panel.editorControllerForTesting.measuredEditorHeight,
            targetHeight: panel.editorControllerForTesting.measuredEditorHeight + 40,
            animation: nil,
            isInitial: false
        ))

        assertEditorHeightChangePinned(
            surface: surface,
            panel: panel,
            editor: editor,
            actionRow: actionRow,
            initialMetrics: initialMetrics
        )

        try await Task.sleep(nanoseconds: 30_000_000)

        assertEditorHeightChangePinned(
            surface: surface,
            panel: panel,
            editor: editor,
            actionRow: actionRow,
            initialMetrics: initialMetrics
        )
    }

    func testQueuedMessagesAboveComposerKeepEditorAndActionRowBottomPinnedWhenSurfaceAnimationIsAvailable() async throws {
        let surface = AppKitChatSurfaceView(frame: NSRect(x: 0, y: 0, width: 420, height: 320))
        surface.heightAnimationEnabledForTesting = true
        let window = NSWindow(contentRect: surface.frame, styleMask: .borderless, backing: .buffered, defer: false)
        let content = NSView()
        let panel = AppKitChatComposerPanelView()
        let layout = AppKitChatComposerPanelView.Layout(
            horizontalPadding: NSEdgeInsetsZero,
            topContentSpacing: 0,
            actionRowSpacing: 14,
            bottomPadding: 16
        )
        panel.configure(AppKitChatComposerPanelConfiguration(
            bodyConfiguration: makeHeightTestComposerBodyConfiguration(),
            actionRowConfiguration: makeActionRowConfiguration(),
            showsTopDivider: false,
            layout: layout
        ))
        window.contentView = surface
        surface.configure(contentView: content, composerView: panel)
        surface.layoutSubtreeIfNeeded()

        let editor = try XCTUnwrap(heightTestViews(in: panel, ofType: BlockInputView.self).first)
        let actionRow = try XCTUnwrap(panel.subviews.first { $0 is ChatComposerActionRowView })
        let initialMetrics = PinnedComposerMetrics(
            editorBottom: surfaceBottomY(of: editor, in: surface),
            actionRowBottom: surfaceBottomY(of: actionRow, in: surface)
        )

        panel.configure(AppKitChatComposerPanelConfiguration(
            bodyConfiguration: makeHeightTestComposerBodyConfiguration(hasQueuedMessages: true),
            queuedMessagesConfiguration: makeHeightTestQueuedMessagesConfiguration([
                QueuedMessage(text: "Queued follow-up", stagedContext: nil)
            ]),
            actionRowConfiguration: makeActionRowConfiguration(),
            showsTopDivider: false,
            layout: layout
        ))

        assertEditorHeightChangePinned(
            surface: surface,
            panel: panel,
            editor: editor,
            actionRow: actionRow,
            initialMetrics: initialMetrics
        )

        try await Task.sleep(nanoseconds: 30_000_000)

        assertEditorHeightChangePinned(
            surface: surface,
            panel: panel,
            editor: editor,
            actionRow: actionRow,
            initialMetrics: initialMetrics
        )
    }
}

private struct PinnedComposerMetrics {
    let editorBottom: CGFloat
    let actionRowBottom: CGFloat
}

@MainActor
private func assertEditorHeightChangePinned(
    surface: AppKitChatSurfaceView,
    panel: AppKitChatComposerPanelView,
    editor: BlockInputView,
    actionRow: NSView,
    initialMetrics: PinnedComposerMetrics,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    surface.layoutSubtreeIfNeeded()
    XCTAssertEqual(panel.frame.maxY, surface.bounds.maxY, accuracy: 0.5, file: file, line: line)
    XCTAssertEqual(panel.frame.height, panel.fittingSize.height, accuracy: 0.5, file: file, line: line)
    XCTAssertEqual(surfaceBottomY(of: editor, in: surface), initialMetrics.editorBottom, accuracy: 0.5, file: file, line: line)
    XCTAssertEqual(surfaceBottomY(of: actionRow, in: surface), initialMetrics.actionRowBottom, accuracy: 0.5, file: file, line: line)
}

@MainActor
private func surfaceBottomY(of view: NSView, in surface: NSView) -> CGFloat {
    guard let superview = view.superview else {
        return .nan
    }
    return surface.convert(view.frame, from: superview).maxY
}

private func makeHeightTestComposerBodyConfiguration(hasQueuedMessages: Bool = false) -> AppKitChatComposerBodyConfiguration {
    AppKitChatComposerBodyConfiguration(
        text: "Panel body",
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

@MainActor
private func makeHeightTestQueuedMessagesConfiguration(_ messages: [QueuedMessage]) -> AppKitChatQueuedMessagesConfiguration {
    AppKitChatQueuedMessagesConfiguration(
        queuedMessages: messages,
        supportsMidTurnSteering: true,
        isTurnActive: true,
        inFlightQueuedMessageID: nil,
        borderWidth: 1,
        onSteer: { _ in },
        onEdit: { _ in },
        onDismiss: { _ in }
    )
}

@MainActor
private func heightTestViews<T: NSView>(in view: NSView, ofType type: T.Type) -> [T] {
    var matches = view.subviews.compactMap { $0 as? T }
    for subview in view.subviews {
        matches.append(contentsOf: heightTestViews(in: subview, ofType: type))
    }
    return matches
}

private final class SurfaceFixedHeightView: NSView {
    private let fixedHeight: CGFloat

    init(height: CGFloat) {
        fixedHeight = height
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { nil }
    override var intrinsicContentSize: NSSize { NSSize(width: NSView.noIntrinsicMetric, height: fixedHeight) }
    override var fittingSize: NSSize { NSSize(width: NSView.noIntrinsicMetric, height: fixedHeight) }
}

private final class SurfaceMutableHeightView: NSView {
    var height: CGFloat {
        didSet {
            invalidateIntrinsicContentSize()
        }
    }

    init(height: CGFloat) {
        self.height = height
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { nil }
    override var intrinsicContentSize: NSSize { NSSize(width: NSView.noIntrinsicMetric, height: height) }
    override var fittingSize: NSSize { NSSize(width: NSView.noIntrinsicMetric, height: height) }
}

private final class SurfaceLayoutCountingView: NSView {
    private let fixedHeight: CGFloat
    private(set) var layoutCount = 0

    init(height: CGFloat) {
        fixedHeight = height
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { nil }
    override var intrinsicContentSize: NSSize { NSSize(width: NSView.noIntrinsicMetric, height: fixedHeight) }
    override var fittingSize: NSSize { NSSize(width: NSView.noIntrinsicMetric, height: fixedHeight) }

    override func layout() {
        super.layout()
        layoutCount += 1
    }
}
