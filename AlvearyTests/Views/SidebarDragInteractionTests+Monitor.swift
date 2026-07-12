import AppKit
import SwiftData
import XCTest

@testable import Alveary

@MainActor
extension SidebarDragInteractionTests {
    func testMonitorPolicyFiltersOtherWindowsAndRoutesPointerLifecycle() throws {
        let session = try makeMonitorTestSession(itemKind: .project)
        let active = SidebarDragInteractionState.active(session)
        let cancelled = SidebarDragInteractionState.cancelledUntilMouseUp(session.id)

        XCTAssertEqual(monitorAction(.leftMouseDragged, state: active, originatesInWindow: false), .passThrough)
        XCTAssertEqual(monitorAction(.leftMouseUp, state: active, originatesInWindow: false), .passThrough)
        XCTAssertEqual(monitorAction(.keyDown, keyCode: 53, state: active, originatesInWindow: false), .passThrough)

        XCTAssertEqual(monitorAction(.leftMouseDragged, state: .idle), .pointerMoved)
        XCTAssertEqual(monitorAction(.leftMouseDragged, state: active), .pointerMoved)
        XCTAssertEqual(monitorAction(.leftMouseDragged, state: cancelled), .passThrough)

        XCTAssertEqual(monitorAction(.leftMouseUp, state: .idle), .mouseUp)
        XCTAssertEqual(monitorAction(.leftMouseUp, state: active), .mouseUp)
        XCTAssertEqual(monitorAction(.leftMouseUp, state: cancelled), .mouseUp)
        XCTAssertEqual(monitorAction(.leftMouseDown, state: active), .passThrough)
    }

    func testMonitorPolicyConsumesDragKeysAndRoutesEscapeForBothSources() throws {
        let projectSession = try makeMonitorTestSession(itemKind: .project)
        let threadSession = try makeMonitorTestSession(itemKind: .pinnedThread)
        let suppressedKeyCodes: [UInt16] = [36, 51, 76, 117, 123, 124, 125, 126]

        for session in [projectSession, threadSession] {
            let active = SidebarDragInteractionState.active(session)
            let cancelled = SidebarDragInteractionState.cancelledUntilMouseUp(session.id)
            XCTAssertEqual(monitorAction(.keyDown, keyCode: 53, state: active), .escape)
            XCTAssertEqual(monitorAction(.keyDown, keyCode: 53, state: cancelled), .consumeKey)

            for keyCode in suppressedKeyCodes {
                XCTAssertEqual(monitorAction(.keyDown, keyCode: keyCode, state: active), .consumeKey)
                XCTAssertEqual(monitorAction(.keyDown, keyCode: keyCode, state: cancelled), .consumeKey)
            }
            XCTAssertEqual(monitorAction(.keyDown, keyCode: 0, state: active), .passThrough)
        }

        XCTAssertEqual(monitorAction(.keyDown, keyCode: 53, state: .idle), .passThrough)
        XCTAssertEqual(monitorAction(.keyDown, keyCode: 126, state: .idle), .passThrough)
    }

    func testMonitorMouseUpRoutingFeedsIdempotentFinalization() throws {
        let session = try makeMonitorTestSession(itemKind: .project)
        XCTAssertEqual(monitorAction(.leftMouseUp, state: .active(session)), .mouseUp)

        let first = sidebarDragFinalizationTransition(state: .active(session), sessionID: session.id)
        let duplicate = sidebarDragFinalizationTransition(state: first.nextState, sessionID: session.id)

        XCTAssertEqual(first.session, session)
        XCTAssertNil(duplicate.session)
    }

    func testAutoscrollSessionPolicyStopsOutsideActiveEdgeInteraction() throws {
        let session = try makeMonitorTestSession(itemKind: .project)
        let replacement = try makeMonitorTestSession(itemKind: .project)
        let viewport = CGRect(x: 0, y: 0, width: 200, height: 200)
        let edge = CGPoint(x: 100, y: 1)
        let center = CGPoint(x: 100, y: 100)

        XCTAssertEqual(autoscrollSessionID(state: .active(session), pointer: edge, viewport: viewport), session.id)
        XCTAssertEqual(autoscrollSessionID(state: .active(replacement), pointer: edge, viewport: viewport), replacement.id)
        XCTAssertNil(autoscrollSessionID(state: .active(session), pointer: center, viewport: viewport))
        XCTAssertNil(autoscrollSessionID(state: .active(session), pointer: nil, viewport: viewport))
        XCTAssertNil(autoscrollSessionID(state: .cancelledUntilMouseUp(session.id), pointer: edge, viewport: viewport))
        XCTAssertNil(autoscrollSessionID(state: .idle, pointer: edge, viewport: viewport))
    }

    private func makeMonitorTestSession(itemKind: SidebarMonitorTestItemKind) throws -> SidebarDragSession {
        let fixture = try SidebarTestFixture()
        let model = try fixture.insertProject(name: UUID().uuidString, path: "/tmp/\(UUID().uuidString)")
        let item: SidebarDragItem = switch itemKind {
        case .project:
            .project(model.persistentModelID)
        case .pinnedThread:
            .pinnedThread(model.persistentModelID)
        }
        return SidebarDragSession(
            id: UUID(),
            item: item,
            location: CGPoint(x: 100, y: 100),
            logicalOrder: SidebarDragLogicalOrder(
                pinnedItems: [],
                regularProjects: [],
                projectsHeaderIsSticky: true
            )
        )
    }

    private func monitorAction(
        _ eventType: NSEvent.EventType,
        keyCode: UInt16 = 0,
        state: SidebarDragInteractionState,
        originatesInWindow: Bool = true
    ) -> SidebarDragMonitorAction {
        sidebarDragMonitorAction(
            eventType: eventType,
            keyCode: keyCode,
            interactionState: state,
            originatesInWindow: originatesInWindow
        )
    }

    private func autoscrollSessionID(
        state: SidebarDragInteractionState,
        pointer: CGPoint?,
        viewport: CGRect
    ) -> UUID? {
        sidebarAutoscrollSessionID(
            interactionState: state,
            pointerLocation: pointer,
            viewport: viewport
        )
    }
}

private enum SidebarMonitorTestItemKind {
    case project
    case pinnedThread
}
