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

        let editor = try XCTUnwrap(panel.editorControllerForTesting.view)
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

        let editor = try XCTUnwrap(panel.editorControllerForTesting.view)
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

    func testAttachmentStripSitsAboveEditorAndDropOverlayCoversStripAndEditor() throws {
        let panel = AppKitChatComposerPanelView(frame: NSRect(x: 0, y: 0, width: 420, height: 260))
        let attachment = LocalFileAttachment(
            id: "report",
            fileURL: FileManager.default.temporaryDirectory.appendingPathComponent("report.pdf"),
            label: "report.pdf",
            createdAt: Date(timeIntervalSince1970: 0)
        )

        panel.configure(AppKitChatComposerPanelConfiguration(
            bodyConfiguration: makeHeightTestComposerBodyConfiguration(attachments: [.file(attachment)]),
            actionRowConfiguration: makeActionRowConfiguration(),
            showsTopDivider: false,
            layout: AppKitChatComposerPanelView.Layout(
                horizontalPadding: NSEdgeInsetsZero,
                topContentSpacing: 0,
                actionRowSpacing: 14,
                bottomPadding: 16
            )
        ))
        panel.layoutSubtreeIfNeeded()

        let editor = try XCTUnwrap(panel.editorControllerForTesting.view)
        let strip = panel.attachmentStripViewForTesting
        let expectedDropFrame = strip.frame.union(editor.frame)
        XCTAssertFalse(strip.isHidden)
        XCTAssertEqual(strip.frame.maxY, editor.frame.minY, accuracy: 0.5)
        XCTAssertEqual(panel.fileDropOverlayViewForTesting.frame, expectedDropFrame)
    }

    func testAttachmentStripRenderedBackgroundMatchesEditorSurface() throws {
        let panel = AppKitChatComposerPanelView(frame: NSRect(x: 0, y: 0, width: 420, height: 180))
        panel.appearance = try XCTUnwrap(NSAppearance(named: .darkAqua))
        let attachment = LocalFileAttachment(
            id: "report",
            fileURL: FileManager.default.temporaryDirectory.appendingPathComponent("report.pdf"),
            label: "report.pdf",
            createdAt: Date(timeIntervalSince1970: 0)
        )

        panel.configure(AppKitChatComposerPanelConfiguration(
            bodyConfiguration: makeHeightTestComposerBodyConfiguration(attachments: [.file(attachment)]),
            showsTopDivider: false,
            layout: AppKitChatComposerPanelView.Layout(
                horizontalPadding: NSEdgeInsetsZero,
                topContentSpacing: 0,
                actionRowSpacing: 14,
                bottomPadding: 0
            )
        ))
        panel.layoutSubtreeIfNeeded()

        let editor = try XCTUnwrap(panel.editorControllerForTesting.view)
        let strip = panel.attachmentStripViewForTesting
        let bitmap = try renderedComposerPanelBitmap(panel)
        let stripColor = try composerPanelColor(
            at: NSPoint(x: strip.frame.maxX - 24, y: strip.frame.midY),
            in: bitmap
        )
        let editorColor = try composerPanelColor(
            at: NSPoint(x: editor.frame.maxX - 24, y: editor.frame.midY),
            in: bitmap
        )

        assertMatchingRGBColors(stripColor, editorColor, accuracy: 0.01)
        assertMatchingRGBColors(
            stripColor,
            NSColor(deviceRed: 30.0 / 255.0, green: 30.0 / 255.0, blue: 30.0 / 255.0, alpha: 1),
            accuracy: 0.01
        )
    }

    func testChatSurfaceRegistersAsLightweightFileDragDestination() {
        let surface = AppKitChatSurfaceView(frame: NSRect(x: 0, y: 0, width: 420, height: 320))

        XCTAssertEqual(Set(surface.registeredDraggedTypes), [.fileURL])
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

private func makeHeightTestComposerBodyConfiguration(
    hasQueuedMessages: Bool = false,
    attachments: [ComposerAttachment] = []
) -> AppKitChatComposerBodyConfiguration {
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
        attachments: attachments,
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

@MainActor
private func renderedComposerPanelBitmap(
    _ panel: AppKitChatComposerPanelView,
    file: StaticString = #filePath,
    line: UInt = #line
) throws -> NSBitmapImageRep {
    panel.displayIfNeeded()
    panel.layoutSubtreeIfNeeded()

    let size = panel.bounds.size
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
    NSColor(calibratedWhite: 0.10, alpha: 1).setFill()
    NSRect(origin: .zero, size: size).fill()
    NSGraphicsContext.restoreGraphicsState()
    panel.cacheDisplay(in: panel.bounds, to: bitmap)
    return bitmap
}

private func composerPanelColor(
    at point: NSPoint,
    in bitmap: NSBitmapImageRep,
    file: StaticString = #filePath,
    line: UInt = #line
) throws -> NSColor {
    let pixelX = min(max(Int(point.x.rounded()), 0), bitmap.pixelsWide - 1)
    let pixelY = min(max(Int(point.y.rounded()), 0), bitmap.pixelsHigh - 1)
    return try XCTUnwrap(bitmap.colorAt(x: pixelX, y: pixelY)?.usingColorSpace(.deviceRGB), file: file, line: line)
}

private func assertMatchingRGBColors(
    _ first: NSColor,
    _ second: NSColor,
    accuracy: CGFloat,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    let first = first.usingColorSpace(.deviceRGB) ?? first
    let second = second.usingColorSpace(.deviceRGB) ?? second
    XCTAssertEqual(first.redComponent, second.redComponent, accuracy: accuracy, file: file, line: line)
    XCTAssertEqual(first.greenComponent, second.greenComponent, accuracy: accuracy, file: file, line: line)
    XCTAssertEqual(first.blueComponent, second.blueComponent, accuracy: accuracy, file: file, line: line)
    XCTAssertEqual(first.alphaComponent, second.alphaComponent, accuracy: accuracy, file: file, line: line)
}
