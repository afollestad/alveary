import SwiftData
import SwiftUI

enum SidebarDragInteractionState: Equatable {
    case idle
    case active(SidebarDragSession)
    case cancelledUntilMouseUp(UUID)
}
struct SidebarDragSession: Equatable {
    let id: UUID
    let item: SidebarDragItem
    private let context: SidebarDragSessionContext

    init(
        id: UUID,
        item: SidebarDragItem,
        location: CGPoint,
        logicalOrder: SidebarDragLogicalOrder
    ) {
        self.id = id
        self.item = item
        context = SidebarDragSessionContext(location: location, logicalOrder: logicalOrder)
    }

    var location: CGPoint {
        get { context.location }
        nonmutating set { context.location = newValue }
    }

    var logicalOrder: SidebarDragLogicalOrder {
        context.logicalOrder
    }

    var hasFrozenDropCandidate: Bool {
        context.hasFrozenDropCandidate
    }

    var frozenDropCandidate: SidebarDropCandidate? {
        context.frozenDropCandidate
    }

    func freezeDropCandidate(_ candidate: SidebarDropCandidate?) {
        context.freezeDropCandidate(candidate)
    }

    var hasMonitorPointerLocation: Bool {
        context.hasMonitorPointerLocation
    }

    func updateMonitorPointerLocation(_ location: CGPoint) {
        context.location = location
        context.hasMonitorPointerLocation = true
    }

    static func == (lhs: SidebarDragSession, rhs: SidebarDragSession) -> Bool {
        lhs.id == rhs.id && lhs.item == rhs.item
    }
}

struct SidebarRowDragConfiguration {
    let isEnabled: Bool
    let onChanged: (CGPoint) -> Void
    let onEnded: (CGPoint) -> Void
}

struct SidebarDropCandidate: Equatable {
    let target: SidebarDropTarget
    let indicatorY: CGFloat
    let hitFrame: CGRect
    let priority: Int
}

struct SidebarDragLogicalOrder: Equatable {
    let pinnedItems: [SidebarDragItem]
    let regularProjects: [SidebarDragItem]
    let projectsHeaderIsSticky: Bool
}

struct SidebarDragFinalizationTransition {
    let session: SidebarDragSession?
    let nextState: SidebarDragInteractionState
}

func sidebarDragStateAfterPointerChange(
    _ state: SidebarDragInteractionState,
    item: SidebarDragItem,
    location: CGPoint,
    logicalOrder: SidebarDragLogicalOrder,
    newSessionID: UUID
) -> SidebarDragInteractionState {
    switch state {
    case .idle:
        return .active(SidebarDragSession(
            id: newSessionID,
            item: item,
            location: location,
            logicalOrder: logicalOrder
        ))
    case .active(let session) where session.item == item:
        return .active(session)
    case .active, .cancelledUntilMouseUp:
        return state
    }
}

func sidebarDragStateAfterEscape(_ state: SidebarDragInteractionState) -> SidebarDragInteractionState {
    guard case .active(let session) = state else {
        return state
    }
    return .cancelledUntilMouseUp(session.id)
}

func sidebarDragTransitionStartsSession(
    previousState: SidebarDragInteractionState,
    nextState: SidebarDragInteractionState
) -> Bool {
    guard previousState == .idle, case .active = nextState else {
        return false
    }
    return true
}

func sidebarDragStateAfterCancelledMouseUp(_ state: SidebarDragInteractionState) -> SidebarDragInteractionState {
    guard case .cancelledUntilMouseUp = state else {
        return state
    }
    return .idle
}

func sidebarDragFinalizationTransition(
    state: SidebarDragInteractionState,
    sessionID: UUID
) -> SidebarDragFinalizationTransition {
    guard case .active(let session) = state, session.id == sessionID else {
        return SidebarDragFinalizationTransition(session: nil, nextState: state)
    }
    return SidebarDragFinalizationTransition(session: session, nextState: .idle)
}

enum SidebarDragGeometryRole: Hashable {
    case projectHeader(SidebarDropSection, PersistentIdentifier)
    case projectTerminal(SidebarDropSection, PersistentIdentifier)
    case pinnedThread(PersistentIdentifier)
    case pinnedTask(PersistentIdentifier)
    case pinnedHeader
    case projectsHeader
    case viewport
}

struct SidebarDragGeometryPreferenceKey: PreferenceKey {
    static let defaultValue: [SidebarDragGeometryRole: [CGRect]] = [:]

    static func reduce(
        value: inout [SidebarDragGeometryRole: [CGRect]],
        nextValue: () -> [SidebarDragGeometryRole: [CGRect]]
    ) {
        for (role, frames) in nextValue() {
            value[role, default: []].append(contentsOf: frames)
        }
    }
}

extension View {
    func sidebarDragGeometry(_ role: SidebarDragGeometryRole) -> some View {
        background {
            GeometryReader { proxy in
                Color.clear.preference(
                    key: SidebarDragGeometryPreferenceKey.self,
                    value: [role: [proxy.frame(in: .named(SidebarDragCoordinateSpace.name))]]
                )
            }
        }
    }
}

extension SidebarView {
    static let sidebarDragCoordinateSpaceName = SidebarDragCoordinateSpace.name

    var isSidebarDragInteractionInFlight: Bool {
        sidebarDragInteractionState != .idle
    }

    var activeSidebarDragItem: SidebarDragItem? {
        guard case .active(let session) = sidebarDragInteractionState else {
            return nil
        }
        return session.item
    }

    var sidebarDragAnimation: Animation? {
        accessibilityReduceMotion ? nil : .easeInOut(duration: 0.16)
    }

    var sidebarDragLogicalOrder: SidebarDragLogicalOrder {
        let pinnedItems = pinnedItems()
        return SidebarDragLogicalOrder(
            pinnedItems: pinnedItems.map(\.dragItem),
            regularProjects: regularProjects.map { .project($0.persistentModelID) },
            projectsHeaderIsSticky: pinnedItems.isEmpty
        )
    }

    @ViewBuilder
    var sidebarDragOverlay: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                SidebarDragMonitor(
                    interactionState: sidebarDragInteractionState,
                    onPointerMoved: handleSidebarMonitorPointerMoved,
                    onAutoscroll: handleSidebarMonitorAutoscroll,
                    onMouseUp: handleSidebarMonitorMouseUp,
                    onEscape: cancelSidebarDragFromEscape,
                    onWindowInvalidated: cancelSidebarDragForTeardown
                )
                .frame(width: proxy.size.width, height: proxy.size.height)

                if let sidebarDropCandidate,
                   let viewport = sidebarDragGeometryFrames[.viewport]?.sidebarUnion {
                    Rectangle()
                        .fill(AppAccentFill.primary)
                        .frame(width: max(proxy.size.width - 20, 0), height: 2)
                        .offset(
                            x: 10,
                            y: sidebarDragIndicatorOffset(
                                indicatorY: sidebarDropCandidate.indicatorY,
                                viewport: viewport,
                                overlayHeight: proxy.size.height
                            )
                        )
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                        .transition(.opacity)
                }
            }
        }
    }

    func projectDragConfiguration(for project: Project) -> SidebarRowDragConfiguration? {
        guard editingThreadID == nil else {
            return nil
        }

        let item = SidebarDragItem.project(project.persistentModelID)
        return SidebarRowDragConfiguration(
            isEnabled: sidebarDragSourceIsEnabled(item),
            onChanged: { location in
                updateSidebarDrag(item: item, location: location)
            },
            onEnded: { location in
                finishSidebarDragGesture(item: item, location: location)
            }
        )
    }

    func pinnedItemDragConfiguration(for thread: AgentThread) -> SidebarRowDragConfiguration? {
        switch thread.effectiveMode {
        case .project:
            return pinnedThreadDragConfiguration(for: thread)
        case .task:
            return pinnedTaskDragConfiguration(for: thread)
        }
    }

    func pinnedItemDragGeometryRole(for thread: AgentThread) -> SidebarDragGeometryRole {
        switch thread.effectiveMode {
        case .project:
            return .pinnedThread(thread.persistentModelID)
        case .task:
            return .pinnedTask(thread.persistentModelID)
        }
    }

    private func pinnedThreadDragConfiguration(for thread: AgentThread) -> SidebarRowDragConfiguration? {
        guard editingThreadID == nil,
              thread.effectiveMode == .project,
              thread.isPinned,
              !thread.isDraft,
              thread.archivedAt == nil,
              thread.project?.isPinned != true else {
            return nil
        }

        let item = SidebarDragItem.pinnedThread(thread.persistentModelID)
        return SidebarRowDragConfiguration(
            isEnabled: sidebarDragSourceIsEnabled(item),
            onChanged: { location in
                updateSidebarDrag(item: item, location: location)
            },
            onEnded: { location in
                finishSidebarDragGesture(item: item, location: location)
            }
        )
    }

    private func pinnedTaskDragConfiguration(for thread: AgentThread) -> SidebarRowDragConfiguration? {
        guard editingThreadID == nil,
              thread.effectiveMode == .task,
              thread.isPinned,
              !thread.isDraft,
              thread.archivedAt == nil else {
            return nil
        }

        let item = SidebarDragItem.pinnedTask(thread.persistentModelID)
        return SidebarRowDragConfiguration(
            isEnabled: sidebarDragSourceIsEnabled(item),
            onChanged: { location in
                updateSidebarDrag(item: item, location: location)
            },
            onEnded: { location in
                finishSidebarDragGesture(item: item, location: location)
            }
        )
    }

    func sidebarDragSourceIsEnabled(_ item: SidebarDragItem) -> Bool {
        switch sidebarDragInteractionState {
        case .idle:
            return true
        case .active(let session):
            return session.item == item
        case .cancelledUntilMouseUp:
            return false
        }
    }

    func updateSidebarDrag(item: SidebarDragItem, location: CGPoint) {
        switch sidebarDragInteractionState {
        case .idle:
            let previousState = sidebarDragInteractionState
            let nextState = sidebarDragStateAfterPointerChange(
                previousState,
                item: item,
                location: location,
                logicalOrder: sidebarDragLogicalOrder,
                newSessionID: UUID()
            )
            if sidebarDragTransitionStartsSession(previousState: previousState, nextState: nextState) {
                claimSidebarFocus()
            }
            sidebarDragInteractionState = nextState
            guard case .active(let session) = nextState,
                  let monitorLocation = sidebarDragPointerRelay.pendingMonitorLocation,
                  let viewport = sidebarDragGeometryFrames[.viewport]?.sidebarUnion else {
                sidebarDragPointerRelay.pendingMonitorLocation = nil
                sidebarDropCandidate = nil
                return
            }
            sidebarDragPointerRelay.pendingMonitorLocation = nil
            let namedLocation = sidebarDragLocationInNamedSpace(
                monitorLocation: monitorLocation,
                viewport: viewport
            )
            session.updateMonitorPointerLocation(namedLocation)
            updateSidebarDropCandidate(location: namedLocation, dragging: item)
        case .active(let session) where session.item == item:
            return
        case .active:
            return
        case .cancelledUntilMouseUp:
            return
        }
    }

    func finishSidebarDragGesture(item: SidebarDragItem, location _: CGPoint) {
        switch sidebarDragInteractionState {
        case .active(let session) where session.item == item:
            finalizeSidebarDrag(sessionID: session.id)
        case .cancelledUntilMouseUp:
            withAnimation(sidebarDragAnimation) {
                sidebarDragGeometryMissToken = nil
                sidebarDragInteractionState = sidebarDragStateAfterCancelledMouseUp(sidebarDragInteractionState)
                sidebarDropCandidate = nil
            }
        default:
            break
        }
    }

    func finalizeSidebarDrag(sessionID: UUID) {
        let transition = sidebarDragFinalizationTransition(
            state: sidebarDragInteractionState,
            sessionID: sessionID
        )
        guard let session = transition.session else {
            return
        }

        freezeSidebarDropCandidateForCompletion(session)
        let candidate = session.frozenDropCandidate
        let selectedItem = appState.selectedSidebarItem
        let selectedThreadBelongsToDraggedProject: Bool
        if case .project(let projectID) = session.item,
           case .thread(let selectedThread) = selectedItem,
           selectedThread.effectiveMode == .project {
            selectedThreadBelongsToDraggedProject = selectedThread.project?.persistentModelID == projectID
        } else {
            selectedThreadBelongsToDraggedProject = false
        }

        withAnimation(sidebarDragAnimation) {
            sidebarDragGeometryMissToken = nil
            sidebarDragInteractionState = transition.nextState
            sidebarDropCandidate = nil
        }
        guard let candidate else {
            return
        }

        do {
            let didMove = try viewModel.commitSidebarDrop(
                dragItem: session.item,
                target: candidate.target
            )
            guard didMove else {
                return
            }

            if selectedThreadBelongsToDraggedProject,
               case .project(let projectID) = session.item,
               let project = projects.first(where: { $0.persistentModelID == projectID }) {
                expandedProjects.insert(project.path)
            }
            syncExpansionWithSelection(selectedItem)
        } catch {
            viewModel.presentSidebarError(error)
        }
    }

    func freezeSidebarDropCandidateForCompletion(_ session: SidebarDragSession) {
        guard !session.hasFrozenDropCandidate else {
            return
        }
        session.freezeDropCandidate(sidebarDropCandidate)
        sidebarDragGeometryRefreshRevision &+= 1
        sidebarDragGeometryMissToken = nil
    }
}

private final class SidebarDragSessionContext {
    var location: CGPoint
    let logicalOrder: SidebarDragLogicalOrder
    var hasMonitorPointerLocation = false
    private(set) var hasFrozenDropCandidate = false
    private(set) var frozenDropCandidate: SidebarDropCandidate?

    init(location: CGPoint, logicalOrder: SidebarDragLogicalOrder) {
        self.location = location
        self.logicalOrder = logicalOrder
    }

    func freezeDropCandidate(_ candidate: SidebarDropCandidate?) {
        guard !hasFrozenDropCandidate else {
            return
        }
        hasFrozenDropCandidate = true
        frozenDropCandidate = candidate
    }
}

func sidebarDragIndicatorOffset(
    indicatorY: CGFloat,
    viewport: CGRect,
    overlayHeight: CGFloat
) -> CGFloat {
    let centeredOffset = indicatorY - viewport.minY - 1
    return min(max(centeredOffset, 0), max(overlayHeight - 2, 0))
}
