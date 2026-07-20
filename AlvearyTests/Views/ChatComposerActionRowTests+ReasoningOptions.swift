import AppKit
import XCTest

@testable import Alveary

@MainActor
extension ChatComposerActionRowTests {
    func testReasoningModelOptionsUseCodexProviderStatusLabelsAndEfforts() {
        let menuItems = AgentModelOptionSelection.menuItems(
            in: AgentModelOptionTestFixtures.codexModelOptions,
            selectedModel: "gpt-5.4-mini",
            fallbackTitle: ChatComposerTextSupport.modelLabel(for:)
        )
        let effortOptions = AgentModelOptionSelection.effortOptions(
            in: AgentModelOptionTestFixtures.codexModelOptions,
            selectedModel: "gpt-5.4-mini"
        )

        XCTAssertEqual(menuItems.map(\.value), ["gpt-5.5", "gpt-5.4-mini"])
        XCTAssertEqual(menuItems.map(\.title), ["GPT-5.5", "GPT-5.4-Mini"])
        XCTAssertEqual(effortOptions.map(\.value), ["low", "medium"])
        XCTAssertEqual(
            AgentModelOptionSelection.defaultEffortValue(
                in: AgentModelOptionTestFixtures.codexModelOptions,
                selectedModel: "gpt-5.5"
            ),
            "medium"
        )
    }

    func testReasoningPopoverAnchorStaysFixedWhenReasoningButtonWidthChanges() throws {
        let row = ChatComposerActionRowView(frame: NSRect(x: 0, y: 0, width: 720, height: 30))
        let configuration = makeConfiguration(
            mode: .idle,
            modelOptions: [.init(value: "haiku", title: "Haiku")],
            effortOptions: [
                .init(value: "low", title: "L"),
                .init(value: "medium", title: "Medium"),
                .init(value: "high", title: "Extra High Reasoning")
            ],
            selectedEffort: "low"
        )
        row.configure(configuration)
        let controller = ComposerReasoningMenuViewController(
            configuration: configuration.reasoning,
            onRequestCloseMainMenu: {},
            onDisplaySelectionChanged: { [weak row] in
                row?.applyReasoningDisplaySelectionOverride($0)
            }
        )
        row.reasoningMenuController = controller
        controller.loadViewIfNeeded()
        row.layoutSubtreeIfNeeded()

        let initialAnchor = row.captureReasoningPopoverAnchorRect()
        row.reasoningPopoverAnchorRect = initialAnchor
        let slider = try XCTUnwrap(controller.debugEffortSlider)
        slider.beginTrackingInteraction()
        slider.updateTrackingInteraction(to: 2)
        row.layoutSubtreeIfNeeded()

        let storedAnchor = try XCTUnwrap(row.reasoningPopoverAnchorRect)
        let liveAnchor = row.captureReasoningPopoverAnchorRect()
        XCTAssertEqual(storedAnchor.minX, initialAnchor.minX, accuracy: 1)
        XCTAssertEqual(storedAnchor.midX, initialAnchor.midX, accuracy: 1)
        XCTAssertEqual(storedAnchor.width, initialAnchor.width, accuracy: 1)
        XCTAssertGreaterThan(liveAnchor.width, initialAnchor.width + 1)
        XCTAssertGreaterThan(abs(liveAnchor.midX - initialAnchor.midX), 1)
    }

    func testReasoningPopoverCollapseReappliesCapturedAnchorAndUpwardEdge() throws {
        let row = ChatComposerActionRowView(frame: NSRect(x: 0, y: 0, width: 720, height: 30))
        let configuration = makeConfiguration(mode: .idle)
        row.configure(configuration)
        let controller = ComposerReasoningMenuViewController(
            configuration: configuration.reasoning,
            onRequestCloseMainMenu: {},
            onContentSizeChanged: { [weak row] in
                row?.applyReasoningPopoverContentSize($0)
            }
        )
        let popover = RecordingShownPopover()
        popover.contentViewController = controller
        row.reasoningMenuController = controller
        row.reasoningPopover = popover
        row.layoutSubtreeIfNeeded()
        let anchorRect = row.captureReasoningPopoverAnchorRect()
        row.reasoningPopoverAnchorRect = anchorRect

        controller.setModelsExpanded(true, animated: false)
        popover.resetShowRequests()
        controller.setModelsExpanded(false, animated: false)

        XCTAssertEqual(popover.showRequests.count, 1)
        let request = try XCTUnwrap(popover.showRequests.first)
        XCTAssertEqual(request.positioningRect, anchorRect)
        XCTAssertEqual(request.positioningViewIdentifier, ObjectIdentifier(row))
        XCTAssertEqual(request.preferredEdge, .maxY)
        XCTAssertEqual(request.preferredEdge, ChatComposerActionRowView.reasoningPopoverPreferredEdge)
        XCTAssertEqual(
            popover.contentSize,
            ComposerReasoningMenuMetrics.mainContentSize(for: configuration.reasoning)
        )
    }

    func testReasoningContentSizeCallbacksTrackExpansionAndEffortOptionChangesWithoutPopover() {
        var sizes: [NSSize] = []
        let controller = ComposerReasoningMenuViewController(
            configuration: makeReasoningConfiguration(),
            onRequestCloseMainMenu: {},
            onContentSizeChanged: { sizes.append($0) }
        )

        controller.setModelsExpanded(true, animated: false)
        let expandedSize = ComposerReasoningMenuMetrics.mainContentSize(
            for: makeReasoningConfiguration(),
            isModelsExpanded: true
        )

        XCTAssertEqual(sizes.last, expandedSize)

        let noEffortConfiguration = makeReasoningConfiguration(effortOptions: [])
        controller.update(configuration: noEffortConfiguration)
        XCTAssertEqual(sizes.last, ComposerReasoningMenuMetrics.mainContentSize(
            for: noEffortConfiguration,
            isModelsExpanded: true
        ))
    }

    #if DEBUG
    func testReasoningButtonKeepsFixedGapWhenModelIsTruncated() throws {
        let button = makeReasoningButton(
            modelTitle: "GPT-5.3-Codex-Spark-Extended-Context",
            effortTitle: "High",
            width: 148
        )

        let displayedTitle = try XCTUnwrap(button.debugDisplayedModelTitle)
        XCTAssertTrue(button.debugIsModelTruncated)
        XCTAssertTrue(displayedTitle.hasSuffix("…"))
        XCTAssertGreaterThan(displayedTitle.count, 5)
        try assertReasoningButtonModelEffortGap(button)
        try assertReasoningButtonEffortChevronGap(button)
    }

    func testReasoningButtonKeepsFixedGapWhenModelFits() throws {
        let button = makeReasoningButton(
            modelTitle: "Sonnet",
            effortTitle: "High",
            width: 148
        )

        XCTAssertEqual(button.debugDisplayedModelTitle, "Sonnet")
        XCTAssertFalse(button.debugIsModelTruncated)
        try assertReasoningButtonModelEffortGap(button)
        try assertReasoningButtonEffortChevronGap(button)
    }

    func testReasoningButtonIntrinsicWidthShowsSonnetWithEffort() throws {
        let button = makeReasoningButton(
            modelTitle: "Sonnet",
            effortTitle: "High",
            width: 1
        )
        button.frame.size.width = button.intrinsicContentSize.width
        button.layoutSubtreeIfNeeded()

        XCTAssertEqual(button.debugDisplayedModelTitle, "Sonnet")
        XCTAssertFalse(button.debugIsModelTruncated)
        try assertReasoningButtonModelEffortGap(button)
        try assertReasoningButtonEffortChevronGap(button)
        XCTAssertLessThanOrEqual(try XCTUnwrap(button.debugContentTrailingGap), 2)
    }

    func testActionRowUsesReasoningButtonContentWrappingWidth() throws {
        let row = ChatComposerActionRowView(frame: NSRect(x: 0, y: 0, width: 700, height: 30))
        row.configure(makeConfiguration(
            mode: .idle,
            modelOptions: [.init(value: "sonnet", title: "Sonnet")],
            effortOptions: [.init(value: "high", title: "High")],
            selectedEffort: "high"
        ))

        row.layoutSubtreeIfNeeded()

        let reasoningButton = row.reasoningButton
        XCTAssertEqual(reasoningButton.frame.width, reasoningButton.intrinsicContentSize.width, accuracy: 1)
        XCTAssertEqual(reasoningButton.debugDisplayedModelTitle, "Sonnet")
        XCTAssertFalse(reasoningButton.debugIsModelTruncated)
        XCTAssertLessThanOrEqual(try XCTUnwrap(reasoningButton.debugContentTrailingGap), 2)
    }

    func testActionRowShowsGPTMiniWithoutClippingWhenCodexSparkFits() throws {
        let row = ChatComposerActionRowView(frame: NSRect(x: 0, y: 0, width: 700, height: 30))

        row.configure(makeConfiguration(
            mode: .idle,
            modelOptions: [.init(value: "gpt-5.4-mini", title: "GPT-5.4-Mini")],
            effortOptions: [.init(value: "high", title: "High")],
            selectedEffort: "high"
        ))
        row.layoutSubtreeIfNeeded()

        XCTAssertEqual(row.reasoningButton.debugDisplayedModelTitle, "GPT-5.4-Mini")
        XCTAssertFalse(row.reasoningButton.debugIsModelTruncated)
        XCTAssertLessThanOrEqual(try XCTUnwrap(row.reasoningButton.debugContentTrailingGap), 2)

        row.configure(makeConfiguration(
            mode: .idle,
            modelOptions: [.init(value: "gpt-5.3-codex-spark", title: "GPT-5.3-Codex-Spark")],
            effortOptions: [.init(value: "high", title: "High")],
            selectedEffort: "high"
        ))
        row.layoutSubtreeIfNeeded()

        XCTAssertEqual(row.reasoningButton.debugDisplayedModelTitle, "GPT-5.3-Codex-Spark")
        XCTAssertFalse(row.reasoningButton.debugIsModelTruncated)
        XCTAssertLessThanOrEqual(try XCTUnwrap(row.reasoningButton.debugContentTrailingGap), 2)
    }

    func testReasoningButtonIntrinsicWidthShowsGPTMiniWithFastIconAndEffort() throws {
        let button = makeReasoningButton(
            modelTitle: "GPT-5.4-Mini",
            effortTitle: "Medium",
            width: 1,
            selectedSpeedMode: .fast,
            supportsSpeedMode: true
        )
        button.frame.size.width = button.intrinsicContentSize.width
        button.layoutSubtreeIfNeeded()

        XCTAssertEqual(button.debugDisplayedModelTitle, "GPT-5.4-Mini")
        XCTAssertFalse(button.debugIsModelTruncated)
        XCTAssertGreaterThan(button.intrinsicContentSize.width, 180)
        XCTAssertLessThanOrEqual(button.intrinsicContentSize.width, ComposerReasoningButton.maxWidth)
        try assertReasoningButtonModelEffortGap(button)
        try assertReasoningButtonEffortChevronGap(button)
        XCTAssertLessThanOrEqual(try XCTUnwrap(button.debugContentTrailingGap), 2)
    }

    func testReasoningButtonFastModePreservesIconOffsetAndFixedGap() throws {
        let button = makeReasoningButton(
            modelTitle: "GPT-5.3-Codex-Spark-Extended-Context",
            effortTitle: "High",
            width: 168,
            selectedSpeedMode: .fast,
            supportsSpeedMode: true
        )

        let modelFrame = try XCTUnwrap(button.debugModelFrame)
        let fastIconFrame = try XCTUnwrap(button.debugFastIconFrame)
        let expectedLeading = fastIconFrame.maxX + button.debugFastIconTextSpacing
        XCTAssertTrue(button.debugShowsFastIcon)
        XCTAssertEqual(button.debugFastIconSymbolName, "bolt.fill")
        XCTAssertEqual(
            button.debugFastIconTintColor,
            AppAccentIcon.foregroundNSColor.appKitResolvedColor(in: button)
        )
        XCTAssertEqual(fastIconFrame.minX, button.contentDrawingRect.minX, accuracy: 0.5)
        XCTAssertEqual(modelFrame.minX, expectedLeading, accuracy: 0.5)
        XCTAssertTrue(button.debugIsModelTruncated)
        try assertReasoningButtonModelEffortGap(button)
        try assertReasoningButtonEffortChevronGap(button)
    }

    func testReasoningButtonRoutesContentSubviewHitTestingToButton() throws {
        let button = makeReasoningButton(
            modelTitle: "GPT-5.4-Mini",
            effortTitle: "High",
            width: 180,
            selectedSpeedMode: .fast,
            supportsSpeedMode: true
        )
        let contentFrames = [
            try XCTUnwrap(button.debugFastIconFrame),
            try XCTUnwrap(button.debugModelFrame),
            try XCTUnwrap(button.debugEffortFrame),
            try XCTUnwrap(button.debugChevronFrame)
        ]

        for frame in contentFrames {
            let hitView = try XCTUnwrap(button.hitTest(NSPoint(x: frame.midX, y: frame.midY)))
            XCTAssertTrue(hitView === button)
        }
        XCTAssertNil(button.hitTest(NSPoint(x: button.bounds.maxX + 1, y: button.bounds.midY)))
    }

    func testReasoningButtonCompactWidthKeepsEffortAndChevronInRow() throws {
        let button = makeReasoningButton(
            modelTitle: "GPT-5.3-Codex-Spark",
            effortTitle: "High",
            width: 132
        )

        let modelFrame = try XCTUnwrap(button.debugModelFrame)
        let effortFrame = try XCTUnwrap(button.debugEffortFrame)
        let chevronFrame = try XCTUnwrap(button.debugChevronFrame)
        XCTAssertGreaterThanOrEqual(modelFrame.width, 0)
        XCTAssertGreaterThanOrEqual(effortFrame.width, 0)
        XCTAssertGreaterThanOrEqual(effortFrame.minX, button.contentDrawingRect.minX)
        XCTAssertLessThanOrEqual(effortFrame.maxX, button.contentDrawingRect.maxX)
        XCTAssertLessThanOrEqual(modelFrame.maxX, effortFrame.minX)
        XCTAssertTrue(button.debugIsModelTruncated)
        XCTAssertTrue(try XCTUnwrap(button.debugDisplayedModelTitle).hasSuffix("…"))
        let effortChevronGap = try XCTUnwrap(button.debugEffortChevronGap)
        XCTAssertEqual(effortChevronGap, button.debugFastIconTextSpacing, accuracy: 0.5)
        XCTAssertLessThanOrEqual(chevronFrame.maxX, button.bounds.maxX - button.horizontalPadding)
    }

    func testReasoningButtonOmitsModelWhenOnlyReasoningCanFit() throws {
        let button = makeReasoningButton(
            modelTitle: "GPT-5.3-Codex-Spark",
            effortTitle: "H",
            width: 50
        )

        let modelFrame = try XCTUnwrap(button.debugModelFrame)
        let effortFrame = try XCTUnwrap(button.debugEffortFrame)
        XCTAssertEqual(button.debugDisplayedModelTitle, "")
        XCTAssertTrue(button.debugIsModelTruncated)
        XCTAssertEqual(modelFrame.width, 0, accuracy: 0.5)
        XCTAssertEqual(effortFrame.minX, modelFrame.minX, accuracy: 0.5)
        XCTAssertNil(button.debugModelEffortGap)
        try assertReasoningButtonEffortChevronGap(button)
    }
    #endif
}

private final class RecordingShownPopover: NSPopover {
    struct ShowRequest {
        let positioningRect: NSRect
        let positioningViewIdentifier: ObjectIdentifier
        let preferredEdge: NSRectEdge
    }

    private(set) var showRequests: [ShowRequest] = []

    override var isShown: Bool { true }

    override func show(
        relativeTo positioningRect: NSRect,
        of positioningView: NSView,
        preferredEdge: NSRectEdge
    ) {
        showRequests.append(ShowRequest(
            positioningRect: positioningRect,
            positioningViewIdentifier: ObjectIdentifier(positioningView),
            preferredEdge: preferredEdge
        ))
    }

    func resetShowRequests() {
        showRequests = []
    }
}

private extension NSView {
    func descendants<ViewType: NSView>(of type: ViewType.Type) -> [ViewType] {
        subviews.flatMap { child -> [ViewType] in
            var matches = child.descendants(of: type)
            if let typed = child as? ViewType {
                matches.insert(typed, at: 0)
            }
            return matches
        }
    }
}

#if DEBUG
@MainActor
private func makeReasoningButton(
    modelTitle: String,
    effortTitle: String,
    width: CGFloat,
    selectedSpeedMode: AgentSpeedMode = .standard,
    supportsSpeedMode: Bool = false
) -> ComposerReasoningButton {
    let button = ComposerReasoningButton()
    button.configure(
        selection: makeReasoningConfiguration(
            modelOptions: [.init(value: "selected-model", title: modelTitle)],
            effortOptions: [.init(value: "selected-effort", title: effortTitle)],
            selectedModel: "selected-model",
            selectedEffort: "selected-effort",
            selectedSpeedMode: selectedSpeedMode,
            supportsSpeedMode: supportsSpeedMode
        ).selection,
        height: ChatComposerActionRowView.defaultSettingsControlHeight,
        isEnabled: true,
        showsProgress: false,
        actionHandler: {}
    )
    button.frame = NSRect(
        x: 0,
        y: 0,
        width: width,
        height: ChatComposerActionRowView.defaultSettingsControlHeight
    )
    button.layoutSubtreeIfNeeded()
    return button
}

@MainActor
private func assertReasoningButtonModelEffortGap(
    _ button: ComposerReasoningButton,
    file: StaticString = #filePath,
    line: UInt = #line
) throws {
    let modelFrame = try XCTUnwrap(button.debugModelFrame, file: file, line: line)
    let effortFrame = try XCTUnwrap(button.debugEffortFrame, file: file, line: line)
    let gap = try XCTUnwrap(button.debugModelEffortGap, file: file, line: line)
    XCTAssertGreaterThan(modelFrame.width, 0, file: file, line: line)
    XCTAssertEqual(gap, 2, accuracy: 0.5, file: file, line: line)
    XCTAssertLessThanOrEqual(modelFrame.maxX, effortFrame.minX, file: file, line: line)
}

@MainActor
private func assertReasoningButtonEffortChevronGap(
    _ button: ComposerReasoningButton,
    file: StaticString = #filePath,
    line: UInt = #line
) throws {
    let effortFrame = try XCTUnwrap(button.debugEffortFrame, file: file, line: line)
    let chevronFrame = try XCTUnwrap(button.debugChevronFrame, file: file, line: line)
    let gap = try XCTUnwrap(button.debugEffortChevronGap, file: file, line: line)
    XCTAssertEqual(gap, button.debugFastIconTextSpacing, accuracy: 0.5, file: file, line: line)
    XCTAssertLessThanOrEqual(effortFrame.maxX, chevronFrame.minX, file: file, line: line)
}
#endif
