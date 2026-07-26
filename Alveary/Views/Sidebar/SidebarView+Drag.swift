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

/// Lines mean ordered insertion; borders mean containers. `Pinned` is manually ordered, so its
/// targets stay insertion boundaries. `Tasks` is activity-sorted, so its target accepts a drop
/// anywhere in the section and renders a border around the whole thing.
enum SidebarDropCandidateKind: Equatable {
    case boundary
    case container
}

struct SidebarDropCandidate: Equatable {
    let target: SidebarDropTarget
    /// Mutable so boundary coalescing can re-place a candidate without rebuilding it — a rebuild
    /// silently drops whichever fields the call site forgets.
    var indicatorY: CGFloat
    var hitFrame: CGRect
    let priority: Int
    var kind: SidebarDropCandidateKind = .boundary
    /// What a container's border draws around, when that differs from where it accepts a drop —
    /// a project group reserves its outer edges for the insertion boundaries that share them, but
    /// the border still has to wrap the whole group.
    var containerFrame: CGRect?
    /// Skips the indicator-proximity gate. The gate keeps an insertion line local to the row that
    /// owns it, so it only means something where neighbouring rows publish competing boundaries.
    /// The empty-`Pinned` target spans a region where nothing else publishes at all.
    var ignoresIndicatorProximity = false

    var borderFrame: CGRect { containerFrame ?? hitFrame }
}

struct SidebarDragLogicalOrder: Equatable {
    let pinnedItems: [SidebarDragItem]
    let regularProjects: [SidebarDragItem]
    let projectsHeaderIsSticky: Bool
    /// Pinned Task threads that may leave `Pinned` via the Tasks-section drop target;
    /// scheduled-attached Tasks are excluded, matching the disabled context-menu Unpin.
    var unpinnableTaskIDs: Set<PersistentIdentifier> = []
    /// The owning project for every Task thread placed in one, pinned or nested. Gates the
    /// `Tasks` pull-out target and suppresses the `.into` target for a Task's own project.
    var projectIDByTaskID: [PersistentIdentifier: PersistentIdentifier] = [:]
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
    /// Last visible top-level row, so the empty-`Pinned` target can reach the region where a
    /// pinned row would appear rather than clinging to the `Projects` header's top edge.
    case topLevelTerminal
    case tasksHeader
    /// Last visible Tasks row (or the empty placeholder), so the section's border can hug content.
    case tasksTerminal
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
    /// Disabling suppresses preference emission without changing view structure, preserving identity during animations.
    func sidebarDragGeometry(
        _ role: SidebarDragGeometryRole,
        isEnabled: Bool = true,
        excludingTopInset topInset: CGFloat = 0
    ) -> some View {
        background {
            GeometryReader { proxy in
                Color.clear.preference(
                    key: SidebarDragGeometryPreferenceKey.self,
                    value: isEnabled
                        ? [role: [sidebarDragGeometryFrame(
                            proxy.frame(in: .named(SidebarDragCoordinateSpace.name)),
                            excludingTopInset: topInset
                        )]]
                        : [:]
                )
            }
        }
    }
}

func sidebarDragGeometryFrame(
    _ frame: CGRect,
    excludingTopInset topInset: CGFloat
) -> CGRect {
    let excludedTopInset = min(max(topInset, 0), frame.height)
    return CGRect(
        x: frame.minX,
        y: frame.minY + excludedTopInset,
        width: frame.width,
        height: frame.height - excludedTopInset
    )
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
                    switch sidebarDropCandidate.kind {
                    case .boundary:
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
                    case .container:
                        let rect = sidebarDragBorderLocalRect(
                            frame: sidebarDropCandidate.borderFrame,
                            viewport: viewport,
                            overlaySize: proxy.size
                        )
                        RoundedRectangle(cornerRadius: AppCornerRadius.standard, style: .continuous)
                            .fill(Color.accentColor.opacity(SidebarDragBorderMetrics.fillOpacity))
                            .overlay {
                                RoundedRectangle(cornerRadius: AppCornerRadius.standard, style: .continuous)
                                    .strokeBorder(
                                        Color.accentColor.opacity(SidebarDragBorderMetrics.strokeOpacity),
                                        lineWidth: SidebarDragBorderMetrics.lineWidth
                                    )
                            }
                            .frame(width: rect.width, height: rect.height)
                            .offset(x: rect.minX, y: rect.minY)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                            .transition(.opacity)
                    }
                }
            }
        }
    }

    func updateSidebarDrag(
        item: SidebarDragItem,
        location: CGPoint,
        logicalOrder: SidebarDragLogicalOrder
    ) {
        switch sidebarDragInteractionState {
        case .idle:
            let previousState = sidebarDragInteractionState
            let nextState = sidebarDragStateAfterPointerChange(
                previousState,
                item: item,
                location: location,
                logicalOrder: logicalOrder,
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
        // Any mode: a Task placed in the dragged project is one of its children too.
        if case .project(let projectID) = session.item,
           case .thread(let selectedThread) = selectedItem {
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
        if let access = sidebarTaskProjectAccessDrop(item: session.item, target: candidate.target) {
            requestTaskProjectAccessDrop(threadID: access.threadID, projectID: access.projectID)
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

enum SidebarDragBorderMetrics {
    // Matches the composer's file-drop overlay so drop affordances read the same app-wide.
    // See `AppKitComposerFileDropOverlayView`; this alpha accent is that documented exception.
    static let fillOpacity: Double = 0.16
    static let strokeOpacity: Double = 0.55
    static let lineWidth: CGFloat = 1.5
    /// Sits outside the 10pt-inset selection pill so a selected row's accent fill stays fully
    /// inside the border instead of tracing the same rectangle.
    static let horizontalInset: CGFloat = 3
}

/// Converts a named-space drag frame into the drag overlay's local coordinates, clamped so a
/// partially scrolled container still renders a border across its visible extent.
func sidebarDragBorderLocalRect(
    frame: CGRect,
    viewport: CGRect,
    overlaySize: CGSize
) -> CGRect {
    let minY = min(max(frame.minY - viewport.minY, 0), max(overlaySize.height, 0))
    let maxY = min(max(frame.maxY - viewport.minY, 0), max(overlaySize.height, 0))
    let width = max(overlaySize.width - SidebarDragBorderMetrics.horizontalInset * 2, 0)
    return CGRect(
        x: SidebarDragBorderMetrics.horizontalInset,
        y: minY,
        width: width,
        height: max(maxY - minY, 0)
    )
}
