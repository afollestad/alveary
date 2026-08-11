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

    /// Routes the frozen drop once drag state is cleared: `.into` access grants go to the async
    /// confirmation flow; everything else — reorders, pins, and the owning-project unpin — rides
    /// the synchronous commit.
    func commitFinalizedSidebarDrop(
        session: SidebarDragSession,
        candidate: SidebarDropCandidate,
        selectedItem: SidebarItem?
    ) {
        if let access = sidebarTaskProjectAccessDrop(
            item: session.item,
            target: candidate.target,
            logicalOrder: session.logicalOrder
        ) {
            requestTaskProjectAccessDrop(threadID: access.threadID, projectID: access.projectID)
            return
        }
        let selectedThreadBelongsToDraggedProject: Bool
        // Any mode: a Task placed in the dragged project is one of its children too.
        if case .project(let projectID) = session.item,
           case .thread(let selectedThread) = selectedItem {
            selectedThreadBelongsToDraggedProject = selectedThread.project?.persistentModelID == projectID
        } else {
            selectedThreadBelongsToDraggedProject = false
        }

        do {
            let didMove = try viewModel.commitSidebarDrop(
                dragItem: session.item,
                target: candidate.target
            )
            guard didMove else {
                return
            }

            // A collapsed section hides the row the drop just landed, for the same reason a
            // collapsed project would.
            if let section = SidebarCollapsibleSection(dropSection: candidate.target.section) {
                collapsedSections.remove(section)
            }
            // The only `.into` drop the synchronous commit accepts is the owning-project unpin,
            // which lands the row inside that group — expand it so a collapsed project does not
            // swallow the drop.
            if candidate.target.placement == .into,
               case .project(let projectID) = candidate.target.item,
               let project = projects.first(where: { $0.persistentModelID == projectID }) {
                revealProject(project)
            }
            if selectedThreadBelongsToDraggedProject,
               case .project(let projectID) = session.item,
               let project = projects.first(where: { $0.persistentModelID == projectID }) {
                revealProject(project)
            }
            syncExpansionWithSelection(selectedItem)
        } catch {
            viewModel.presentSidebarError(error)
        }
    }
}
