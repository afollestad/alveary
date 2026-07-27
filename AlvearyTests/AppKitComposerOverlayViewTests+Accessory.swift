@preconcurrency import AppKit
import XCTest

@testable import Alveary

@MainActor
extension AppKitComposerOverlayViewTests {
    func testAccessoryIsHiddenAndDoesNotChangeGeometryWhenAbsent() {
        let withoutAccessory = makeAccessoryPanel(accessory: nil)
        let heightWithout = withoutAccessory.measuredHeight(width: 700)
        withoutAccessory.frame.size.height = heightWithout
        withoutAccessory.layoutSubtreeIfNeeded()

        XCTAssertTrue(withoutAccessory.accessoryButton.isHidden)
        XCTAssertEqual(withoutAccessory.accessoryButton.frame, .zero)
        XCTAssertEqual(withoutAccessory.accessoryFooterWidth, 0)

        // An `AskUserQuestion` overlay must measure exactly as it did before the slot existed.
        let withAccessory = makeAccessoryPanel(accessory: makeOverlayAccessory())
        XCTAssertEqual(withAccessory.measuredHeight(width: 700), heightWithout, accuracy: 0.5)
    }

    func testAccessorySitsImmediatelyLeftOfDismissInFooterGroup() throws {
        let panel = makeAccessoryPanel(accessory: makeOverlayAccessory())
        panel.frame.size.height = panel.measuredHeight(width: 700)
        panel.layoutSubtreeIfNeeded()

        XCTAssertFalse(panel.accessoryButton.isHidden)
        // One trailing action group: accessory, standard footer gap, Dismiss, Submit.
        XCTAssertEqual(
            panel.accessoryButton.frame.maxX,
            panel.dismissButton.frame.minX - AppKitComposerOverlayMetrics.footerButtonSpacing,
            accuracy: 0.5
        )
        XCTAssertEqual(
            panel.accessoryButton.frame.midY,
            panel.dismissButton.frame.midY,
            accuracy: 1
        )
    }

    func testAccessoryMenuOpensUpwardFromFlippedPanel() {
        // NSPopover edges are anchor-relative: the panel is flipped, so "up" is `.minY` there while
        // the non-flipped action row keeps `.maxY`. A hardcoded `.maxY` would open the overlay's
        // menu downward over the footer.
        let panel = makeAccessoryPanel(accessory: makeOverlayAccessory())
        XCTAssertTrue(panel.isFlipped)
        XCTAssertEqual(ComposerReasoningMenuPresenter.upwardEdge(for: panel), .minY)
        XCTAssertEqual(ComposerReasoningMenuPresenter.upwardEdge(for: NSView()), .maxY)
    }

    func testAccessoryViewIdentitySurvivesReconfigure() {
        let panel = makeAccessoryPanel(accessory: makeOverlayAccessory())
        let firstButton = panel.accessoryButton

        // The panel is reconfigured on every ChatView render; a recreated anchor would close the
        // popover the instant a model pick re-renders.
        panel.configure(makeAccessoryConfiguration(accessory: makeOverlayAccessory(selectedModel: "opus")))

        XCTAssertTrue(panel.accessoryButton === firstButton)
    }

    func testAccessoryJoinsKeyViewLoopAfterRowsAndBeforeFooterButtons() {
        let panel = makeAccessoryPanel(accessory: makeOverlayAccessory())
        panel.frame.size.height = panel.measuredHeight(width: 700)
        panel.layoutSubtreeIfNeeded()

        let keyViews = panel.focusableKeyViews
        let accessoryIndex = keyViews.firstIndex { $0 === panel.accessoryButton }
        let dismissIndex = keyViews.firstIndex { $0 === panel.dismissButton }
        let primaryIndex = keyViews.firstIndex { $0 === panel.primaryButton }
        let lastRowIndex = keyViews.lastIndex { view in
            panel.rowViews.contains { $0 === view }
        }

        let accessory = try? XCTUnwrap(accessoryIndex)
        XCTAssertNotNil(accessory)
        if let accessory, let lastRowIndex {
            XCTAssertGreaterThan(accessory, lastRowIndex)
        }
        if let accessory, let dismissIndex, let primaryIndex {
            XCTAssertLessThan(accessory, dismissIndex)
            XCTAssertLessThan(accessory, primaryIndex)
        }
    }

    func testDisabledAccessoryLeavesKeyViewLoop() {
        let panel = makeAccessoryPanel(accessory: makeOverlayAccessory(isEnabled: false))
        panel.frame.size.height = panel.measuredHeight(width: 700)
        panel.layoutSubtreeIfNeeded()

        XCTAssertTrue(panel.accessoryControls.isEmpty)
        XCTAssertFalse(panel.focusableKeyViews.contains { $0 === panel.accessoryButton })
    }

    func testAccessoryForwardsPanelOwnedKeysAndKeepsItsOwnActivationKeys() {
        var dismissCount = 0
        let panel = makeAccessoryPanel(
            accessory: makeOverlayAccessory(),
            onDismiss: { dismissCount += 1 }
        )
        panel.frame.size.height = panel.measuredHeight(width: 700)
        panel.layoutSubtreeIfNeeded()

        // Esc belongs to the panel even while the accessory holds focus.
        panel.accessoryButton.keyDown(with: makeKeyEvent(keyCode: 53))
        XCTAssertEqual(dismissCount, 1)

        // Return activates the dropdown instead of submitting the overlay.
        var activationCount = 0
        panel.accessoryButton.actionHandler = { activationCount += 1 }
        panel.accessoryButton.keyDown(with: makeKeyEvent(keyCode: 36))
        XCTAssertEqual(activationCount, 1)
        XCTAssertEqual(dismissCount, 1)
    }

    func testClearingConfigurationHidesAccessory() {
        let panel = makeAccessoryPanel(accessory: makeOverlayAccessory())
        XCTAssertFalse(panel.accessoryButton.isHidden)

        panel.configure(nil)

        XCTAssertTrue(panel.accessoryButton.isHidden)
        XCTAssertEqual(panel.accessoryButton.frame, .zero)
        XCTAssertFalse(panel.accessoryMenuPresenter.isShown)
    }

    func testDetachingPanelFromWindowClosesAccessoryMenu() {
        let panel = makeAccessoryPanel(accessory: makeOverlayAccessory())
        let popover = NSPopover()
        panel.accessoryMenuPresenter.popover = popover

        panel.viewWillMove(toWindow: nil)

        XCTAssertNil(panel.accessoryMenuPresenter.popover)
    }

    func testAccessoryIsClickReachableThroughOverlayHitTesting() throws {
        // The interaction overlay swallows mouse events that land on its own root, so the accessory
        // is only usable if the panel's hit test resolves it first.
        let overlay = AppKitComposerOverlayView(frame: NSRect(x: 0, y: 0, width: 700, height: 260))
        overlay.configure(
            AppKitComposerOverlayConfiguration(
                id: "exit-plan-mode-accessory",
                panelConfiguration: makeAccessoryConfiguration(accessory: makeOverlayAccessory())
            )
        )
        overlay.frame.size.height = overlay.measuredHeight(width: 700)
        overlay.layoutSubtreeIfNeeded()

        let panel = try XCTUnwrap(
            overlay.subviews.first { $0 is AppKitComposerOverlayPanelView } as? AppKitComposerOverlayPanelView
        )
        let accessoryCenter = panel.convert(
            NSPoint(x: panel.accessoryButton.frame.midX, y: panel.accessoryButton.frame.midY),
            to: overlay
        )

        let hit = overlay.hitTest(accessoryCenter)
        XCTAssertTrue(hit === panel.accessoryButton || hit?.isDescendant(of: panel.accessoryButton) == true)
    }
}

@MainActor
private func makeAccessoryPanel(
    accessory: AppKitComposerOverlayAccessory?,
    onDismiss: @escaping () -> Void = {}
) -> AppKitComposerOverlayPanelView {
    let panel = AppKitComposerOverlayPanelView(frame: NSRect(x: 0, y: 0, width: 700, height: 200))
    panel.configure(makeAccessoryConfiguration(accessory: accessory, onDismiss: onDismiss))
    return panel
}

@MainActor
private func makeAccessoryConfiguration(
    accessory: AppKitComposerOverlayAccessory?,
    onDismiss: @escaping () -> Void = {}
) -> AppKitComposerOverlayPanelView.Configuration {
    AppKitComposerOverlayPanelView.Configuration(
        title: "Implement this plan?",
        rows: [
            makeRowConfiguration(id: "implement", title: "Yes, implement this plan"),
            makeRowConfiguration(id: "deny", title: "No, and tell the agent what to do differently")
        ],
        accessory: accessory,
        primaryTitle: "Submit",
        onDismiss: onDismiss,
        onPrimary: {}
    )
}

@MainActor
private func makeOverlayAccessory(
    selectedModel: String = "sonnet",
    isEnabled: Bool = true
) -> AppKitComposerOverlayAccessory {
    let reasoning = makeReasoningConfiguration(
        modelOptions: [.init(value: "sonnet", title: "Sonnet"), .init(value: "opus", title: "Opus")],
        selectedModel: selectedModel
    )
    return AppKitComposerOverlayAccessory(
        selection: reasoning.selection,
        reasoning: reasoning,
        isEnabled: isEnabled
    )
}

private func makeKeyEvent(keyCode: UInt16) -> NSEvent {
    NSEvent.keyEvent(
        with: .keyDown,
        location: .zero,
        modifierFlags: [],
        timestamp: 0,
        windowNumber: 0,
        context: nil,
        characters: "",
        charactersIgnoringModifiers: "",
        isARepeat: false,
        keyCode: keyCode
        // swiftlint:disable:next force_unwrapping
    )!
}
