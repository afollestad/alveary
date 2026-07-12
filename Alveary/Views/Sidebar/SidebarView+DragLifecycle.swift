import SwiftUI

extension SidebarView {
    func handleSidebarMonitorPointerMoved(_ location: CGPoint) {
        switch sidebarDragInteractionState {
        case .idle:
            sidebarDragPointerRelay.pendingMonitorLocation = location
        case .active(let session):
            guard let viewport = sidebarDragGeometryFrames[.viewport]?.sidebarUnion else {
                return
            }
            let namedLocation = sidebarDragLocationInNamedSpace(
                monitorLocation: location,
                viewport: viewport
            )
            let shouldRefreshCandidate = !session.hasMonitorPointerLocation
                || abs(namedLocation.x - session.location.x) > 0.5
                || abs(namedLocation.y - session.location.y) > 0.5
            session.updateMonitorPointerLocation(namedLocation)
            if shouldRefreshCandidate {
                updateSidebarDropCandidate(location: namedLocation, dragging: session.item)
            }
        case .cancelledUntilMouseUp:
            break
        }
    }

    func handleSidebarMonitorMouseUp(_ location: CGPoint) {
        switch sidebarDragInteractionState {
        case .active(let session):
            guard let viewport = sidebarDragGeometryFrames[.viewport]?.sidebarUnion else {
                clearSidebarDragState()
                return
            }
            let namedLocation = sidebarDragLocationInNamedSpace(
                monitorLocation: location,
                viewport: viewport
            )
            let shouldRefreshCandidate = !session.hasMonitorPointerLocation
                || abs(namedLocation.x - session.location.x) > 0.5
                || abs(namedLocation.y - session.location.y) > 0.5
            session.updateMonitorPointerLocation(namedLocation)
            if shouldRefreshCandidate {
                updateSidebarDropCandidate(location: namedLocation, dragging: session.item)
            }
            freezeSidebarDropCandidateForCompletion(session)
            let sessionID = session.id
            // Give SwiftUI's source gesture its normal completion opportunity. If the
            // source was virtualized, this root-owned fallback still commits exactly once.
            DispatchQueue.main.async {
                finalizeSidebarDrag(sessionID: sessionID)
            }
        case .cancelledUntilMouseUp(let sessionID):
            DispatchQueue.main.async {
                guard case .cancelledUntilMouseUp(sessionID) = sidebarDragInteractionState else {
                    return
                }
                clearSidebarDragState()
            }
        case .idle:
            sidebarDragPointerRelay.pendingMonitorLocation = nil
        }
    }

    func cancelSidebarDragFromEscape() {
        let nextState = sidebarDragStateAfterEscape(sidebarDragInteractionState)
        guard nextState != sidebarDragInteractionState else {
            return
        }
        sidebarDragGeometryMissToken = nil
        sidebarDragPointerRelay.pendingMonitorLocation = nil
        sidebarDropCandidate = nil
        sidebarDragInteractionState = nextState
    }

    func cancelSidebarDragForTeardown() {
        clearSidebarDragState()
    }

    func clearSidebarDragState() {
        withAnimation(sidebarDragAnimation) {
            sidebarDragGeometryMissToken = nil
            sidebarDragPointerRelay.pendingMonitorLocation = nil
            sidebarDragInteractionState = .idle
            sidebarDropCandidate = nil
        }
    }

    func cancelSidebarDragIfSourceIsMissing(visibleItems: Set<SidebarDragItem>) {
        guard case .active(let session) = sidebarDragInteractionState,
              !visibleItems.contains(session.item) else {
            return
        }
        clearSidebarDragState()
    }
}
