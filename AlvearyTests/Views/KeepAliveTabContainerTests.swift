import AppKit
import SwiftUI
import XCTest

@testable import Alveary

@MainActor
private final class KeepAliveProbeBox {
    var selectTab: ((String) -> Void)?
    var activeByTab: [String: Bool] = [:]
    var hostRenderCount = 0
}

/// Mirrors a pane: local `@State` selection written by a closure built in `body`, with
/// `.equatable()` children that compare equal across a selection change.
private struct KeepAliveProbeHost: View {
    let box: KeepAliveProbeBox
    @State private var selection = "a"

    var body: some View {
        box.hostRenderCount += 1
        box.selectTab = { selection = $0 }
        return KeepAliveTabContainer(tabs: ["a", "b"], selection: selection) { tab in
            KeepAliveProbeChild(tab: tab, box: box)
                .equatable()
        }
    }
}

private struct KeepAliveProbeChild: View, Equatable {
    let tab: String
    let box: KeepAliveProbeBox
    @Environment(\.keepAliveTabIsActive) private var isActive

    nonisolated static func == (lhs: KeepAliveProbeChild, rhs: KeepAliveProbeChild) -> Bool {
        lhs.tab == rhs.tab && lhs.box === rhs.box
    }

    var body: some View {
        box.activeByTab[tab] = isActive
        return Color.clear
    }
}

@MainActor
final class KeepAliveTabContainerTests: XCTestCase {
    func testSelectionChangeMountsAndActivatesTheNewTab() {
        let box = KeepAliveProbeBox()
        let controller = NSHostingController(rootView: AnyView(KeepAliveProbeHost(box: box)))
        controller.view.frame = CGRect(x: 0, y: 0, width: 300, height: 200)

        let window = NSWindow(
            contentRect: CGRect(x: -3_000, y: -3_000, width: 300, height: 200),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = controller
        window.orderFront(nil)
        window.layoutIfNeeded()
        window.displayIfNeeded()
        defer {
            window.orderOut(nil)
            window.contentViewController = nil
        }

        XCTAssertEqual(box.activeByTab["a"], true, "The initially selected tab should render active")
        XCTAssertNil(box.activeByTab["b"], "An unvisited tab must not mount")

        box.selectTab?("b")
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        window.layoutIfNeeded()
        window.displayIfNeeded()

        // Not an exact count: SwiftUI may coalesce or add passes, and only re-running at
        // all is what this asserts.
        XCTAssertGreaterThan(box.hostRenderCount, 1, "The host body should re-run on a selection write")
        XCTAssertEqual(box.activeByTab["b"], true, "The newly selected tab should be active")
        XCTAssertEqual(
            box.activeByTab["a"],
            false,
            "The deselected tab stayed mounted but never observed keepAliveTabIsActive flipping to false"
        )
    }

    /// Clicks the chips with real mouse events, the way a user does. Switching back is
    /// the pass that matters: the first switch also mounts the second tab, whose state
    /// write buys an extra render, so a chip that only repaints incidentally still looks
    /// correct there.
    func testClickingChipsSwitchesTabsInBothDirections() async throws {
        let size = CGSize(width: 900, height: 400)
        let (window, controller) = try await makeLanePaneHost(size: size)
        defer {
            window.orderOut(nil)
            window.contentViewController = nil
        }

        let before = try snapshotData(controller.view)
        let chipRow = CGRect(x: size.width - 460, y: 64, width: 220, height: 48)
        let beforeChips = try snapshotData(controller.view, in: chipRow)

        // The lane pins the 460pt pane to the trailing edge; the Changes capsule sits
        // ~141pt inside it, below the 64pt header. Window coordinates are bottom-up.
        let chipPoint = NSPoint(x: size.width - 460 + 141, y: size.height - 90)
        try click(at: chipPoint, in: window)

        try await Task.sleep(for: .milliseconds(400))
        window.layoutIfNeeded()
        window.displayIfNeeded()

        let after = try snapshotData(controller.view)
        XCTAssertNotEqual(before, after, "Clicking the Changes chip did not change what the pane renders")

        // The chip row alone: the reported symptom is content switching while the
        // selected-chip highlight stays put, which a full-pane compare would hide.
        XCTAssertNotEqual(
            try snapshotData(controller.view, in: chipRow),
            beforeChips,
            "The tab chip row did not repaint — the selected-state highlight is stale"
        )

        // Switching back must hide the Changes tab again. It is mounted and, being later
        // in the stack, draws over the Overview unless its hide actually applies.
        try click(at: NSPoint(x: size.width - 460 + 56, y: size.height - 90), in: window)
        try await Task.sleep(for: .milliseconds(400))
        window.layoutIfNeeded()
        window.displayIfNeeded()

        XCTAssertEqual(
            try snapshotData(controller.view),
            before,
            "Returning to Overview left the pane rendering the previous selection"
        )
    }

    /// Hosts the pane the way the app does: inside the right-pane lane, which keys it by
    /// presentation identity and re-runs its `GeometryReader` body per frame, with
    /// `.equatable()` on the pane — whose `==` ignores `selectedTab`.
    private func makeLanePaneHost(size: CGSize) async throws -> (NSWindow, NSHostingController<AnyView>) {
        let fixture = await PullRequestPaneSnapshots.makeLoadedFixture()
        let container = try PullRequestPaneSnapshots.makeModelContainer()
        let viewModel = fixture.viewModel
        let target = fixture.target
        let generation = viewModel.paneSessions[target]?.generation
        let lane = ResizableRightPane(
            destination: target,
            width: .constant(460),
            onWidthCommit: { _ in },
            presentationGeneration: { _ in generation },
            onDismiss: { _, _ in },
            mainContent: { Color.clear },
            paneContent: { paneTarget, dismiss in
                PullRequestPane(viewModel: viewModel, target: paneTarget, onDismiss: dismiss)
                    .equatable()
            }
        )
        let controller = NSHostingController(rootView: AnyView(lane.modelContainer(container)))
        controller.view.frame = CGRect(origin: .zero, size: size)

        let window = NSWindow(
            contentRect: CGRect(origin: CGPoint(x: -3_000, y: -3_000), size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = controller
        window.orderFront(nil)
        window.layoutIfNeeded()
        window.displayIfNeeded()
        return (window, controller)
    }

    private func click(at point: NSPoint, in window: NSWindow) throws {
        let mouseDown = try XCTUnwrap(NSEvent.mouseEvent(
            with: .leftMouseDown,
            location: point,
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 1
        ))
        let mouseUp = try XCTUnwrap(NSEvent.mouseEvent(
            with: .leftMouseUp,
            location: point,
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: 1,
            clickCount: 1,
            pressure: 0
        ))
        window.sendEvent(mouseDown)
        window.sendEvent(mouseUp)
    }

    private func snapshotData(_ view: NSView, in rect: CGRect? = nil) throws -> Data {
        let bounds = rect ?? view.bounds
        let rep = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: bounds))
        view.cacheDisplay(in: bounds, to: rep)
        return try XCTUnwrap(rep.representation(using: .png, properties: [:]))
    }
}
