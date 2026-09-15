import AppKit
import SwiftData
import SwiftUI
import XCTest

@testable import Alveary

@MainActor
final class PullRequestReviewTeamValidationViewTests: XCTestCase {
    func testValidationCompletionKeepsTheMountedEquatablePaneReadyAcrossReopens() async throws {
        let gates = ReviewTeamValidationViewGates()
        defer { gates.releaseAll() }
        let fixture = await makeFixture(gates: gates)

        try await withMountedPane(fixture) { host in
            try await host.requireChecking()
            let generation = fixture.viewModel.paneSessions[fixture.target]?.generation

            gates.validators[0].open()

            try await host.requireReady()
            for _ in 0..<5 {
                fixture.viewModel.requestDetails(fixture.target.identifier, origin: .screen)
                XCTAssertEqual(fixture.viewModel.paneSessions[fixture.target]?.pullRequestReviewTeamValidationStatus, .valid)
                XCTAssertNil(fixture.viewModel.reviewTeamValidationTask)
                try await host.requireReady()
            }
            XCTAssertEqual(gates.validationCalls, 1)
            XCTAssertEqual(gates.deadlineCalls, 1)
            XCTAssertEqual(gates.refreshCalls, 0)
            XCTAssertEqual(fixture.viewModel.paneSessions[fixture.target]?.generation, generation)
        }
    }

    func testTimeoutCanBeRetriedFromTheMountedPaneWithoutNavigation() async throws {
        let gates = ReviewTeamValidationViewGates()
        defer { gates.releaseAll() }
        let fixture = await makeFixture(gates: gates)

        try await withMountedPane(fixture) { host in
            try await host.requireChecking()
            let generation = fixture.viewModel.paneSessions[fixture.target]?.generation

            // Leave the validator suspended to prove timeout does not await its cancellation.
            gates.deadlines[0].open()

            try await host.requireRendered {
                host.hasText("Review team check timed out. Try again.")
                    && host.buttonEnabled("Retry") == true
                    && host.buttonEnabled("Review with team") == false
            }
            XCTAssertFalse(host.hasText("Checking review team settings…"))

            try host.clickButton("Retry")
            try await host.requireChecking()
            await waitFor { gates.validationCalls == 2 }
            XCTAssertEqual(gates.refreshCalls, 1)
            XCTAssertFalse(host.hasText("Review team check timed out. Try again."))

            gates.validators[1].open()

            try await host.requireReady()
            XCTAssertEqual(gates.validationCalls, 2)
            XCTAssertEqual(fixture.viewModel.paneSessions[fixture.target]?.generation, generation)
        }
    }

    private func makeFixture(gates: ReviewTeamValidationViewGates) async -> ReviewTeamValidationViewFixture {
        let settings = InMemorySettingsService()
        settings.update { $0.pullRequestReviewMode = .reviewTeam }
        let service = StubPullRequestsService()
        let summary = makePullRequestSummary(number: 7)
        service.detailResult = .success(makePullRequestDetail(id: summary.id, viewerCanUpdate: true))
        service.diffResult = .success(makeUnifiedDiffFixture(fileCount: 1))
        let viewModel = makePullRequestsViewModel(
            service: service,
            settingsService: settings,
            reviewTeamSettingsValidator: { _ in await gates.validate() },
            reviewTeamValidationSleeper: { await gates.waitForDeadline() },
            refreshReviewTeamHarnessDiscovery: { gates.refreshDiscovery() }
        )
        viewModel.requestDetails(summary)
        let target = PullRequestPaneTarget.details(summary.id)
        await waitForPaneContent(viewModel, target: target)
        return ReviewTeamValidationViewFixture(viewModel: viewModel, target: target)
    }

    /// Keep the root mounted throughout the assertions; replace it only to unregister SwiftData observations at teardown.
    private func withMountedPane(
        _ fixture: ReviewTeamValidationViewFixture,
        operation: (ReviewTeamValidationPaneHost) async throws -> Void
    ) async throws {
        let container = try PullRequestPaneSnapshots.makeModelContainer()
        let host = try ReviewTeamValidationPaneHost(fixture: fixture, container: container)
        do {
            try await operation(host)
        } catch {
            host.close()
            await awaitSnapshotHostTeardown(retaining: container)
            throw error
        }
        host.close()
        await awaitSnapshotHostTeardown(retaining: container)
    }
}

@MainActor
private struct ReviewTeamValidationViewFixture {
    let viewModel: PullRequestsViewModel
    let target: PullRequestPaneTarget
}

/// Separate non-cancellable gates keep the original attempt suspended through timeout and Retry.
@MainActor
private final class ReviewTeamValidationViewGates {
    let validators = [PullRequestsServiceGate(), PullRequestsServiceGate()]
    let deadlines = [PullRequestsServiceGate(), PullRequestsServiceGate()]
    private(set) var validationCalls = 0
    private(set) var deadlineCalls = 0
    private(set) var refreshCalls = 0

    func refreshDiscovery() {
        refreshCalls += 1
    }

    func validate() async {
        let index = validationCalls
        validationCalls += 1
        guard validators.indices.contains(index) else {
            return XCTFail("Unexpected extra validation attempt")
        }
        await validators[index].wait()
    }

    func waitForDeadline() async {
        let index = deadlineCalls
        deadlineCalls += 1
        guard deadlines.indices.contains(index) else {
            return XCTFail("Unexpected extra validation deadline")
        }
        await deadlines[index].wait()
    }

    func releaseAll() {
        (validators + deadlines).forEach { $0.open() }
    }
}

/// Mirrors the contextual lane's identity and equality boundaries while observing the actual rendered controls.
@MainActor
private final class ReviewTeamValidationPaneHost {
    private let controller: NSHostingController<AnyView>
    private let window: NSWindow
    private let previousEnhancedInterface: Any
    private let enhancedInterface = "AXEnhancedUserInterface" as NSString

    init(fixture: ReviewTeamValidationViewFixture, container: ModelContainer) throws {
        let application = NSApplication.shared
        previousEnhancedInterface = try XCTUnwrap(application.perform(
            NSSelectorFromString("accessibilityAttributeValue:"), with: enhancedInterface
        )?.takeUnretainedValue())
        _ = application.perform(
            NSSelectorFromString("accessibilitySetValue:forAttribute:"), with: true as NSNumber, with: enhancedInterface
        )
        let viewModel = fixture.viewModel
        let generation = viewModel.paneSessions[fixture.target]?.generation
        let lane = ResizableRightPane(
            destination: fixture.target,
            width: .constant(460),
            onWidthCommit: { _ in },
            presentationGeneration: { _ in generation },
            onDismiss: { _, _ in },
            mainContent: { Color.clear },
            paneContent: { target, dismiss in
                PullRequestPane(viewModel: viewModel, target: target, onDismiss: dismiss)
                    .equatable()
            }
        )
        let size = CGSize(width: 900, height: 700)
        controller = NSHostingController(rootView: AnyView(lane.modelContainer(container)))
        controller.view.frame = CGRect(origin: .zero, size: size)
        window = NSWindow(
            contentRect: CGRect(origin: CGPoint(x: -3_000, y: -3_000), size: size),
            styleMask: [.borderless], backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentViewController = controller
        window.orderFront(nil)
        layout()
    }

    func close() {
        closeSnapshotWindow(window, controller: controller)
        _ = NSApplication.shared.perform(
            NSSelectorFromString("accessibilitySetValue:forAttribute:"),
            with: previousEnhancedInterface, with: enhancedInterface
        )
    }

    func requireChecking(file: StaticString = #filePath, line: UInt = #line) async throws {
        try await requireRendered(file: file, line: line) {
            self.hasText("Checking review team settings…") && self.buttonEnabled("Review with team") == false
        }
    }

    func requireReady(file: StaticString = #filePath, line: UInt = #line) async throws {
        try await requireRendered(file: file, line: line) {
            !self.hasText("Checking review team settings…")
                && !self.hasText("Review team check timed out. Try again.")
                && self.buttonEnabled("Review with team") == true
                && self.buttonEnabled("Retry") == nil
        }
    }

    func requireRendered(
        file: StaticString = #filePath,
        line: UInt = #line,
        condition: () -> Bool
    ) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        repeat {
            layout()
            if condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        } while ContinuousClock.now < deadline
        let labels = accessibilityNodes(in: controller.view).flatMap(accessibilityText)
        _ = try XCTUnwrap(
            condition() ? true : nil,
            "Mounted pane did not reach the expected state. Accessibility text: \(labels)",
            file: file, line: line
        )
    }

    func hasText(_ text: String) -> Bool {
        accessibilityNodes(in: controller.view).contains { accessibilityText($0).contains(text) }
    }

    func buttonEnabled(_ title: String) -> Bool? {
        guard let button = button(title), button.responds(to: NSSelectorFromString("isAccessibilityEnabled")) else {
            return nil
        }
        // KVC boxes the Boolean result; perform(_:) is only safe for object-returning selectors.
        return button.value(forKey: "accessibilityEnabled") as? Bool
    }

    func clickButton(_ title: String) throws {
        let button = try XCTUnwrap(button(title))
        XCTAssertEqual(buttonEnabled(title), true)
        let frame = try XCTUnwrap(button.value(forKey: "accessibilityFrame") as? NSValue).rectValue
        XCTAssertFalse(frame.isEmpty)
        let point = window.convertPoint(fromScreen: NSPoint(x: frame.midX, y: frame.midY))
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            let event = try XCTUnwrap(NSEvent.mouseEvent(
                with: type, location: point, modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber, context: nil, eventNumber: 0,
                clickCount: 1, pressure: type == .leftMouseDown ? 1 : 0
            ))
            window.sendEvent(event)
        }
    }

    private func button(_ title: String) -> NSObject? {
        accessibilityNodes(in: controller.view).first {
            accessibilityString($0, selector: "accessibilityRole") == NSAccessibility.Role.button.rawValue
                && accessibilityText($0).contains(title)
        }
    }

    private func layout() {
        window.layoutIfNeeded()
        window.displayIfNeeded()
        controller.view.layoutSubtreeIfNeeded()
    }

    private func accessibilityText(_ node: NSObject) -> [String] {
        ["accessibilityLabel", "accessibilityTitle", "accessibilityValue"].compactMap {
            accessibilityString(node, selector: $0)
        }
    }

    private func accessibilityString(_ node: NSObject, selector name: String) -> String? {
        let selector = NSSelectorFromString(name)
        return node.responds(to: selector) ? node.perform(selector)?.takeUnretainedValue() as? String : nil
    }

    private func accessibilityNodes(in element: Any, depth: Int = 0) -> [NSObject] {
        guard depth < 30, let node = element as? NSObject else { return [] }
        // SwiftUI's virtual nodes expose selectors without conforming to NSAccessibilityProtocol.
        let selector = NSSelectorFromString("accessibilityChildren")
        let children = node.responds(to: selector) ? node.perform(selector)?.takeUnretainedValue() as? [Any] : nil
        return [node] + (children ?? []).flatMap { accessibilityNodes(in: $0, depth: depth + 1) }
    }
}
