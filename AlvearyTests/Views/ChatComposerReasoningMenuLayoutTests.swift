import AppKit
import XCTest

@testable import Alveary

@MainActor
final class ChatComposerReasoningMenuLayoutTests: XCTestCase {
    func testCollapsedMenuUsesUnifiedSurfaceAndOversizedSliderLayout() throws {
        let configuration = makeReasoningConfiguration(
            effortOptions: reasoningEffortOptions,
            supportsSpeedMode: true
        )
        let controller = makeController(configuration: configuration)
        controller.loadViewIfNeeded()
        controller.view.layoutSubtreeIfNeeded()

        XCTAssertTrue(controller.view is AppKitComposerPopoverSurfaceView)
        XCTAssertFalse(controller.view is NSVisualEffectView)
        XCTAssertEqual(controller.preferredContentSize.width, 260)

        let slider = try XCTUnwrap(controller.view.descendants(of: ComposerReasoningEffortSlider.self).first)
        let models = try XCTUnwrap(controller.view.descendants(of: ComposerReasoningModelsDisclosureControl.self).first)
        let fast = try XCTUnwrap(controller.view.descendants(of: ComposerReasoningFastToggleControl.self).first)
        let divider = try XCTUnwrap(controller.view.descendants(of: AppKitComposerPopoverDividerView.self).first)
        let modelList = try XCTUnwrap(controller.view.descendants(of: ComposerReasoningModelListView.self).first)
        let modelsSection = try XCTUnwrap(controller.debugModelsSection)

        XCTAssertEqual(slider.frame.height, 33)
        XCTAssertEqual(slider.frame.minX, ComposerReasoningMenuMetrics.sliderHorizontalInset)
        XCTAssertEqual(models.frame.minY, slider.frame.maxY + ComposerReasoningMenuMetrics.sliderBottomSpacing)
        XCTAssertEqual(fast.frame.width, 30)
        XCTAssertFalse(divider.isHidden)
        XCTAssertFalse(modelList.isHidden)
        XCTAssertEqual(modelsSection.frame.height, 0)
    }

    func testCollapsedControlsUseVisuallyBalancedInsetsAndFillAvailableWidthBeforeFast() throws {
        let controller = makeController(configuration: makeReasoningConfiguration(
            effortOptions: reasoningEffortOptions,
            supportsSpeedMode: true
        ))
        controller.loadViewIfNeeded()
        controller.view.layoutSubtreeIfNeeded()

        let slider = try XCTUnwrap(controller.debugEffortSlider)
        let models = try XCTUnwrap(controller.debugModelsDisclosure)
        let fast = try XCTUnwrap(controller.debugFastToggle)

        XCTAssertEqual(ComposerReasoningMenuMetrics.topInset, 14)
        XCTAssertEqual(ComposerReasoningMenuMetrics.bottomInset, 12)
        XCTAssertEqual(ComposerReasoningMenuMetrics.sliderBottomSpacing, 4)
        XCTAssertEqual(slider.frame.minY, ComposerReasoningMenuMetrics.topInset)
        XCTAssertEqual(
            controller.view.bounds.maxY - models.frame.maxY,
            ComposerReasoningMenuMetrics.bottomInset
        )
        XCTAssertEqual(models.frame.minX, ComposerReasoningMenuMetrics.horizontalInset)
        XCTAssertGreaterThan(models.frame.width, models.intrinsicContentSize.width)
        XCTAssertEqual(fast.frame.minX - models.frame.maxX, 6, accuracy: 0.001)
        XCTAssertEqual(
            fast.frame.maxX - fast.opticalTrailingPadding,
            controller.view.bounds.maxX - ComposerReasoningMenuMetrics.sliderHorizontalInset,
            accuracy: 0.001
        )
        XCTAssertEqual(fast.frame.maxX - fast.opticalTrailingPadding, slider.frame.maxX, accuracy: 0.001)
    }

    func testCollapsedModelsDisclosureReachesTrailingInsetWhenFastIsUnavailable() throws {
        let controller = makeController(configuration: makeReasoningConfiguration(
            effortOptions: reasoningEffortOptions,
            supportsSpeedMode: false
        ))
        controller.loadViewIfNeeded()
        controller.view.layoutSubtreeIfNeeded()

        let models = try XCTUnwrap(controller.debugModelsDisclosure)
        let fast = try XCTUnwrap(controller.debugFastToggle)

        XCTAssertTrue(fast.isHidden)
        XCTAssertEqual(fast.frame, .zero)
        XCTAssertEqual(models.frame.minX, ComposerReasoningMenuMetrics.horizontalInset)
        XCTAssertEqual(
            models.frame.maxX,
            controller.view.bounds.maxX - ComposerReasoningMenuMetrics.horizontalInset,
            accuracy: 0.001
        )
    }

    func testZeroEffortOptionsRemoveSliderAndShrinkCollapsedMenu() throws {
        let withSlider = makeReasoningConfiguration(effortOptions: reasoningEffortOptions)
        let withoutSlider = makeReasoningConfiguration(effortOptions: [])
        let controller = makeController(configuration: withSlider)
        controller.loadViewIfNeeded()
        let withSliderHeight = controller.preferredContentSize.height

        controller.update(configuration: withoutSlider)
        controller.view.layoutSubtreeIfNeeded()

        let slider = try XCTUnwrap(controller.view.descendants(of: ComposerReasoningEffortSlider.self).first)
        let models = try XCTUnwrap(controller.view.descendants(of: ComposerReasoningModelsDisclosureControl.self).first)
        XCTAssertTrue(slider.isHidden)
        XCTAssertEqual(slider.frame, .zero)
        XCTAssertEqual(models.frame.minY, ComposerReasoningMenuMetrics.topInset)
        XCTAssertEqual(
            withSliderHeight - controller.preferredContentSize.height,
            ComposerReasoningMenuMetrics.sliderHeight + ComposerReasoningMenuMetrics.sliderBottomSpacing
        )
    }

    func testExpansionResizesTopAlignedContentAndPinsControls() throws {
        var sizes: [NSSize] = []
        let configuration = makeReasoningConfiguration(effortOptions: reasoningEffortOptions)
        let controller = ComposerReasoningMenuViewController(
            configuration: configuration,
            onRequestCloseMainMenu: {},
            onContentSizeChanged: { sizes.append($0) }
        )
        controller.loadViewIfNeeded()
        let host = NSView(frame: NSRect(
            x: 0,
            y: 0,
            width: controller.preferredContentSize.width,
            height: controller.preferredContentSize.height + 420
        ))
        host.addSubview(controller.view)
        controller.alignContentViewToPopoverHost()
        controller.view.layoutSubtreeIfNeeded()
        let sliderY = try XCTUnwrap(controller.debugEffortSlider).frame.minY

        controller.setModelsExpanded(true, animated: false)
        controller.view.layoutSubtreeIfNeeded()

        XCTAssertTrue(controller.isModelsExpanded)
        XCTAssertEqual(sizes.last, controller.preferredContentSize)
        XCTAssertEqual(controller.view.frame.maxY, ComposerReasoningPopoverContentFrame.visibleTopY(
            in: host,
            contentSize: controller.preferredContentSize
        ), accuracy: 1)
        XCTAssertEqual(try XCTUnwrap(controller.debugEffortSlider).frame.minY, sliderY, accuracy: 1)
        XCTAssertFalse(try XCTUnwrap(controller.debugModelList).isHidden)
    }

    func testOneEffortOptionIsVisibleButSkippedByKeyLoop() throws {
        let controller = makeController(configuration: makeReasoningConfiguration(
            effortOptions: [.init(value: "medium", title: "Medium")],
            supportsSpeedMode: true
        ))
        controller.loadViewIfNeeded()
        let slider = try XCTUnwrap(controller.debugEffortSlider)
        let models = try XCTUnwrap(controller.debugModelsDisclosure)
        let fast = try XCTUnwrap(controller.debugFastToggle)

        XCTAssertFalse(slider.isHidden)
        XCTAssertFalse(slider.acceptsFirstResponder)
        XCTAssertTrue(models.nextKeyView === fast)
    }

    func testFastToggleVisibilitySymbolTintAndHelpFollowSelection() throws {
        let controller = makeController(configuration: makeReasoningConfiguration(
            selectedSpeedMode: .standard,
            supportsSpeedMode: true
        ))
        controller.loadViewIfNeeded()
        let fast = try XCTUnwrap(controller.debugFastToggle)

        XCTAssertFalse(fast.isHidden)
        XCTAssertEqual(fast.accessibilityRole(), .checkBox)
        XCTAssertEqual(fast.accessibilitySubrole(), .switch)
        XCTAssertEqual(fast.accessibilityLabel(), "Fast mode")
        XCTAssertEqual(fast.accessibilityValue() as? String, "Off")
        XCTAssertEqual(fast.accessibilityHelp(), "Enable fast mode")
        XCTAssertEqual(fast.toolTip, "Enable fast mode")
        XCTAssertEqual(fast.debugSymbolName, "bolt")

        controller.update(configuration: makeReasoningConfiguration(
            selectedSpeedMode: .fast,
            supportsSpeedMode: true
        ))

        XCTAssertEqual(fast.accessibilityValue() as? String, "On")
        XCTAssertEqual(fast.accessibilityHelp(), "Disable fast mode")
        XCTAssertEqual(fast.toolTip, "Disable fast mode")
        XCTAssertEqual(fast.debugSymbolName, "bolt.fill")
        let expectedAccent = AppAccentIcon.foregroundNSColor.appKitResolvedColor(in: fast)
        XCTAssertEqual(fast.debugSymbolTintColor, expectedAccent)

        controller.update(configuration: makeReasoningConfiguration(supportsSpeedMode: false))
        XCTAssertTrue(fast.isHidden)
        XCTAssertFalse(fast.isAccessibilityElement())
    }

    func testFastEnabledAccentTintPersistsThroughInteractionAndAppearanceChanges() throws {
        let control = ComposerReasoningFastToggleControl(frame: NSRect(x: 12, y: 12, width: 30, height: 30))
        control.configure(isOn: true, isEnabled: true, onToggle: { _ in })
        let window = mountReasoningMenuControl(control)
        defer { window.contentView = nil }

        let darkAppearance = try XCTUnwrap(NSAppearance(named: .darkAqua))
        control.appearance = darkAppearance
        control.viewDidChangeEffectiveAppearance()
        let darkAccent = AppAccentIcon.foregroundNSColor.appKitResolvedColor(in: control)
        XCTAssertEqual(control.debugSymbolName, "bolt.fill")
        XCTAssertEqual(control.debugSymbolTintColor, darkAccent)
        control.mouseEntered(with: NSEvent())
        XCTAssertEqual(control.debugSymbolTintColor, darkAccent)
        control.mouseDown(with: reasoningMenuMouseEvent(type: .leftMouseDown, in: control, window: window))
        XCTAssertTrue(control.debugIsPressed)
        XCTAssertEqual(control.debugSymbolTintColor, darkAccent)
        control.mouseExited(with: NSEvent())
        XCTAssertTrue(window.makeFirstResponder(control))
        control.keyDown(with: reasoningMenuKeyEvent(keyCode: 36, window: window))
        control.setOn(true, postsAccessibilityNotification: false)
        XCTAssertTrue(control.debugIsFocused)
        XCTAssertEqual(control.debugSymbolTintColor, darkAccent)
        let lightAppearance = try XCTUnwrap(NSAppearance(named: .aqua))
        control.appearance = lightAppearance
        control.viewDidChangeEffectiveAppearance()
        let lightAccent = AppAccentIcon.foregroundNSColor.appKitResolvedColor(in: control)
        XCTAssertEqual(control.debugSymbolTintColor, lightAccent)
    }

    func testDisclosureUsesOneRotatingChevronAndReduceMotionSkipsAnimation() throws {
        let control = ComposerReasoningModelsDisclosureControl(reducesMotion: { true })
        control.frame = NSRect(x: 0, y: 0, width: 180, height: 32)
        control.configure(isExpanded: false, isEnabled: true, animated: false, onExpansionChange: { _ in })

        control.setExpanded(true, animated: true)

        XCTAssertEqual(control.debugChevronSymbolName, "chevron.right")
        XCTAssertEqual(control.debugChevronRotationRadians, .pi / 2, accuracy: 0.001)
        XCTAssertEqual(control.debugChevronFrameCenterRotationDegrees, 90, accuracy: 0.001)
        XCTAssertFalse(control.debugDidRequestChevronRotationAnimation)
    }

    func testDisclosureMouseActivationDoesNotLeaveKeyboardFocusChromeVisible() throws {
        var requestedExpansion: Bool?
        let control = ComposerReasoningModelsDisclosureControl(reducesMotion: { true })
        control.frame = NSRect(x: 12, y: 12, width: 96, height: 32)
        control.configure(
            isExpanded: false,
            isEnabled: true,
            animated: false,
            onExpansionChange: { requestedExpansion = $0 }
        )
        let window = mountReasoningMenuControl(control)
        XCTAssertTrue(window.makeFirstResponder(control))
        XCTAssertFalse(control.debugIsFocused)

        control.mouseEntered(with: NSEvent())
        XCTAssertTrue(control.debugIsHovering)
        XCTAssertTrue(control.debugShowsInteractionBackground)
        control.mouseDown(with: reasoningMenuMouseEvent(type: .leftMouseDown, in: control, window: window))
        XCTAssertTrue(control.debugIsFirstResponder)
        XCTAssertTrue(control.debugIsPressed)
        XCTAssertFalse(control.debugIsFocused)

        control.mouseUp(with: reasoningMenuMouseEvent(type: .leftMouseUp, in: control, window: window))
        XCTAssertEqual(requestedExpansion, true)
        XCTAssertFalse(control.debugIsPressed)
        XCTAssertFalse(control.debugIsFocused)
        XCTAssertFalse(control.debugShowsInteractionBackground)

        control.keyDown(with: reasoningMenuKeyEvent(keyCode: 36, window: window))
        XCTAssertTrue(control.debugIsFocused)
    }

    func testFastMouseActivationDoesNotLeaveKeyboardFocusChromeVisible() throws {
        var requestedValue: Bool?
        let control = ComposerReasoningFastToggleControl(frame: NSRect(x: 12, y: 12, width: 30, height: 30))
        control.configure(isOn: false, isEnabled: true, onToggle: { requestedValue = $0 })
        let window = mountReasoningMenuControl(control)
        XCTAssertTrue(window.makeFirstResponder(control))
        XCTAssertFalse(control.debugIsFocused)

        control.mouseEntered(with: NSEvent())
        XCTAssertTrue(control.debugIsHovering)
        XCTAssertTrue(control.debugShowsInteractionBackground)
        control.mouseDown(with: reasoningMenuMouseEvent(type: .leftMouseDown, in: control, window: window))
        XCTAssertTrue(control.debugIsFirstResponder)
        XCTAssertTrue(control.debugIsPressed)
        XCTAssertFalse(control.debugIsFocused)

        control.mouseUp(with: reasoningMenuMouseEvent(type: .leftMouseUp, in: control, window: window))
        XCTAssertEqual(requestedValue, true)
        XCTAssertFalse(control.debugIsPressed)
        XCTAssertFalse(control.debugIsFocused)
        XCTAssertFalse(control.debugShowsInteractionBackground)

        control.keyDown(with: reasoningMenuKeyEvent(keyCode: 36, window: window))
        XCTAssertTrue(control.debugIsFocused)
    }

    func testInteractiveControlRevealsFocusOnlyForKeyboardDrivenResponderChanges() {
        XCTAssertFalse(ComposerReasoningMenuInteractiveControl.shouldRevealFocusState(for: nil))
        XCTAssertFalse(ComposerReasoningMenuInteractiveControl.shouldRevealFocusState(
            for: reasoningMenuMouseEvent(type: .leftMouseUp)
        ))
        XCTAssertTrue(ComposerReasoningMenuInteractiveControl.shouldRevealFocusState(
            for: reasoningMenuKeyEvent(keyCode: 48)
        ))
    }

    func testSharedMenuRowFocusBackgroundRemainsOptIn() {
        let defaultRow = makeMenuRow(showsFocusBackground: false)
        let focusedRow = makeMenuRow(showsFocusBackground: true)
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 180, height: 64))
        defaultRow.frame = NSRect(x: 0, y: 0, width: 180, height: 32)
        focusedRow.frame = NSRect(x: 0, y: 32, width: 180, height: 32)
        container.addSubview(defaultRow)
        container.addSubview(focusedRow)
        let window = NSWindow(contentRect: container.bounds, styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = container

        XCTAssertTrue(window.makeFirstResponder(defaultRow))
        XCTAssertFalse(defaultRow.debugShowsInteractionBackground)
        XCTAssertTrue(window.makeFirstResponder(focusedRow))
        XCTAssertFalse(focusedRow.debugShowsInteractionBackground)
        focusedRow.keyDown(with: reasoningMenuKeyEvent(keyCode: 36, window: window))
        XCTAssertTrue(focusedRow.debugShowsInteractionBackground)
    }

    func testAppliedModelSelectionFromRealRowKeepsExpandedMenuOpen() throws {
        var closeCount = 0
        var requests: [ChatComposerActionRowView.ReasoningModelSelectionRequest] = []
        let modelOptions: [ChatComposerActionRowView.MenuOption] = [
            .init(value: "sonnet", title: "Sonnet"),
            .init(value: "opus", title: "Opus")
        ]
        let controller = ComposerReasoningMenuViewController(
            configuration: makeReasoningConfiguration(
                modelOptions: modelOptions,
                onModelChange: { request in
                    requests.append(request)
                    return .applied(selection: makeReasoningConfiguration(
                        modelOptions: modelOptions,
                        selectedModel: request.modelID
                    ).selection)
                }
            ),
            onRequestCloseMainMenu: { closeCount += 1 }
        )
        controller.loadViewIfNeeded()
        controller.setModelsExpanded(true)
        let opusRow = try XCTUnwrap(controller.debugModelList?.focusableRows.first {
            $0.accessibilityLabel() == "Opus"
        })

        XCTAssertTrue(opusRow.accessibilityPerformPress())

        XCTAssertEqual(requests, [.init(providerID: "claude", modelID: "opus")])
        XCTAssertEqual(closeCount, 0)
        XCTAssertTrue(controller.isModelsExpanded)
        XCTAssertEqual(opusRow.accessibilityValue() as? String, "Selected")
    }

    var reasoningEffortOptions: [ChatComposerActionRowView.MenuOption] {
        [
            .init(value: "low", title: "Low"),
            .init(value: "medium", title: "Medium"),
            .init(value: "high", title: "High"),
            .init(value: "extra-high", title: "Extra High"),
            .init(value: "max", title: "Max")
        ]
    }

    func makeController(
        configuration: ChatComposerActionRowView.ReasoningConfiguration
    ) -> ComposerReasoningMenuViewController {
        ComposerReasoningMenuViewController(configuration: configuration, onRequestCloseMainMenu: {})
    }

    private func makeMenuRow(showsFocusBackground: Bool) -> ComposerReasoningMenuRowView {
        let row = ComposerReasoningMenuRowView()
        row.configure(.init(
            title: "Model",
            iconName: nil,
            trailingIconName: nil,
            accessibilityLabel: "Model",
            isSelected: false,
            isEnabled: true,
            showsFocusBackground: showsFocusBackground,
            action: {},
            cancelAction: {}
        ))
        return row
    }
}

@MainActor
private func mountReasoningMenuControl(_ control: NSView) -> NSWindow {
    let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 180, height: 60),
        styleMask: .borderless,
        backing: .buffered,
        defer: false
    )
    window.contentView?.addSubview(control)
    return window
}

@MainActor
private func reasoningMenuMouseEvent(
    type: NSEvent.EventType,
    in control: NSView,
    window: NSWindow
) -> NSEvent {
    let location = control.convert(NSPoint(x: control.bounds.midX, y: control.bounds.midY), to: nil)
    return NSEvent.mouseEvent(
        with: type,
        location: location,
        modifierFlags: [],
        timestamp: 0,
        windowNumber: window.windowNumber,
        context: nil,
        eventNumber: 0,
        clickCount: 1,
        pressure: 0
    ) ?? NSEvent()
}

@MainActor
private func reasoningMenuMouseEvent(type: NSEvent.EventType) -> NSEvent {
    NSEvent.mouseEvent(
        with: type,
        location: .zero,
        modifierFlags: [],
        timestamp: 0,
        windowNumber: 0,
        context: nil,
        eventNumber: 0,
        clickCount: 1,
        pressure: 0
    ) ?? NSEvent()
}

@MainActor
private func reasoningMenuKeyEvent(keyCode: UInt16, window: NSWindow) -> NSEvent {
    NSEvent.keyEvent(
        with: .keyDown,
        location: .zero,
        modifierFlags: [],
        timestamp: 0,
        windowNumber: window.windowNumber,
        context: nil,
        characters: "\r",
        charactersIgnoringModifiers: "\r",
        isARepeat: false,
        keyCode: keyCode
    ) ?? NSEvent()
}

@MainActor
private func reasoningMenuKeyEvent(keyCode: UInt16) -> NSEvent {
    NSEvent.keyEvent(
        with: .keyDown,
        location: .zero,
        modifierFlags: [],
        timestamp: 0,
        windowNumber: 0,
        context: nil,
        characters: "\t",
        charactersIgnoringModifiers: "\t",
        isARepeat: false,
        keyCode: keyCode
    ) ?? NSEvent()
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
