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
    }

    func testReasoningPopoverAnchorStaysFixedWhenReasoningButtonWidthChanges() throws {
        let row = ChatComposerActionRowView(frame: NSRect(x: 0, y: 0, width: 720, height: 30))
        row.configure(makeConfiguration(
            mode: .idle,
            modelOptions: [.init(value: "haiku", title: "Haiku")]
        ))
        row.layoutSubtreeIfNeeded()

        let initialAnchor = row.captureReasoningPopoverAnchorRect()
        row.reasoningPopoverAnchorRect = initialAnchor

        row.configure(makeConfiguration(
            mode: .idle,
            modelOptions: [.init(value: "codex-spark", title: "GPT-5.3-Codex-Spark")]
        ))
        row.layoutSubtreeIfNeeded()

        let storedAnchor = try XCTUnwrap(row.reasoningPopoverAnchorRect)
        let liveAnchor = row.captureReasoningPopoverAnchorRect()
        XCTAssertEqual(storedAnchor.minX, initialAnchor.minX, accuracy: 1)
        XCTAssertEqual(storedAnchor.midX, initialAnchor.midX, accuracy: 1)
        XCTAssertEqual(storedAnchor.width, initialAnchor.width, accuracy: 1)
        XCTAssertGreaterThan(liveAnchor.width, initialAnchor.width + 1)
        XCTAssertGreaterThan(abs(liveAnchor.midX - initialAnchor.midX), 1)
    }

    func testReasoningPopoverContentSizeUpdatesEvenWhenPopoverIsNotReportedShown() {
        let row = ChatComposerActionRowView(frame: NSRect(x: 0, y: 0, width: 720, height: 30))
        let controller = ComposerReasoningMenuViewController(
            configuration: makeReasoningConfiguration(effortOptions: [
                .init(value: "low", title: "Low"),
                .init(value: "medium", title: "Medium"),
                .init(value: "high", title: "High"),
                .init(value: "max", title: "Max")
            ]),
            onRequestCloseMainMenu: {},
            onContentSizeChanged: { [weak row] in
                row?.applyReasoningPopoverContentSize($0)
            }
        )
        let popover = NSPopover()
        popover.contentViewController = controller
        popover.contentSize = controller.preferredContentSize
        row.reasoningMenuController = controller
        row.reasoningPopover = popover

        let smallerConfiguration = makeReasoningConfiguration(effortOptions: [
            .init(value: "low", title: "Low"),
            .init(value: "medium", title: "Medium"),
            .init(value: "high", title: "High")
        ])
        controller.update(configuration: smallerConfiguration)

        XCTAssertFalse(popover.isShown)
        XCTAssertEqual(popover.contentSize, ComposerReasoningMenuMetrics.mainContentSize(for: smallerConfiguration))
    }

    func testOpenReasoningPopoverContentSizeTracksConfigurationChanges() throws {
        // Resizing a *shown* popover on macOS 26 schedules an `_NSWindowTransformAnimation` even with
        // `animates == false`; AppKit over-releases it after the popover window dies, crashing whichever
        // later test pumps the run loop (xcodebuild then silently relaunches the host, so suite results
        // look green while the host crashes). `testReasoningPopoverContentSizeUpdatesEvenWhenPopoverIsNotReportedShown`
        // keeps the contentSize-tracking coverage without showing the popover.
        if ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 26 {
            throw XCTSkip("Shown-popover resize crashes the test host on macOS 26 (AppKit window-transform animation over-release).")
        }
        let largeEffortOptions: [ChatComposerActionRowView.MenuOption] = [
            .init(value: "low", title: "Low"),
            .init(value: "medium", title: "Medium"),
            .init(value: "high", title: "High"),
            .init(value: "max", title: "Max")
        ]
        let smallEffortOptions: [ChatComposerActionRowView.MenuOption] = [
            .init(value: "low", title: "Low"),
            .init(value: "medium", title: "Medium"),
            .init(value: "high", title: "High")
        ]
        let row = ChatComposerActionRowView(frame: NSRect(x: 0, y: 0, width: 720, height: 30))
        let largeConfiguration = makeConfiguration(mode: .idle, effortOptions: largeEffortOptions)
        row.configure(largeConfiguration)
        let window = NSWindow(contentRect: row.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = row
        window.orderFrontRegardless()
        row.layoutSubtreeIfNeeded()
        defer {
            row.closeReasoningMenu()
            window.close()
        }

        row.toggleReasoningMenu()

        let popover = try XCTUnwrap(row.reasoningPopover)
        XCTAssertEqual(popover.contentSize, ComposerReasoningMenuMetrics.mainContentSize(for: largeConfiguration.reasoning))

        let smallConfiguration = makeConfiguration(mode: .idle, effortOptions: smallEffortOptions)
        row.configure(smallConfiguration)

        XCTAssertEqual(popover.contentSize, ComposerReasoningMenuMetrics.mainContentSize(for: smallConfiguration.reasoning))
        XCTAssertEqual(row.reasoningMenuController?.view.frame.size, popover.contentSize)
    }

    func testReasoningModelSubmenuSourceRectTopAlignsTallContent() throws {
        let controller = ComposerReasoningMenuViewController(
            configuration: makeReasoningConfiguration(
                effortOptions: [
                    .init(value: "low", title: "Low"),
                    .init(value: "medium", title: "Medium"),
                    .init(value: "high", title: "High"),
                    .init(value: "extra-high", title: "Extra High"),
                    .init(value: "max", title: "Max")
                ],
                supportsSpeedMode: true
            ),
            onRequestCloseMainMenu: {}
        )
        controller.loadViewIfNeeded()
        controller.view.layoutSubtreeIfNeeded()
        let modelRow = try XCTUnwrap(controller.view.descendants(of: ComposerReasoningMenuRowView.self).first {
            $0.accessibilityLabel() == "Model"
        })
        let tallContentSize = NSSize(width: ComposerReasoningMenuMetrics.modelWidth, height: controller.view.bounds.height)
        let sourceRect = controller.submenuSourceRect(relativeTo: modelRow, contentSize: tallContentSize)
        let modelRowRect = modelRow.convert(modelRow.bounds, to: controller.view)

        XCTAssertGreaterThan(modelRowRect.minY, 0)
        XCTAssertEqual(sourceRect.minY, 0, accuracy: 1)
        XCTAssertEqual(sourceRect.height, tallContentSize.height, accuracy: 1)
        XCTAssertEqual(sourceRect.minX, modelRowRect.minX, accuracy: 1)
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
            effortOptions: [.init(value: "high", title: "High")]
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
            effortOptions: [.init(value: "high", title: "High")]
        ))
        row.layoutSubtreeIfNeeded()

        XCTAssertEqual(row.reasoningButton.debugDisplayedModelTitle, "GPT-5.4-Mini")
        XCTAssertFalse(row.reasoningButton.debugIsModelTruncated)
        XCTAssertLessThanOrEqual(try XCTUnwrap(row.reasoningButton.debugContentTrailingGap), 2)

        row.configure(makeConfiguration(
            mode: .idle,
            modelOptions: [.init(value: "gpt-5.3-codex-spark", title: "GPT-5.3-Codex-Spark")],
            effortOptions: [.init(value: "high", title: "High")]
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
