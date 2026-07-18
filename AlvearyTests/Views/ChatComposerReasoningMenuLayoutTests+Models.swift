import AppKit
import XCTest

@testable import Alveary

@MainActor
extension ChatComposerReasoningMenuLayoutTests {
    func testDisclosureResizesModelsSectionImmediatelyWhileCaretRotates() throws {
        var sizeChanges: [NSSize] = []
        let configuration = makeReasoningConfiguration(supportsSpeedMode: true)
        let controller = ComposerReasoningMenuViewController(
            configuration: configuration,
            onRequestCloseMainMenu: {},
            onContentSizeChanged: { sizeChanges.append($0) },
            reducesMotion: { false }
        )
        controller.loadViewIfNeeded()
        let window = mountForModelsSectionLayout(controller)
        defer { window.contentView = nil }

        let collapsedSize = controller.preferredContentSize
        let slider = try XCTUnwrap(controller.debugEffortSlider)
        let disclosure = try XCTUnwrap(controller.debugModelsDisclosure)
        let fast = try XCTUnwrap(controller.debugFastToggle)
        let modelsSection = try XCTUnwrap(controller.debugModelsSection)
        let modelList = try XCTUnwrap(controller.debugModelList)
        let pinnedFrames = [slider.frame, disclosure.frame, fast.frame]
        XCTAssertTrue(modelsSection.isAccessibilityHidden())

        controller.setModelsExpanded(true, animated: true)

        let expandedSize = ComposerReasoningMenuMetrics.mainContentSize(
            for: configuration,
            isModelsExpanded: true
        )
        XCTAssertEqual(controller.preferredContentSize, expandedSize)
        XCTAssertEqual(controller.view.frame.size, expandedSize)
        XCTAssertEqual(sizeChanges.last, expandedSize)
        XCTAssertEqual(
            modelsSection.frame.height,
            ComposerReasoningMenuMetrics.modelsSectionHeight(groups: configuration.modelGroups),
            accuracy: 0.001
        )
        XCTAssertTrue(modelsSection.allowsHitTesting)
        XCTAssertFalse(modelsSection.isAccessibilityHidden())
        XCTAssertTrue(fast.nextKeyView === modelList.focusableRows.first)
        XCTAssertEqual([slider.frame, disclosure.frame, fast.frame], pinnedFrames)
        XCTAssertTrue(disclosure.debugDidRequestChevronRotationAnimation)
        XCTAssertEqual(disclosure.debugChevronFrameCenterRotationDegrees, 90, accuracy: 0.001)

        controller.setModelsExpanded(false, animated: true)

        XCTAssertEqual(controller.preferredContentSize, collapsedSize)
        XCTAssertEqual(controller.view.frame.size, collapsedSize)
        XCTAssertEqual(sizeChanges.last, collapsedSize)
        XCTAssertEqual(modelsSection.frame.height, 0)
        XCTAssertFalse(modelsSection.allowsHitTesting)
        XCTAssertTrue(modelsSection.isAccessibilityHidden())
        XCTAssertFalse(fast.nextKeyView === modelList.focusableRows.first)
        XCTAssertEqual([slider.frame, disclosure.frame, fast.frame], pinnedFrames)
        XCTAssertEqual(disclosure.debugChevronFrameCenterRotationDegrees, 0, accuracy: 0.001)
    }

    func testDisclosureActivationPreservesCaretAnimationThroughControllerSynchronization() throws {
        let controller = ComposerReasoningMenuViewController(
            configuration: makeReasoningConfiguration(),
            onRequestCloseMainMenu: {},
            reducesMotion: { false }
        )
        controller.loadViewIfNeeded()
        let disclosure = try XCTUnwrap(controller.debugModelsDisclosure)

        disclosure.performActivationForTesting()

        XCTAssertTrue(controller.isModelsExpanded)
        XCTAssertTrue(disclosure.isExpanded)
        XCTAssertTrue(disclosure.debugDidRequestChevronRotationAnimation)
        XCTAssertEqual(disclosure.debugChevronFrameCenterRotationDegrees, 90, accuracy: 0.001)
    }

    func testDisclosureKeyboardCommandsUpdateExpansionAndAccessibilityState() {
        var expansionChanges: [Bool] = []
        let control = ComposerReasoningModelsDisclosureControl(reducesMotion: { true })
        control.frame = NSRect(x: 0, y: 0, width: 180, height: 32)
        control.configure(
            isExpanded: false,
            isEnabled: true,
            animated: false,
            onExpansionChange: { expansionChanges.append($0) }
        )
        let window = NSWindow(
            contentRect: control.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.contentView = control
        defer { window.contentView = nil }

        XCTAssertEqual(control.accessibilityRole(), .button)
        XCTAssertEqual(control.accessibilityLabel(), "Models")
        control.keyDown(with: modelRowKeyEvent(keyCode: 124, window: window))
        XCTAssertTrue(control.isExpanded)
        XCTAssertTrue(control.isAccessibilityExpanded())
        control.keyDown(with: modelRowKeyEvent(keyCode: 124, window: window))
        control.keyDown(with: modelRowKeyEvent(keyCode: 123, window: window))
        XCTAssertFalse(control.isExpanded)
        XCTAssertFalse(control.isAccessibilityExpanded())
        control.keyDown(with: modelRowKeyEvent(keyCode: 123, window: window))
        control.keyDown(with: modelRowKeyEvent(keyCode: 36, window: window))
        control.keyDown(with: modelRowKeyEvent(keyCode: 49, window: window))

        XCTAssertFalse(control.isExpanded)
        XCTAssertEqual(expansionChanges, [true, false, true, false])
    }

    func testSingleNonEmptyProviderOmitsHeadingEvenWhenTitleExists() throws {
        let controller = groupedController(groups: [
            modelGroup(providerID: "claude", title: "Claude", models: [("sonnet", "Sonnet")])
        ])
        controller.setModelsExpanded(true)
        controller.view.layoutSubtreeIfNeeded()

        XCTAssertTrue(controller.view.modelsDescendants(of: ComposerReasoningHeaderView.self).isEmpty)
        XCTAssertEqual(controller.debugModelList?.debugShowsProviderHeaders, false)
    }

    func testModelsDisclosureMatchesModelOptionTypographyAndInsets() throws {
        let controller = groupedController(groups: [
            modelGroup(providerID: "claude", title: "Claude", models: [("sonnet", "Sonnet")])
        ])
        controller.setModelsExpanded(true)
        controller.view.layoutSubtreeIfNeeded()

        let disclosure = try XCTUnwrap(controller.debugModelsDisclosure)
        let modelRow = try XCTUnwrap(controller.debugModelList?.focusableRows.first)
        let modelTitleFrame = try XCTUnwrap(modelRow.debugTitleVisualFrame)
        let disclosureTitleFrameInMenu = disclosure.convert(disclosure.debugTitleVisualFrame, to: controller.view)
        let modelTitleFrameInMenu = modelRow.convert(modelTitleFrame, to: controller.view)
        XCTAssertEqual(ComposerReasoningMenuMetrics.controlsHeight, ComposerReasoningMenuMetrics.rowHeight)
        XCTAssertEqual(disclosure.intrinsicContentSize.height, ComposerReasoningMenuMetrics.rowHeight)
        XCTAssertEqual(disclosure.frame.height, modelRow.frame.height)
        XCTAssertEqual(disclosure.frame.width, modelRow.frame.width)
        XCTAssertEqual(modelRow.frame.height, ComposerReasoningMenuMetrics.rowHeight)
        XCTAssertEqual(disclosure.frame.minX, modelRow.frame.minX)
        XCTAssertEqual(disclosure.debugTitleVisualFrame.origin, modelTitleFrame.origin)
        XCTAssertEqual(disclosure.debugTitleVisualFrame.height, modelTitleFrame.height)
        XCTAssertEqual(disclosureTitleFrameInMenu.minX, modelTitleFrameInMenu.minX, accuracy: 0.001)
        XCTAssertEqual(disclosure.debugTitleFont.fontName, modelRow.debugTitleFont.fontName)
        XCTAssertEqual(disclosure.debugTitleFont.pointSize, modelRow.debugTitleFont.pointSize, accuracy: 0.001)
        XCTAssertEqual(
            disclosure.debugTitleFont.fontDescriptor.symbolicTraits,
            modelRow.debugTitleFont.fontDescriptor.symbolicTraits
        )
        XCTAssertEqual(disclosure.debugInteractionBackgroundFrame.minX, modelRow.debugInteractionBackgroundFrame.minX)
        XCTAssertEqual(disclosure.debugInteractionBackgroundFrame.minY, modelRow.debugInteractionBackgroundFrame.minY)
        XCTAssertEqual(disclosure.debugInteractionBackgroundFrame.height, modelRow.debugInteractionBackgroundFrame.height)
    }

    func testMultipleNonEmptyProvidersShowHeadingsAndDivider() throws {
        let controller = groupedController(groups: [
            modelGroup(providerID: "claude", title: "Claude", models: [("sonnet", "Sonnet")]),
            modelGroup(providerID: "codex", title: "Codex", models: [("gpt", "GPT")])
        ])
        controller.setModelsExpanded(true)
        controller.view.layoutSubtreeIfNeeded()

        let headers = controller.view.modelsDescendants(of: ComposerReasoningHeaderView.self).map(\.stringValue)
        XCTAssertEqual(headers, ["Claude", "Codex"])
        XCTAssertEqual(controller.debugModelList?.debugShowsProviderHeaders, true)
        XCTAssertEqual(
            controller.debugModelList?.modelsDescendants(of: AppKitComposerPopoverDividerView.self).count,
            1
        )

        let modelsSection = try XCTUnwrap(controller.debugModelsSection)
        let mainDivider = try XCTUnwrap(
            modelsSection.subviews.compactMap { $0 as? AppKitComposerPopoverDividerView }.first
        )
        let firstHeader = try XCTUnwrap(
            controller.view.modelsDescendants(of: ComposerReasoningHeaderView.self).first
        )
        let firstHeaderFrame = firstHeader.convert(firstHeader.bounds, to: modelsSection)
        XCTAssertEqual(mainDivider.frame.minY, ComposerReasoningMenuMetrics.dividerSpacing, accuracy: 0.001)
        XCTAssertEqual(
            firstHeaderFrame.minY - mainDivider.frame.maxY,
            ComposerReasoningMenuMetrics.dividerSpacing,
            accuracy: 0.001
        )
    }

    func testEmptyProviderDoesNotTriggerHeadings() {
        let controller = groupedController(groups: [
            modelGroup(providerID: "empty", title: "Empty", models: []),
            modelGroup(providerID: "claude", title: "Claude", models: [("sonnet", "Sonnet")])
        ])
        controller.setModelsExpanded(true)
        controller.view.layoutSubtreeIfNeeded()

        XCTAssertTrue(controller.view.modelsDescendants(of: ComposerReasoningHeaderView.self).isEmpty)
    }

    func testNoModelsShowsDisabledPlaceholder() throws {
        let controller = groupedController(groups: [])
        controller.setModelsExpanded(true)
        controller.view.layoutSubtreeIfNeeded()

        let row = try XCTUnwrap(controller.view.modelsDescendants(of: ComposerReasoningMenuRowView.self).first {
            $0.accessibilityLabel() == "No models available"
        })
        XCTAssertFalse(row.accessibilityPerformPress())
    }

    func testProviderQualifiedIdentitySelectsOnlyMatchingDuplicateModelID() throws {
        let groups = [
            modelGroup(providerID: "claude", title: "Claude", models: [("default", "Provider default")]),
            modelGroup(providerID: "codex", title: "Codex", models: [("default", "Provider default")])
        ]
        let configuration = makeReasoningConfiguration(
            modelGroups: groups,
            selectedProvider: "codex",
            selectedModel: "default"
        )
        let controller = ComposerReasoningMenuViewController(configuration: configuration, onRequestCloseMainMenu: {})
        controller.loadViewIfNeeded()
        controller.setModelsExpanded(true)

        let list = try XCTUnwrap(controller.debugModelList)
        let selectedIdentities = zip(list.debugModelRowIdentities, list.focusableRows).compactMap { identity, row in
            row.accessibilityValue() as? String == "Selected" ? identity : nil
        }
        XCTAssertEqual(selectedIdentities, ["codex:default"])
        XCTAssertEqual(
            list.focusableRows.compactMap { $0.accessibilityLabel() },
            ["Claude, Provider default", "Codex, Provider default"]
        )
    }

    func testSelectionOnlyUpdatePreservesModelRowsWhileStructureChangeRebuilds() throws {
        let groups = [modelGroup(
            providerID: "claude",
            title: "Claude",
            models: (0 ..< 20).map { ("model-\($0)", "Model \($0)") }
        )]
        let controller = groupedController(groups: groups)
        controller.setModelsExpanded(true)
        let window = mountForModelsSectionLayout(controller)
        defer { window.contentView = nil }
        let list = try XCTUnwrap(controller.debugModelList)
        let scrollView = try XCTUnwrap(list.modelsDescendants(of: NSScrollView.self).first)
        let focusedRow = try XCTUnwrap(list.focusableRows[reasoningMenuSafe: 4])

        scrollView.contentView.scroll(to: NSPoint(x: 0, y: 80))
        scrollView.reflectScrolledClipView(scrollView.contentView)
        XCTAssertTrue(window.makeFirstResponder(focusedRow))
        let preservedScrollOrigin = list.debugScrollOrigin
        XCTAssertGreaterThan(preservedScrollOrigin.y, 0)

        let selectionUpdate = makeReasoningConfiguration(modelGroups: groups, selectedModel: "model-12")
        controller.update(configuration: selectionUpdate)

        XCTAssertTrue(list.focusableRows[4] === focusedRow)
        XCTAssertTrue(window.firstResponder === focusedRow)
        XCTAssertEqual(list.debugScrollOrigin.x, preservedScrollOrigin.x, accuracy: 0.001)
        XCTAssertEqual(list.debugScrollOrigin.y, preservedScrollOrigin.y, accuracy: 0.001)
        XCTAssertEqual(list.focusableRows[12].accessibilityValue() as? String, "Selected")

        var structureUpdate = selectionUpdate
        structureUpdate.modelGroups = [modelGroup(
            providerID: "claude",
            title: "Claude",
            models: (0 ... 20).map { ("model-\($0)", "Model \($0)") }
        )]
        controller.update(configuration: structureUpdate)
        XCTAssertFalse(list.focusableRows[4] === focusedRow)
        XCTAssertEqual(list.debugScrollOrigin, .zero)
    }

    func testFocusingOffscreenModelRowScrollsItIntoView() throws {
        let groups = [modelGroup(
            providerID: "claude",
            title: "Claude",
            models: (0 ..< 30).map { ("model-\($0)", "Model \($0)") }
        )]
        let controller = groupedController(groups: groups)
        controller.setModelsExpanded(true)
        let window = mountForModelsSectionLayout(controller)
        defer { window.contentView = nil }
        let list = try XCTUnwrap(controller.debugModelList)
        let scrollView = try XCTUnwrap(list.modelsDescendants(of: NSScrollView.self).first)
        let lastRow = try XCTUnwrap(list.focusableRows.last)

        XCTAssertEqual(list.debugScrollOrigin, .zero)
        XCTAssertTrue(window.makeFirstResponder(lastRow))

        let visibleRect = scrollView.documentVisibleRect
        XCTAssertTrue(window.firstResponder === lastRow)
        XCTAssertGreaterThan(list.debugScrollOrigin.y, 0)
        XCTAssertGreaterThanOrEqual(lastRow.frame.minY, visibleRect.minY - 1)
        XCTAssertLessThanOrEqual(lastRow.frame.maxY, visibleRect.maxY + 1)
    }

    func testModelRowsActivateFromReturnAndSpace() throws {
        let groups = [modelGroup(
            providerID: "claude",
            title: "Claude",
            models: [("sonnet", "Sonnet"), ("opus", "Opus")]
        )]
        var requests: [ChatComposerActionRowView.ReasoningModelSelectionRequest] = []
        let controller = ComposerReasoningMenuViewController(
            configuration: makeReasoningConfiguration(
                modelGroups: groups,
                onModelChange: { request in
                    requests.append(request)
                    return .applied(selection: makeReasoningConfiguration(
                        modelGroups: groups,
                        selectedModel: request.modelID
                    ).selection)
                }
            ),
            onRequestCloseMainMenu: {}
        )
        controller.loadViewIfNeeded()
        controller.setModelsExpanded(true)
        let window = mountForModelsSectionLayout(controller)
        defer { window.contentView = nil }
        let rows = try XCTUnwrap(controller.debugModelList?.focusableRows)
        let sonnetRow = try XCTUnwrap(rows.first { $0.accessibilityLabel() == "Sonnet" })
        let opusRow = try XCTUnwrap(rows.first { $0.accessibilityLabel() == "Opus" })

        XCTAssertTrue(window.makeFirstResponder(opusRow))
        opusRow.keyDown(with: modelRowKeyEvent(keyCode: 36, window: window))
        XCTAssertEqual(requests, [.init(providerID: "claude", modelID: "opus")])
        XCTAssertEqual(opusRow.accessibilityValue() as? String, "Selected")

        XCTAssertTrue(window.makeFirstResponder(sonnetRow))
        sonnetRow.keyDown(with: modelRowKeyEvent(keyCode: 49, window: window))
        XCTAssertEqual(requests, [
            .init(providerID: "claude", modelID: "opus"),
            .init(providerID: "claude", modelID: "sonnet")
        ])
        XCTAssertEqual(sonnetRow.accessibilityValue() as? String, "Selected")
    }

    func testModelRowShowsHoverPressedAndFocusInteractionStates() throws {
        let groups = [modelGroup(providerID: "claude", title: "Claude", models: [("sonnet", "Sonnet")])]
        var requests: [ChatComposerActionRowView.ReasoningModelSelectionRequest] = []
        let selection = makeReasoningConfiguration(modelGroups: groups).selection
        let controller = ComposerReasoningMenuViewController(
            configuration: makeReasoningConfiguration(
                modelGroups: groups,
                onModelChange: {
                    requests.append($0)
                    return .unchanged(selection)
                }
            ),
            onRequestCloseMainMenu: {}
        )
        controller.loadViewIfNeeded()
        controller.setModelsExpanded(true)
        let window = mountForModelsSectionLayout(controller)
        defer { window.contentView = nil }
        let row = try XCTUnwrap(controller.debugModelList?.focusableRows.first)

        XCTAssertFalse(row.debugShowsInteractionBackground)
        row.mouseEntered(with: NSEvent())
        XCTAssertTrue(row.debugShowsInteractionBackground)
        row.mouseDown(with: modelRowMouseEvent(type: .leftMouseDown, in: row, window: window))
        XCTAssertTrue(window.firstResponder === row)
        XCTAssertTrue(row.debugShowsInteractionBackground)
        row.mouseUp(with: modelRowMouseEvent(type: .leftMouseUp, in: row, window: window))
        XCTAssertEqual(requests, [.init(providerID: "claude", modelID: "sonnet")])
        XCTAssertTrue(window.firstResponder === row)

        row.mouseExited(with: NSEvent())
        XCTAssertFalse(row.debugShowsInteractionBackground)
        row.keyDown(with: modelRowKeyEvent(keyCode: 36, window: window))
        XCTAssertEqual(requests, [
            .init(providerID: "claude", modelID: "sonnet"),
            .init(providerID: "claude", modelID: "sonnet")
        ])
        XCTAssertTrue(row.debugShowsInteractionBackground)
        XCTAssertTrue(window.makeFirstResponder(nil))
        XCTAssertFalse(row.debugShowsInteractionBackground)
    }

    func testAppliedModelSelectionsUpdateEffortOptionsAndFastSupportInPlace() throws {
        let groups = [
            modelGroup(providerID: "codex", title: "Codex", models: [("fast", "Fast model")]),
            modelGroup(providerID: "claude", title: "Claude", models: [("slow", "Slow model")])
        ]
        let supportedEfforts: [ChatComposerActionRowView.MenuOption] = [.init(value: "low", title: "Low"), .init(value: "high", title: "High")]
        let slowEfforts: [ChatComposerActionRowView.MenuOption] = [.init(value: "minimal", title: "Minimal"), .init(value: "ultra", title: "Ultra")]
        let unsupportedSelection = makeReasoningConfiguration(modelGroups: groups, effortOptions: slowEfforts, selectedProvider: "claude",
            selectedModel: "slow", selectedEffort: "ultra", selectedSpeedMode: .standard, supportsSpeedMode: false).selection
        let restoredSelection = makeReasoningConfiguration(modelGroups: groups, effortOptions: supportedEfforts, selectedProvider: "codex",
            selectedModel: "fast", selectedEffort: "low", selectedSpeedMode: .standard, supportsSpeedMode: true).selection
        var displayedSelections: [ChatComposerActionRowView.ReasoningSelection] = []
        var closeCount = 0
        let controller = ComposerReasoningMenuViewController(
            configuration: makeReasoningConfiguration(
                modelGroups: groups, effortOptions: supportedEfforts, selectedProvider: "codex",
                selectedModel: "fast", selectedEffort: "high", selectedSpeedMode: .fast, supportsSpeedMode: true,
                onModelChange: { $0.providerID == "claude" ? .applied(selection: unsupportedSelection) : .applied(selection: restoredSelection) }
            ),
            onRequestCloseMainMenu: { closeCount += 1 },
            onDisplaySelectionChanged: { selection in if let selection { displayedSelections.append(selection) } }
        )
        controller.loadViewIfNeeded()
        controller.setModelsExpanded(true)
        let list = try XCTUnwrap(controller.debugModelList)
        let slider = try XCTUnwrap(controller.debugEffortSlider)
        let models = try XCTUnwrap(controller.debugModelsDisclosure)
        let fast = try XCTUnwrap(controller.debugFastToggle)
        let slowIndex = try XCTUnwrap(list.debugModelRowIdentities.firstIndex(of: "claude:slow"))
        XCTAssertTrue(list.focusableRows[slowIndex].accessibilityPerformPress())
        XCTAssertTrue(controller.isModelsExpanded)
        XCTAssertTrue(controller.debugEffortSlider === slider)
        XCTAssertEqual(slider.effortTitles, ["Minimal", "Ultra"])
        XCTAssertEqual(slider.accessibilityValueDescription(), "Ultra")
        XCTAssertTrue(fast.isHidden)
        XCTAssertFalse(fast.isAccessibilityElement())
        XCTAssertTrue(models.nextKeyView === list.focusableRows.first)
        XCTAssertEqual(displayedSelections.last, unsupportedSelection)

        let fastIndex = try XCTUnwrap(list.debugModelRowIdentities.firstIndex(of: "codex:fast"))
        XCTAssertTrue(list.focusableRows[fastIndex].accessibilityPerformPress())
        XCTAssertTrue(controller.isModelsExpanded)
        XCTAssertEqual(slider.effortTitles, ["Low", "High"])
        XCTAssertEqual(slider.accessibilityValueDescription(), "Low")
        XCTAssertFalse(fast.isHidden)
        XCTAssertEqual(fast.debugSymbolName, "bolt")
        XCTAssertEqual(fast.accessibilityValue() as? String, "Off")
        XCTAssertEqual(fast.accessibilityHelp(), "Enable fast mode")
        XCTAssertTrue(models.nextKeyView === fast)
        XCTAssertTrue(fast.nextKeyView === list.focusableRows.first)
        XCTAssertEqual(displayedSelections.last, restoredSelection)
        XCTAssertEqual(closeCount, 0)
    }

    func testLongModelListCapsOnlyViewport() throws {
        let models = (0 ..< 30).map { ("model-\($0)", "Model \($0)") }
        let groups = [modelGroup(providerID: "claude", title: "Claude", models: models)]
        let controller = groupedController(groups: groups)
        controller.setModelsExpanded(true)
        controller.view.layoutSubtreeIfNeeded()

        let list = try XCTUnwrap(controller.debugModelList)
        XCTAssertEqual(list.frame.height, ComposerReasoningMenuMetrics.maxModelHeight)
        XCTAssertGreaterThan(list.debugDocumentHeight, list.frame.height)
        XCTAssertEqual(try XCTUnwrap(controller.debugEffortSlider).frame.minY, ComposerReasoningMenuMetrics.topInset)
    }

    private func groupedController(
        groups: [ChatComposerActionRowView.ReasoningModelGroup]
    ) -> ComposerReasoningMenuViewController {
        var configuration = makeReasoningConfiguration()
        configuration.modelGroups = groups
        let controller = ComposerReasoningMenuViewController(configuration: configuration, onRequestCloseMainMenu: {})
        controller.loadViewIfNeeded()
        return controller
    }

    private func mountForModelsSectionLayout(_ controller: ComposerReasoningMenuViewController) -> NSWindow {
        let host = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 600))
        let window = NSWindow(
            contentRect: host.bounds,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.contentView = host
        controller.view.frame = NSRect(origin: .zero, size: controller.preferredContentSize)
        host.addSubview(controller.view)
        controller.view.layoutSubtreeIfNeeded()
        return window
    }

    private func modelGroup(
        providerID: String,
        title: String,
        models: [(String, String)]
    ) -> ChatComposerActionRowView.ReasoningModelGroup {
        .init(
            providerID: providerID,
            providerTitle: title,
            options: models.map {
                .init(providerID: providerID, value: $0.0, title: $0.1)
            }
        )
    }
}
