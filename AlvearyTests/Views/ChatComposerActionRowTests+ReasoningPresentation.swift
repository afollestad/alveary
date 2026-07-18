import AppKit
import XCTest

@testable import Alveary

@MainActor
extension ChatComposerActionRowTests {
    func testReasoningPresentationRequestWaitsForMountFocusesPresentsAndDeduplicates() async {
        let request = UUID()
        let row = ChatComposerActionRowView(frame: NSRect(x: 0, y: 0, width: 480, height: 30))
        var presentationCount = 0
        var focusedWhenPresented = false
        var effortFocusCount = 0
        var presentationCountWhenEffortFocused = 0
        var consumedRequests: [UUID] = []
        row.reasoningMenuPresentationOverride = { [weak row] in
            guard let row else { return }
            presentationCount += 1
            focusedWhenPresented = row.window?.firstResponder === row.reasoningButton
        }
        row.reasoningMenuEffortFocusOverride = {
            effortFocusCount += 1
            presentationCountWhenEffortFocused = presentationCount
        }
        var configuration = makeConfiguration(mode: .idle)
        configuration.reasoningMenuPresentationRequest = request
        configuration.onReasoningMenuRequestConsumed = { consumedRequests.append($0) }

        row.configure(configuration)

        XCTAssertEqual(presentationCount, 0)
        XCTAssertTrue(consumedRequests.isEmpty)

        let window = NSWindow(
            contentRect: row.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.contentView = row
        row.layoutSubtreeIfNeeded()
        await Task.yield()

        XCTAssertEqual(presentationCount, 1)
        XCTAssertTrue(focusedWhenPresented)
        XCTAssertEqual(effortFocusCount, 1)
        XCTAssertEqual(presentationCountWhenEffortFocused, 1)
        XCTAssertTrue(window.firstResponder === row.reasoningButton)
        XCTAssertEqual(consumedRequests, [request])

        row.configure(configuration)

        XCTAssertEqual(presentationCount, 1)
        XCTAssertEqual(effortFocusCount, 1)
        XCTAssertEqual(consumedRequests, [request])
    }

    func testDisabledReasoningPresentationRequestIsDiscardedBeforeMount() async {
        let request = UUID()
        let row = ChatComposerActionRowView(frame: NSRect(x: 0, y: 0, width: 480, height: 30))
        var presentationCount = 0
        var effortFocusCount = 0
        var consumedRequests: [UUID] = []
        row.reasoningMenuPresentationOverride = { presentationCount += 1 }
        row.reasoningMenuEffortFocusOverride = { effortFocusCount += 1 }
        var disabledConfiguration = makeConfiguration(mode: .idle, areControlsDisabled: true)
        disabledConfiguration.reasoningMenuPresentationRequest = request
        disabledConfiguration.onReasoningMenuRequestConsumed = { consumedRequests.append($0) }

        row.configure(disabledConfiguration)
        await Task.yield()

        XCTAssertEqual(presentationCount, 0)
        XCTAssertEqual(effortFocusCount, 0)
        XCTAssertEqual(consumedRequests, [request])

        var enabledConfiguration = makeConfiguration(mode: .idle)
        enabledConfiguration.reasoningMenuPresentationRequest = request
        enabledConfiguration.onReasoningMenuRequestConsumed = { consumedRequests.append($0) }
        row.configure(enabledConfiguration)
        let window = NSWindow(
            contentRect: row.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.contentView = row

        XCTAssertEqual(presentationCount, 0)
        XCTAssertEqual(effortFocusCount, 0)
        XCTAssertEqual(consumedRequests, [request])
    }

    func testReasoningPresentationRequestDoesNotToggleShownMenuClosed() async {
        let request = UUID()
        let row = ChatComposerActionRowView(frame: NSRect(x: 0, y: 0, width: 480, height: 30))
        let window = NSWindow(
            contentRect: row.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.contentView = row
        row.reasoningMenuIsPresentedOverride = { true }
        var fallbackPresentationCount = 0
        var effortFocusCount = 0
        var consumedRequests: [UUID] = []
        row.reasoningMenuPresentationOverride = { fallbackPresentationCount += 1 }
        row.reasoningMenuEffortFocusOverride = { effortFocusCount += 1 }
        var configuration = makeConfiguration(mode: .idle)
        configuration.reasoningMenuPresentationRequest = request
        configuration.onReasoningMenuRequestConsumed = { consumedRequests.append($0) }

        row.configure(configuration)
        await Task.yield()

        XCTAssertNil(row.reasoningPopover)
        XCTAssertEqual(fallbackPresentationCount, 0)
        XCTAssertEqual(effortFocusCount, 1)
        XCTAssertEqual(consumedRequests, [request])
        XCTAssertTrue(window.firstResponder === row.reasoningButton)
    }

    func testReasoningButtonUsesSharedPresentationPath() {
        let row = ChatComposerActionRowView(frame: NSRect(x: 0, y: 0, width: 480, height: 30))
        var presentationCount = 0
        var effortFocusCount = 0
        row.reasoningMenuPresentationOverride = { presentationCount += 1 }
        row.reasoningMenuEffortFocusOverride = { effortFocusCount += 1 }
        row.configure(makeConfiguration(mode: .idle))

        XCTAssertTrue(row.reasoningButton.accessibilityPerformPress())
        XCTAssertEqual(presentationCount, 1)
        XCTAssertEqual(effortFocusCount, 0)
    }
}
