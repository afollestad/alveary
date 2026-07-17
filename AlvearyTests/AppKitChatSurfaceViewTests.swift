@preconcurrency import AppKit
import BlockInputKit
import SwiftUI
import XCTest

@testable import Alveary

@MainActor
final class AppKitChatSurfaceViewTests: XCTestCase {
    func testLayoutPinsComposerToBottomAndGivesRemainingHeightToContent() {
        let surface = AppKitChatSurfaceView(frame: NSRect(x: 0, y: 0, width: 300, height: 220))
        let content = FixedHeightView(height: 80)
        let composer = FixedHeightView(height: 44)

        surface.configure(contentView: content, composerView: composer)
        surface.layoutSubtreeIfNeeded()

        XCTAssertEqual(content.frame, NSRect(x: 0, y: 0, width: 300, height: 176))
        XCTAssertEqual(composer.frame, NSRect(x: 0, y: 176, width: 300, height: 44))
    }

    func testLayoutRemeasuresComposerWhenItsHeightChanges() {
        let surface = AppKitChatSurfaceView(frame: NSRect(x: 0, y: 0, width: 300, height: 220))
        let content = FixedHeightView(height: 80)
        let composer = MutableHeightView(height: 44)
        surface.configure(contentView: content, composerView: composer)
        surface.layoutSubtreeIfNeeded()

        composer.height = 70
        surface.needsLayout = true
        surface.layoutSubtreeIfNeeded()

        XCTAssertEqual(content.frame, NSRect(x: 0, y: 0, width: 300, height: 150))
        XCTAssertEqual(composer.frame, NSRect(x: 0, y: 150, width: 300, height: 70))
    }

    func testHostedSurfaceChildSizeInvalidationRequestsSurfaceLayout() {
        let surface = AppKitChatSurfaceView(frame: NSRect(x: 0, y: 0, width: 300, height: 220))
        let content = FixedHeightView(height: 80)
        let composer = AppKitChatSurfaceHostingView(rootView: AnyView(EmptyView()))
        surface.configure(contentView: content, composerView: composer)
        surface.layoutSubtreeIfNeeded()

        surface.needsLayout = false
        composer.invalidateIntrinsicContentSize()

        XCTAssertTrue(surface.needsLayout)
    }

    func testReplacingHostedSurfaceChildClearsOldSizeInvalidationCallback() {
        let surface = AppKitChatSurfaceView(frame: NSRect(x: 0, y: 0, width: 300, height: 220))
        let content = FixedHeightView(height: 80)
        let firstComposer = AppKitChatSurfaceHostingView(rootView: AnyView(EmptyView()))
        let secondComposer = AppKitChatSurfaceHostingView(rootView: AnyView(EmptyView()))
        surface.configure(contentView: content, composerView: firstComposer)
        surface.configure(contentView: content, composerView: secondComposer)
        surface.layoutSubtreeIfNeeded()

        surface.needsLayout = false
        firstComposer.invalidateIntrinsicContentSize()

        XCTAssertFalse(surface.needsLayout)
    }

    func testComposerPanelAppliesNativeChromeLayout() throws {
        let panel = AppKitChatComposerPanelView(frame: NSRect(x: 0, y: 0, width: 300, height: 80))
        panel.configure(
            AppKitChatComposerPanelConfiguration(
                bodyConfiguration: makeComposerBodyConfiguration(),
                showsTopDivider: true,
                layout: AppKitChatComposerPanelView.Layout(
                    horizontalPadding: NSEdgeInsets(top: 0, left: 20, bottom: 0, right: 21),
                    topContentSpacing: 8,
                    actionRowSpacing: 14
                )
            )
        )

        panel.layoutSubtreeIfNeeded()

        let editorView = try composerEditorView(in: panel)
        XCTAssertEqual(editorView.frame.origin.x, 20)
        XCTAssertEqual(editorView.frame.origin.y, ChatComposerPanelLayout.nativeInputTopPadding)
        XCTAssertEqual(editorView.frame.width, 259)
        XCTAssertFalse(panel.isOpaque)
    }

    func testComposerPanelDividerUsesSeparatorColor() throws {
        let panel = AppKitChatComposerPanelView(frame: NSRect(x: 0, y: 0, width: 300, height: 80))
        panel.configure(
            AppKitChatComposerPanelConfiguration(
                bodyConfiguration: makeComposerBodyConfiguration(),
                showsTopDivider: true,
                layout: AppKitChatComposerPanelView.Layout(
                    horizontalPadding: NSEdgeInsets(top: 0, left: 20, bottom: 0, right: 21),
                    topContentSpacing: 8,
                    actionRowSpacing: 14
                )
            )
        )
        panel.layoutSubtreeIfNeeded()

        let divider = try XCTUnwrap(panel.subviews.first {
            $0.frame.height == 1 && $0.layer?.backgroundColor != nil
        })
        let expected = NSColor.separatorColor.resolved(for: panel.appKitRenderingAppearance).cgColor
        XCTAssertEqual(divider.layer?.backgroundColor, expected)
        XCTAssertFalse(divider.isHidden)
        XCTAssertEqual(divider.alphaValue, 1)
    }

    func testComposerPanelLaysOutNativeActionRowBelowNativeBody() throws {
        let panel = AppKitChatComposerPanelView(frame: NSRect(x: 0, y: 0, width: 300, height: 120))
        panel.configure(
            AppKitChatComposerPanelConfiguration(
                bodyConfiguration: makeComposerBodyConfiguration(),
                actionRowConfiguration: makeActionRowConfiguration(),
                showsTopDivider: false,
                layout: AppKitChatComposerPanelView.Layout(
                    horizontalPadding: NSEdgeInsets(top: 0, left: 20, bottom: 0, right: 21),
                    topContentSpacing: 8,
                    actionRowSpacing: 14
                )
            )
        )

        panel.layoutSubtreeIfNeeded()

        let editorView = try composerEditorView(in: panel)
        let actionRow = try XCTUnwrap(panel.subviews.first { $0 is ChatComposerActionRowView })
        XCTAssertEqual(editorView.frame.origin.x, 20)
        XCTAssertEqual(editorView.frame.origin.y, ChatComposerPanelLayout.nativeInputTopPadding)
        XCTAssertEqual(editorView.frame.width, 259)
        XCTAssertEqual(actionRow.frame.origin.y, editorView.frame.maxY + 14)
        XCTAssertEqual(actionRow.frame.width, 259)
        XCTAssertFalse(actionRow.isHidden)
        XCTAssertEqual(panel.fittingSize.height, actionRow.frame.maxY)
    }

    func testComposerPanelKeepsBottomPaddingBelowNativeActionRow() throws {
        let panel = AppKitChatComposerPanelView(frame: NSRect(x: 0, y: 0, width: 300, height: 120))
        panel.configure(
            AppKitChatComposerPanelConfiguration(
                bodyConfiguration: makeComposerBodyConfiguration(),
                actionRowConfiguration: makeActionRowConfiguration(),
                showsTopDivider: false,
                layout: AppKitChatComposerPanelView.Layout(
                    horizontalPadding: NSEdgeInsets(top: 0, left: 20, bottom: 0, right: 21),
                    topContentSpacing: 8,
                    actionRowSpacing: 14,
                    bottomPadding: 16
                )
            )
        )

        panel.layoutSubtreeIfNeeded()

        let editorView = try composerEditorView(in: panel)
        let actionRow = try XCTUnwrap(panel.subviews.first { $0 is ChatComposerActionRowView })
        XCTAssertEqual(editorView.frame.origin.y, ChatComposerPanelLayout.nativeInputTopPadding)
        XCTAssertEqual(actionRow.frame.origin.y, editorView.frame.maxY + 14)
        XCTAssertEqual(panel.fittingSize.height, actionRow.frame.maxY + 16)
    }

    func testComposerPanelLaysOutNativeTopContentAboveNativeBody() throws {
        let panel = AppKitChatComposerPanelView(frame: NSRect(x: 0, y: 0, width: 300, height: 140))
        panel.configure(
            AppKitChatComposerPanelConfiguration(
                bodyConfiguration: makeComposerBodyConfiguration(hasTopContent: true),
                topContentConfiguration: .init(items: [
                    .stagedContext(.init(context: "Restoring context from local history.") {})
                ]),
                showsTopDivider: false,
                layout: AppKitChatComposerPanelView.Layout(
                    horizontalPadding: NSEdgeInsets(top: 0, left: 20, bottom: 0, right: 21),
                    topContentSpacing: 8,
                    actionRowSpacing: 14
                )
            )
        )

        panel.layoutSubtreeIfNeeded()

        let topContentView = try XCTUnwrap(panel.subviews.first { $0 is AppKitChatComposerTopContentView })
        let editorView = try composerEditorView(in: panel)
        XCTAssertEqual(topContentView.frame.origin.x, 20)
        XCTAssertEqual(topContentView.frame.origin.y, 8)
        XCTAssertEqual(topContentView.frame.width, 259)
        XCTAssertEqual(topContentView.frame.height, 42)
        XCTAssertEqual(editorView.frame.origin.x, 20)
        XCTAssertEqual(editorView.frame.origin.y, topContentView.frame.maxY + 8)
        XCTAssertEqual(editorView.frame.width, 259)
        XCTAssertEqual(panel.fittingSize.height, editorView.frame.maxY)
    }

    func testComposerPanelLaysOutNativeQueuedMessagesAboveNativeBody() throws {
        let queuedMessages = [
            QueuedMessage(text: "Queued follow-up", stagedContext: "Context block")
        ]
        let panel = AppKitChatComposerPanelView(frame: NSRect(x: 0, y: 0, width: 300, height: 180))
        panel.configure(
            AppKitChatComposerPanelConfiguration(
                bodyConfiguration: makeComposerBodyConfiguration(hasQueuedMessages: true),
                queuedMessagesConfiguration: makeQueuedMessagesConfiguration(queuedMessages),
                actionRowConfiguration: makeActionRowConfiguration(),
                showsTopDivider: false,
                layout: AppKitChatComposerPanelView.Layout(
                    horizontalPadding: NSEdgeInsets(top: 0, left: 20, bottom: 0, right: 21),
                    topContentSpacing: 8,
                    actionRowSpacing: 14,
                    bottomPadding: 16
                )
            )
        )

        panel.layoutSubtreeIfNeeded()

        let queuedMessagesView = try XCTUnwrap(panel.subviews.first { $0 is AppKitChatQueuedMessagesView })
        let editorView = try composerEditorView(in: panel)
        let actionRow = try XCTUnwrap(panel.subviews.first { $0 is ChatComposerActionRowView })
        XCTAssertFalse(queuedMessagesView.isHidden)
        XCTAssertEqual(queuedMessagesView.frame.origin.x, 20)
        XCTAssertEqual(queuedMessagesView.frame.origin.y, 16)
        XCTAssertEqual(queuedMessagesView.frame.width, 259)
        XCTAssertEqual(editorView.frame.origin.y, queuedMessagesView.frame.maxY)
        XCTAssertEqual(actionRow.frame.origin.y, editorView.frame.maxY + 14)
        XCTAssertEqual(panel.fittingSize.height, actionRow.frame.maxY + 16)
    }

    func testNativeQueuedMessagesRouteActions() throws {
        let message = QueuedMessage(text: "Queued follow-up", stagedContext: nil)
        let view = AppKitChatQueuedMessagesView(frame: NSRect(x: 0, y: 0, width: 480, height: 80))
        var steeredID: UUID?
        var editedID: UUID?
        var dismissedID: UUID?
        view.configure(
            AppKitChatQueuedMessagesConfiguration(
                queuedMessages: [message],
                supportsMidTurnSteering: true,
                isTurnActive: true,
                inFlightQueuedMessageID: nil,
                borderWidth: 1,
                onSteer: { steeredID = $0 },
                onEdit: { editedID = $0 },
                onDismiss: { dismissedID = $0 }
            )
        )
        view.layoutSubtreeIfNeeded()

        XCTAssertTrue(try XCTUnwrap(accessibilityElement(in: view, label: "Steer queued message")).accessibilityPerformPress())
        XCTAssertTrue(try XCTUnwrap(accessibilityElement(in: view, label: "Edit queued message")).accessibilityPerformPress())
        XCTAssertTrue(try XCTUnwrap(accessibilityElement(in: view, label: "Discard queued message")).accessibilityPerformPress())
        XCTAssertEqual(steeredID, message.id)
        XCTAssertEqual(editedID, message.id)
        XCTAssertEqual(dismissedID, message.id)
    }

    func testComposerPanelNativeStagedContextPreservesSwiftUIOpacityAlpha() throws {
        let panel = AppKitChatComposerPanelView(frame: NSRect(x: 0, y: 0, width: 300, height: 140))
        panel.configure(
            AppKitChatComposerPanelConfiguration(
                bodyConfiguration: makeComposerBodyConfiguration(hasTopContent: true),
                topContentConfiguration: .init(items: [
                    .stagedContext(.init(context: "Restoring context from local history.") {})
                ]),
                showsTopDivider: false,
                layout: AppKitChatComposerPanelView.Layout(
                    horizontalPadding: NSEdgeInsets(top: 0, left: 20, bottom: 0, right: 21),
                    topContentSpacing: 8,
                    actionRowSpacing: 14
                )
            )
        )
        panel.layoutSubtreeIfNeeded()

        let topContentView = try XCTUnwrap(panel.subviews.first { $0 is AppKitChatComposerTopContentView })
        let itemView = try XCTUnwrap(topContentView.subviews.first)
        let backgroundView = try XCTUnwrap(itemView.subviews.first)
        let backgroundColor = try XCTUnwrap(backgroundView.layer?.backgroundColor)
        let expectedAlpha = NSColor.secondaryLabelColor
            .resolved(for: panel.appKitRenderingAppearance)
            .alphaComponent * 0.08

        XCTAssertEqual(backgroundColor.alpha, expectedAlpha, accuracy: 0.001)
    }

    func testComposerPanelClearsNativeTopContentFrameWhenConfigurationBecomesEmpty() throws {
        let panel = AppKitChatComposerPanelView(frame: NSRect(x: 0, y: 0, width: 300, height: 140))
        let layout = AppKitChatComposerPanelView.Layout(
            horizontalPadding: NSEdgeInsets(top: 0, left: 20, bottom: 0, right: 21),
            topContentSpacing: 8,
            actionRowSpacing: 14
        )
        panel.configure(
            AppKitChatComposerPanelConfiguration(
                bodyConfiguration: makeComposerBodyConfiguration(hasTopContent: true),
                topContentConfiguration: .init(items: [
                    .stagedContext(.init(context: "Restoring context from local history.") {})
                ]),
                showsTopDivider: false,
                layout: layout
            )
        )
        panel.layoutSubtreeIfNeeded()

        panel.configure(
            AppKitChatComposerPanelConfiguration(
                bodyConfiguration: makeComposerBodyConfiguration(),
                topContentConfiguration: .empty,
                showsTopDivider: false,
                layout: layout
            )
        )
        panel.layoutSubtreeIfNeeded()

        let topContentView = try XCTUnwrap(panel.subviews.first { $0 is AppKitChatComposerTopContentView })
        let editorView = try composerEditorView(in: panel)
        XCTAssertTrue(topContentView.isHidden)
        XCTAssertEqual(topContentView.frame, .zero)
        XCTAssertEqual(editorView.frame.origin.x, 20)
        XCTAssertEqual(editorView.frame.origin.y, ChatComposerPanelLayout.nativeInputTopPadding)
        XCTAssertEqual(editorView.frame.width, 259)
        XCTAssertEqual(panel.fittingSize.height, editorView.frame.maxY)
    }

    func testConfigureReplacesHostedViewsWithoutLeavingOldSubviews() {
        let surface = AppKitChatSurfaceView(frame: NSRect(x: 0, y: 0, width: 300, height: 220))
        let firstContent = FixedHeightView(height: 20)
        let firstComposer = FixedHeightView(height: 40)
        let secondContent = FixedHeightView(height: 30)
        let secondComposer = FixedHeightView(height: 50)

        surface.configure(contentView: firstContent, composerView: firstComposer)
        surface.configure(contentView: secondContent, composerView: secondComposer)

        XCTAssertFalse(surface.subviews.contains(firstContent))
        XCTAssertFalse(surface.subviews.contains(firstComposer))
        XCTAssertTrue(surface.subviews.contains(secondContent))
        XCTAssertTrue(surface.subviews.contains(secondComposer))
        XCTAssertEqual(surface.subviews.filter { $0 === secondContent }.count, 1)
        XCTAssertEqual(surface.subviews.filter { $0 === secondComposer }.count, 1)
        XCTAssertEqual(surface.subviews.count, 2)
    }

    func testRepresentableCoordinatorConfiguresNativeComposerPanel() {
        let configuration = AppKitChatComposerPanelConfiguration(
            bodyConfiguration: makeComposerBodyConfiguration(),
            showsTopDivider: false,
            layout: AppKitChatComposerPanelView.Layout(
                horizontalPadding: NSEdgeInsets(top: 0, left: 20, bottom: 0, right: 21),
                topContentSpacing: 8,
                actionRowSpacing: 14
            )
        )

        let coordinator = AppKitChatSurfaceRepresentable.Coordinator(
            content: AnyView(EmptyView()),
            composerConfiguration: configuration
        )

        coordinator.composerPanelView.frame = NSRect(x: 0, y: 0, width: 300, height: 80)
        coordinator.composerPanelView.layoutSubtreeIfNeeded()

        XCTAssertGreaterThan(coordinator.composerPanelView.fittingSize.height, 0)
        let editorView = coordinator.composerPanelView.editorControllerForTesting.view
        XCTAssertTrue(editorView?.superview === coordinator.composerPanelView)
    }
}

@MainActor
private func composerEditorView(in panel: AppKitChatComposerPanelView) throws -> BlockInputView {
    try XCTUnwrap(panel.editorControllerForTesting.view)
}

@MainActor
private func makeComposerBodyConfiguration(
    hasQueuedMessages: Bool = false,
    hasTopContent: Bool = false
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
        hasTopContent: hasTopContent,
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

func makeActionRowConfiguration() -> ChatComposerActionRowView.Configuration {
    ChatComposerActionRowView.Configuration(
        reasoning: makeReasoningConfiguration(),
        supportedPermissionModes: [.init(value: "default", title: "Default")],
        selectedPermissionMode: "default",
        showWorktreePicker: false,
        selectedUseWorktree: false,
        usageSummary: nil,
        areControlsDisabled: false,
        mode: .idle,
        primaryActionTitle: "Send",
        primaryActionSystemImage: "paperplane.fill",
        isPrimaryActionDisabled: false,
        isStopConfirmationArmed: false,
        composerActionRowHeight: ChatComposerActionRowView.defaultHeight,
        onPermissionModeChange: { _ in },
        onUseWorktreeChange: { _ in },
        taskWorkspace: nil,
        voiceInput: nil,
        onSubmit: {},
        onStop: {}
    )
}

@MainActor
private func makeQueuedMessagesConfiguration(_ messages: [QueuedMessage]) -> AppKitChatQueuedMessagesConfiguration {
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
private func accessibilityElement(in view: NSView, label: String) -> NSView? {
    if view.accessibilityLabel() == label {
        return view
    }
    for subview in view.subviews {
        if let element = accessibilityElement(in: subview, label: label) {
            return element
        }
    }
    return nil
}

private final class FixedHeightView: NSView {
    private let fixedHeight: CGFloat

    init(height: CGFloat) {
        fixedHeight = height
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { nil }
    override var intrinsicContentSize: NSSize { NSSize(width: NSView.noIntrinsicMetric, height: fixedHeight) }

    override var fittingSize: NSSize { NSSize(width: NSView.noIntrinsicMetric, height: fixedHeight) }
}

private final class MutableHeightView: NSView {
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
