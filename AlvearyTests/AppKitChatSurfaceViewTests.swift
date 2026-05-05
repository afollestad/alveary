@preconcurrency import AppKit
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

    func testHostedComposerSizeInvalidationRequestsSurfaceLayout() {
        let surface = AppKitChatSurfaceView(frame: NSRect(x: 0, y: 0, width: 300, height: 220))
        let content = FixedHeightView(height: 80)
        let composer = AppKitChatSurfaceHostingView(rootView: AnyView(EmptyView()))
        surface.configure(contentView: content, composerView: composer)
        surface.layoutSubtreeIfNeeded()

        surface.needsLayout = false
        composer.invalidateIntrinsicContentSize()

        XCTAssertTrue(surface.needsLayout)
    }

    func testReplacingHostedComposerClearsOldSizeInvalidationCallback() {
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
                content: AnyView(Color.clear.frame(height: 44)),
                showsTopDivider: true,
                hasTopContent: true,
                layout: AppKitChatComposerPanelView.Layout(
                    horizontalPadding: NSEdgeInsets(top: 0, left: 20, bottom: 0, right: 21),
                    topContentSpacing: 8,
                    actionRowSpacing: 14
                )
            )
        )

        panel.layoutSubtreeIfNeeded()

        let contentHost = try XCTUnwrap(panel.subviews.first { $0 is AppKitChatSurfaceHostingView })
        XCTAssertEqual(contentHost.frame.origin.x, 20)
        XCTAssertEqual(contentHost.frame.origin.y, 8)
        XCTAssertEqual(contentHost.frame.width, 259)
        XCTAssertFalse(panel.isOpaque)
    }

    func testComposerPanelDividerUsesSeparatorColor() throws {
        let panel = AppKitChatComposerPanelView(frame: NSRect(x: 0, y: 0, width: 300, height: 80))
        panel.configure(
            AppKitChatComposerPanelConfiguration(
                content: AnyView(Color.clear.frame(height: 44)),
                showsTopDivider: true,
                hasTopContent: false,
                layout: AppKitChatComposerPanelView.Layout(
                    horizontalPadding: NSEdgeInsets(top: 0, left: 20, bottom: 0, right: 21),
                    topContentSpacing: 8,
                    actionRowSpacing: 14
                )
            )
        )
        panel.layoutSubtreeIfNeeded()

        let divider = try XCTUnwrap(panel.subviews.first { $0.layer?.backgroundColor != nil })
        let expected = NSColor.separatorColor.resolved(for: panel.appKitRenderingAppearance).cgColor
        XCTAssertEqual(divider.layer?.backgroundColor, expected)
        XCTAssertFalse(divider.isHidden)
        XCTAssertEqual(divider.alphaValue, 1)
    }

    func testComposerPanelLaysOutNativeActionRowBelowHostedContent() throws {
        let panel = AppKitChatComposerPanelView(frame: NSRect(x: 0, y: 0, width: 300, height: 120))
        panel.configure(
            AppKitChatComposerPanelConfiguration(
                content: AnyView(Color.clear.frame(height: 44)),
                actionRowConfiguration: makeActionRowConfiguration(),
                showsTopDivider: false,
                hasTopContent: false,
                layout: AppKitChatComposerPanelView.Layout(
                    horizontalPadding: NSEdgeInsets(top: 0, left: 20, bottom: 0, right: 21),
                    topContentSpacing: 8,
                    actionRowSpacing: 14
                )
            )
        )

        panel.layoutSubtreeIfNeeded()

        let contentHost = try XCTUnwrap(panel.subviews.first { $0 is AppKitChatSurfaceHostingView })
        let actionRow = try XCTUnwrap(panel.subviews.first { $0 is ChatComposerActionRowView })
        XCTAssertEqual(contentHost.frame, NSRect(x: 20, y: 0, width: 259, height: 44))
        XCTAssertEqual(actionRow.frame, NSRect(x: 20, y: 58, width: 259, height: ChatComposerActionRowView.defaultHeight))
        XCTAssertFalse(actionRow.isHidden)
        XCTAssertEqual(panel.fittingSize.height, 88)
    }

    func testComposerPanelKeepsBottomPaddingBelowNativeActionRow() throws {
        let panel = AppKitChatComposerPanelView(frame: NSRect(x: 0, y: 0, width: 300, height: 120))
        panel.configure(
            AppKitChatComposerPanelConfiguration(
                content: AnyView(Color.clear.frame(height: 44)),
                actionRowConfiguration: makeActionRowConfiguration(),
                showsTopDivider: false,
                hasTopContent: false,
                layout: AppKitChatComposerPanelView.Layout(
                    horizontalPadding: NSEdgeInsets(top: 0, left: 20, bottom: 0, right: 21),
                    topContentSpacing: 8,
                    actionRowSpacing: 14,
                    bottomPadding: 16
                )
            )
        )

        panel.layoutSubtreeIfNeeded()

        let contentHost = try XCTUnwrap(panel.subviews.first { $0 is AppKitChatSurfaceHostingView })
        let actionRow = try XCTUnwrap(panel.subviews.first { $0 is ChatComposerActionRowView })
        XCTAssertEqual(contentHost.frame, NSRect(x: 20, y: 0, width: 259, height: 44))
        XCTAssertEqual(actionRow.frame, NSRect(x: 20, y: 58, width: 259, height: ChatComposerActionRowView.defaultHeight))
        XCTAssertEqual(panel.fittingSize.height, 104)
    }

    func testComposerPanelLaysOutNativeTopContentAboveHostedContent() throws {
        let panel = AppKitChatComposerPanelView(frame: NSRect(x: 0, y: 0, width: 300, height: 140))
        panel.configure(
            AppKitChatComposerPanelConfiguration(
                content: AnyView(Color.clear.frame(height: 44)),
                topContentConfiguration: .init(items: [
                    .stagedContext(.init(context: "Restoring context from local history.") {})
                ]),
                showsTopDivider: false,
                hasTopContent: false,
                layout: AppKitChatComposerPanelView.Layout(
                    horizontalPadding: NSEdgeInsets(top: 0, left: 20, bottom: 0, right: 21),
                    topContentSpacing: 8,
                    actionRowSpacing: 14
                )
            )
        )

        panel.layoutSubtreeIfNeeded()

        let topContentView = try XCTUnwrap(panel.subviews.first { $0 is AppKitChatComposerTopContentView })
        let contentHost = try XCTUnwrap(panel.subviews.first { $0 is AppKitChatSurfaceHostingView })
        XCTAssertEqual(topContentView.frame.origin.x, 20)
        XCTAssertEqual(topContentView.frame.origin.y, 8)
        XCTAssertEqual(topContentView.frame.width, 259)
        XCTAssertEqual(topContentView.frame.height, 42)
        XCTAssertEqual(contentHost.frame, NSRect(x: 20, y: 58, width: 259, height: 44))
        XCTAssertEqual(panel.fittingSize.height, 102)
    }

    func testComposerPanelNativeStagedContextPreservesSwiftUIOpacityAlpha() throws {
        let panel = AppKitChatComposerPanelView(frame: NSRect(x: 0, y: 0, width: 300, height: 140))
        panel.configure(
            AppKitChatComposerPanelConfiguration(
                content: AnyView(Color.clear.frame(height: 44)),
                topContentConfiguration: .init(items: [
                    .stagedContext(.init(context: "Restoring context from local history.") {})
                ]),
                showsTopDivider: false,
                hasTopContent: false,
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
                content: AnyView(Color.clear.frame(height: 44)),
                topContentConfiguration: .init(items: [
                    .stagedContext(.init(context: "Restoring context from local history.") {})
                ]),
                showsTopDivider: false,
                hasTopContent: false,
                layout: layout
            )
        )
        panel.layoutSubtreeIfNeeded()

        panel.configure(
            AppKitChatComposerPanelConfiguration(
                content: AnyView(Color.clear.frame(height: 44)),
                topContentConfiguration: .empty,
                showsTopDivider: false,
                hasTopContent: false,
                layout: layout
            )
        )
        panel.layoutSubtreeIfNeeded()

        let topContentView = try XCTUnwrap(panel.subviews.first { $0 is AppKitChatComposerTopContentView })
        let contentHost = try XCTUnwrap(panel.subviews.first { $0 is AppKitChatSurfaceHostingView })
        XCTAssertTrue(topContentView.isHidden)
        XCTAssertEqual(topContentView.frame, .zero)
        XCTAssertEqual(contentHost.frame, NSRect(x: 20, y: 0, width: 259, height: 44))
        XCTAssertEqual(panel.fittingSize.height, 44)
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
        XCTAssertEqual(surface.subviews.count, 2)
    }

    func testRepresentableCoordinatorConfiguresNativeComposerPanel() {
        let configuration = AppKitChatComposerPanelConfiguration(
            content: AnyView(Color.clear.frame(height: 44)),
            showsTopDivider: false,
            hasTopContent: false,
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
        XCTAssertTrue(coordinator.composerPanelView.subviews.contains { $0 is AppKitChatSurfaceHostingView })
    }
}

private func makeActionRowConfiguration() -> ChatComposerActionRowView.Configuration {
    ChatComposerActionRowView.Configuration(
        modelOptions: [.init(value: "sonnet", title: "Sonnet")],
        selectedModel: "sonnet",
        supportedEffortLevels: [.init(value: "medium", title: "Medium")],
        selectedEffort: "medium",
        supportedPermissionModes: [.init(value: "default", title: "Default")],
        selectedPermissionMode: "default",
        showWorktreePicker: false,
        selectedUseWorktree: false,
        sessionLocationLabel: "Local",
        usageSummary: nil,
        isTextEditorDisabled: false,
        areControlsDisabled: false,
        mode: .idle,
        primaryActionTitle: "Send",
        primaryActionSystemImage: "paperplane.fill",
        isPrimaryActionDisabled: false,
        isStopConfirmationArmed: false,
        composerActionRowHeight: ChatComposerActionRowView.defaultHeight,
        contextIndicatorKeyboardSpacing: ChatComposerActionRowView.defaultContextIndicatorKeyboardSpacing,
        onModelChange: { _ in },
        onEffortChange: { _ in },
        onPermissionModeChange: { _ in },
        onUseWorktreeChange: { _ in },
        onSubmit: {},
        onStop: {},
        onShowKeymap: {}
    )
}

private final class FixedHeightView: NSView {
    private let fixedHeight: CGFloat

    init(height: CGFloat) {
        fixedHeight = height
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: fixedHeight)
    }

    override var fittingSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: fixedHeight)
    }
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

    required init?(coder: NSCoder) {
        nil
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: height)
    }

    override var fittingSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: height)
    }
}
