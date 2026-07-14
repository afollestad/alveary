import XCTest

@testable import Alveary

@MainActor
extension ConversationControllerRegistryTests {
    func testDelayedApprovalAfterToolDeferredKeepsSameOutcomeWaiting() async throws {
        let fixture = try ConversationViewModelTestFixture()
        let registry = DefaultConversationControllerRegistry(
            makeViewModel: { _ in fixture.viewModel },
            flushTerminalRecords: { _ in },
            suspendRuntime: { _ in },
            runtimeIsSuspended: { _ in true }
        )
        let lease = registry.makeBackgroundLease(for: fixture.conversation)
        lease.activate()
        var outcomes = lease.outcomes().makeAsyncIterator()
        fixture.viewModel.markVisibleTurnStarted()
        fixture.viewModel.turnState.beginTurn()
        let active = await outcomes.next()

        fixture.viewModel.handleEvent(.tokens(
            input: 1,
            output: 1,
            cacheRead: 0,
            isError: false,
            stopReason: "tool_deferred",
            durationMs: 10,
            costUsd: nil,
            permissionDenials: []
        ))
        await Task.yield()
        let approval = ToolApprovalRequest(
            sessionId: "session-1",
            toolUseId: "approval-1",
            toolName: "Bash",
            toolInput: "{}"
        )
        fixture.viewModel.handleEvent(.toolApprovalRequested(approval))

        let waiting = await outcomes.next()
        XCTAssertEqual(waiting?.turn, active?.turn)
        XCTAssertEqual(waiting?.state, .waitingForApproval(interactionID: "approval-1"))
        XCTAssertNil(fixture.viewModel.state.lastControllerTerminalBoundary)
        XCTAssertTrue(fixture.viewModel.state.hasDeferredControllerTerminalBoundary)
        registry.invalidate(for: lease.key)
    }
}
