import SwiftUI

enum SidebarDropCandidateUpdateReason {
    case pointer
    case geometry
}

extension SidebarView {
    func handleSidebarMonitorAutoscroll() {
        refreshSidebarDropCandidateForCurrentPointer(reason: .geometry)
    }

    func refreshSidebarDropCandidateForCurrentPointer(
        reason: SidebarDropCandidateUpdateReason = .pointer
    ) {
        guard case .active(let session) = sidebarDragInteractionState,
              session.hasMonitorPointerLocation else {
            sidebarDragGeometryMissToken = nil
            sidebarDropCandidate = nil
            return
        }
        updateSidebarDropCandidate(location: session.location, dragging: session.item, reason: reason)
    }

    func updateSidebarDropCandidate(
        location: CGPoint,
        dragging item: SidebarDragItem,
        reason: SidebarDropCandidateUpdateReason = .pointer
    ) {
        guard case .active(let session) = sidebarDragInteractionState,
              session.item == item else {
            sidebarDragGeometryMissToken = nil
            sidebarDropCandidate = nil
            return
        }
        let candidate = sidebarDropCandidateForLocation(
            at: location,
            dragging: item,
            geometry: sidebarDragGeometryFrames,
            logicalOrder: session.logicalOrder,
            retainingTarget: sidebarDropCandidate?.target
        )
        if reason == .geometry,
           let currentCandidate = sidebarDropCandidate,
           candidate?.target != currentCandidate.target {
            scheduleSidebarDragGeometryMissClear(sessionID: session.id)
            return
        }
        sidebarDragGeometryMissToken = nil
        guard candidate != sidebarDropCandidate else {
            return
        }
        if candidate != nil, sidebarDropCandidate != nil {
            sidebarDropCandidate = candidate
        } else {
            withAnimation(sidebarDragAnimation) {
                sidebarDropCandidate = candidate
            }
        }
    }

    func scheduleSidebarDragGeometryRefresh(with frames: [SidebarDragGeometryRole: [CGRect]]) {
        sidebarDragGeometryFrames = frames
        sidebarDragGeometryRefreshRevision &+= 1
        let scheduledRevision = sidebarDragGeometryRefreshRevision

        guard case .active(let session) = sidebarDragInteractionState else {
            sidebarDropCandidate = nil
            return
        }
        let sessionID = session.id

        // A SwiftUI `List` can publish multiple partial preference maps during one
        // layout pass. Resolve only the newest map so a transient pass cannot blink
        // an otherwise stable indicator off and back on.
        DispatchQueue.main.async {
            guard sidebarDragGeometryRefreshIsCurrent(
                scheduledRevision: scheduledRevision,
                currentRevision: sidebarDragGeometryRefreshRevision,
                sessionID: sessionID,
                state: sidebarDragInteractionState
            ) else {
                return
            }
            refreshSidebarDropCandidateForCurrentPointer(reason: .geometry)
        }
    }

    private func scheduleSidebarDragGeometryMissClear(sessionID: UUID) {
        guard sidebarDragGeometryMissToken == nil else {
            return
        }
        let token = UUID()
        sidebarDragGeometryMissToken = token

        // Do not extend this grace period when more incomplete maps arrive. A
        // complete map cancels the token; a real vanished boundary clears shortly.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            guard sidebarDragGeometryMissToken == token,
                  case .active(let session) = sidebarDragInteractionState,
                  session.id == sessionID else {
                return
            }
            sidebarDragGeometryMissToken = nil
            refreshSidebarDropCandidateForCurrentPointer(reason: .pointer)
        }
    }
}

func sidebarDragGeometryRefreshIsCurrent(
    scheduledRevision: UInt64,
    currentRevision: UInt64,
    sessionID: UUID,
    state: SidebarDragInteractionState
) -> Bool {
    guard scheduledRevision == currentRevision,
          case .active(let currentSession) = state else {
        return false
    }
    return currentSession.id == sessionID
}
