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
            geometry: sidebarDragGeometry.frames,
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

    /// Absorbs one `SidebarDragGeometryPreferenceKey` publication.
    ///
    /// Every mounted row, header, and terminal republishes its frame on each layout pass, so this
    /// runs on every frame of a row-removal animation, every scroll tick, and every resize step.
    /// Nothing here may write observed state unconditionally: the frames land in a store `body`
    /// does not observe, and both `@State` writes are equality-guarded. Rows sliding past each
    /// other therefore costs zero rebuilds — only a resize (viewport) or a real targeting change
    /// (candidate) reaches SwiftUI.
    func scheduleSidebarDragGeometryRefresh(with frames: [SidebarDragGeometryRole: [CGRect]]) {
        sidebarDragGeometry.frames = frames
        let scheduledRevision = sidebarDragGeometry.bumpRefreshRevision()

        let viewportFrame = frames[.viewport]?.sidebarUnion
        if viewportFrame != sidebarDragViewportFrame {
            sidebarDragViewportFrame = viewportFrame
        }

        guard case .active(let session) = sidebarDragInteractionState else {
            if sidebarDropCandidate != nil {
                sidebarDropCandidate = nil
            }
            return
        }
        let sessionID = session.id

        // A SwiftUI `List` can publish multiple partial preference maps during one
        // layout pass. Resolve only the newest map so a transient pass cannot blink
        // an otherwise stable indicator off and back on.
        DispatchQueue.main.async {
            guard sidebarDragGeometryRefreshIsCurrent(
                scheduledRevision: scheduledRevision,
                currentRevision: sidebarDragGeometry.refreshRevision,
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

/// Published sidebar drag geometry, deliberately held where `SidebarView.body` cannot observe it.
///
/// These frames churn on every layout pass — each frame of a row-removal animation, each scroll
/// tick, each resize step. As `@State` they invalidated `SidebarView` that often, and because
/// `body` rebuilds `SidebarRenderSnapshot` and every row from scratch, one thread delete cost a
/// double-digit number of full rebuilds and made the removal animation visibly stutter. A `@State`
/// holding a reference whose identity never changes publishes nothing when its contents mutate,
/// and every reader here runs from an event handler — drag targeting, the monitor, the empty-area
/// menu — never from `body`.
///
/// The one geometry `body` does read is the list viewport, mirrored into
/// `SidebarView.sidebarDragViewportFrame`; keep new `body` reads on that same path rather than
/// reaching in here, or the stutter returns.
final class SidebarDragGeometryStore {
    var frames: [SidebarDragGeometryRole: [CGRect]] = [:]
    private(set) var refreshRevision: UInt64 = 0

    /// Stamps this publication and returns its revision, which a coalesced resolution compares
    /// against `refreshRevision` to tell whether a newer map has landed since it was scheduled.
    /// Discarding the result is how a caller invalidates every resolution already in flight.
    @discardableResult
    func bumpRefreshRevision() -> UInt64 {
        refreshRevision &+= 1
        return refreshRevision
    }
}
