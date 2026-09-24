import AppKit
import SwiftUI
import XCTest

@testable import Alveary

/// Drives the selector through its presenter's seams only: `AlvearyTests/AGENTS.md` forbids live `NSPopover` tests.
@MainActor
final class SettingsAgentSelectorTests: XCTestCase {
    func testPressPresentsThroughThePresenter() {
        let coordinator = makeCoordinator()
        let window = mount(coordinator.button)
        var presentationCount = 0
        coordinator.presenter.presentationOverride = { presentationCount += 1 }

        XCTAssertTrue(coordinator.button.accessibilityPerformPress())
        XCTAssertEqual(presentationCount, 1)
        XCTAssertEqual(coordinator.button.accessibilityLabel(), "Agent")
        XCTAssertEqual(coordinator.button.debugDisplayedModelTitle, "Claude · Opus 5.5")
        window.close()
    }

    func testPopoverAnchorsToTheWindowContentViewAtTheButtonsFrame() throws {
        let coordinator = makeCoordinator()
        XCTAssertNil(coordinator.popoverAnchor)
        let window = mount(coordinator.button)
        let contentView = try XCTUnwrap(window.contentView)

        let anchor = try XCTUnwrap(coordinator.popoverAnchor)

        XCTAssertTrue(anchor.view === contentView)
        XCTAssertEqual(anchor.rect, coordinator.button.convert(coordinator.button.bounds, to: contentView))
        window.close()
    }

    func testCheckingAndUnavailablePresentationsCannotPresent() {
        var checking = makeAgentReasoningPresentation()
        checking.isChecking = true
        let unavailable = makeAgentReasoningPresentation(harnesses: [])

        for (presentation, title) in [(checking, "Checking harnesses…"), (unavailable, "No ready harnesses")] {
            let coordinator = makeCoordinator(presentation: presentation)
            var presentationCount = 0
            coordinator.presenter.presentationOverride = { presentationCount += 1 }

            XCTAssertFalse(coordinator.button.accessibilityPerformPress())
            XCTAssertEqual(presentationCount, 0)
            XCTAssertEqual(coordinator.button.debugDisplayedModelTitle, title)
        }
    }

    func testOpenMenuTakesPresentationChangesOnTheNextMainQueueTurn() async throws {
        let pinned = makeAgentReasoningPresentation(inheritance: makeAgentReasoningInheritance(isOffered: true))
        let coordinator = makeCoordinator(presentation: pinned)
        let controller = ComposerReasoningMenuViewController(
            configuration: ReasoningConfiguration(presentation: pinned) { _ in true },
            onRequestCloseMainMenu: {},
            reducesMotion: { false }
        )
        controller.loadViewIfNeeded()
        controller.setModelsExpanded(true)
        coordinator.presenter.controller = controller
        XCTAssertNil(try XCTUnwrap(controller.debugModelList?.debugInheritRow).debugTrailingIconName)

        coordinator.update(accessibilityLabel: "Agent", presentation: pinned.applying(.inherited), apply: { _ in true })

        XCTAssertEqual(coordinator.button.debugDisplayedModelTitle, "Default (Codex · GPT-6-Astra)")
        XCTAssertNil(controller.debugModelList?.debugInheritRow?.debugTrailingIconName)
        await waitForNextMainQueueTurn()
        XCTAssertEqual(controller.debugModelList?.debugInheritRow?.debugTrailingIconName, "checkmark")
    }

    func testCloseReleasesTheInstalledPopover() {
        let coordinator = makeCoordinator()
        coordinator.presenter.popover = NSPopover()

        coordinator.close()

        XCTAssertNil(coordinator.presenter.popover)
    }

    func testSizesToContentUnconstrainedAndFillsAProposedWidth() throws {
        let host = NSHostingView(rootView: SettingsAgentSelector(
            accessibilityLabel: "Agent",
            presentation: makeAgentReasoningPresentation(),
            apply: { _ in true }
        ))
        host.layoutSubtreeIfNeeded()
        let button = try XCTUnwrap(reasoningButton(in: host))
        XCTAssertEqual(host.fittingSize.width, button.intrinsicContentSize.width, accuracy: 0.5)
        XCTAssertEqual(host.fittingSize.height, SettingsScreenLayout.settingsControlSurfaceHeight)

        host.frame = NSRect(x: 0, y: 0, width: 400, height: SettingsScreenLayout.settingsControlSurfaceHeight)
        host.layoutSubtreeIfNeeded()
        XCTAssertEqual(button.frame.width, 400, accuracy: 0.5)
    }

    private func makeCoordinator(
        presentation: AgentReasoningPresentation = makeAgentReasoningPresentation()
    ) -> SettingsAgentSelector.Coordinator {
        let coordinator = SettingsAgentSelector.Coordinator()
        coordinator.update(accessibilityLabel: "Agent", presentation: presentation, apply: { _ in true })
        return coordinator
    }

    private func mount(_ button: NSView) -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 100), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        button.frame = NSRect(x: 120, y: 30, width: 200, height: SettingsScreenLayout.settingsControlSurfaceHeight)
        window.contentView?.addSubview(button)
        return window
    }

    private func reasoningButton(in view: NSView) -> ComposerReasoningButton? {
        (view as? ComposerReasoningButton) ?? view.subviews.lazy.compactMap(reasoningButton(in:)).first
    }

    private func waitForNextMainQueueTurn() async {
        let turn = expectation(description: "next main-queue turn")
        DispatchQueue.main.async { turn.fulfill() }
        await fulfillment(of: [turn], timeout: 1)
    }
}
