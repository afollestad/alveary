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

/// A row's drag gesture wiring plus the values `==` needs to prove that wiring current.
///
/// The closures are excluded from equality: each captures exactly the `item` and `logicalOrder`
/// compared here plus the view's `@State`-backed drag entry points, so a closure can never be
/// staler than the values beside it. Comparing `logicalOrder` is load-bearing for the `Equatable`
/// rows that hold a configuration — a row whose body is skipped keeps its installed gesture, and
/// without this comparison that gesture would seed a drag session with an order the list no
/// longer renders.
struct SidebarRowDragConfiguration: Equatable {
    let item: SidebarDragItem
    let isEnabled: Bool
    let logicalOrder: SidebarDragLogicalOrder
    // `@MainActor` keeps the whole struct `Sendable`, which the rows' nonisolated `==` needs
    // just to read this property — gestures already deliver on the main actor.
    let onChanged: @MainActor (CGPoint) -> Void
    let onEnded: @MainActor (CGPoint) -> Void

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.item == rhs.item
            && lhs.isEnabled == rhs.isEnabled
            && lhs.logicalOrder == rhs.logicalOrder
    }
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
    /// Two targets span regions where nothing else publishes at all: the empty-`Pinned` target,
    /// and the section list's append boundary reaching into the space below the last section.
    var ignoresIndicatorProximity = false

    var borderFrame: CGRect { containerFrame ?? hitFrame }
}

struct SidebarDragLogicalOrder: Equatable {
    let pinnedItems: [SidebarDragItem]
    let regularProjects: [SidebarDragItem]
    /// Pinned Task threads that may leave `Pinned` via the Tasks-section drop target. A scheduled
    /// attachment excludes nothing: a schedule owns where it posts, never where the row renders.
    var unpinnableTaskIDs: Set<PersistentIdentifier> = []
    /// The owning project for every Task thread placed in one, pinned or nested. Gates the
    /// `Tasks` pull-out target and scopes a Task's own project's `.into` target to the unpin drop.
    var projectIDByTaskID: [PersistentIdentifier: PersistentIdentifier] = [:]
    /// The owning project for every standalone pinned Project-mode thread that may unpin by
    /// dropping onto that project group. The drop is the drag mirror of context-menu Unpin, which
    /// no scheduled attachment disables.
    var owningProjectIDByPinnedThreadID: [PersistentIdentifier: PersistentIdentifier] = [:]
    /// The custom section every member Task belongs to. Gates each section's membership
    /// container, so a Task never sees the section it is already in.
    var customSectionIDByTaskID: [PersistentIdentifier: String] = [:]
    /// Every rendered section as a `.section` drag item, in the order the user sees. A hidden
    /// empty `Pinned` is absent — it has no header to grab — and keeps its persisted slot,
    /// which `SidebarSectionService.moveSection` preserves by anchoring on visible neighbours.
    var sections: [SidebarDragItem] = []
    /// Every section in persisted order, hidden `Pinned` included. Distinct from `sections`
    /// because the hidden-`Pinned` drop target has to know which section follows that empty slot.
    var sectionOrder: [SidebarSectionID] = []
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

extension SidebarView {
    static let sidebarDragCoordinateSpaceName = SidebarDragCoordinateSpace.name

    /// Whether a row drag is being tracked. Every row affordance and action has to respect it:
    /// hover chrome, press feedback, and tap actions suppress themselves, expansion and section
    /// toggles abort, `handleSidebarKeyPress` swallows the key, and the thread-order animation
    /// stops.
    ///
    /// A row that ignores this fires on the mouse-up that ends the drag — `appSelectableRow`
    /// detects clicks with a zero-distance `DragGesture`, so the release that commits a drop is
    /// also a tap as far as the row underneath is concerned.
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
                    onPointerLost: cancelSidebarDragForTeardown,
                    onWindowInvalidated: cancelSidebarDragForTeardown
                )
                .frame(width: proxy.size.width, height: proxy.size.height)

                if let sidebarDropCandidate,
                   let viewport = sidebarDragViewportFrame {
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
                        sidebarSectionContainerBorder(
                            frame: sidebarDropCandidate.borderFrame,
                            viewport: viewport,
                            overlaySize: proxy.size
                        )
                        .transition(.opacity)
                    }
                }

                // No transition: the menu this accompanies pops instantly, and a fade would
                // trail it. The two are exclusive anyway — a drag in flight declines the menu.
                if let highlight = sidebarSectionSecondaryClickHighlight,
                   let viewport = sidebarDragViewportFrame {
                    sidebarSectionContainerBorder(
                        frame: highlight.frame,
                        viewport: viewport,
                        overlaySize: proxy.size
                    )
                }
            }
        }
    }

    /// The whole-section outline, shared by a drop container and by the section whose
    /// secondary-click menu is open, so the two are the same pixels by construction.
    private func sidebarSectionContainerBorder(
        frame: CGRect,
        viewport: CGRect,
        overlaySize: CGSize
    ) -> some View {
        let rect = sidebarDragBorderLocalRect(frame: frame, viewport: viewport, overlaySize: overlaySize)
        return RoundedRectangle(cornerRadius: AppCornerRadius.standard, style: .continuous)
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
                  let viewport = sidebarDragViewportFrame else {
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
        withAnimation(sidebarDragAnimation) {
            sidebarDragGeometryMissToken = nil
            sidebarDragInteractionState = transition.nextState
            sidebarDropCandidate = nil
        }
        guard let candidate else {
            return
        }
        commitFinalizedSidebarDrop(session: session, candidate: candidate, selectedItem: selectedItem)
    }

    func freezeSidebarDropCandidateForCompletion(_ session: SidebarDragSession) {
        guard !session.hasFrozenDropCandidate else {
            return
        }
        session.freezeDropCandidate(sidebarDropCandidate)
        sidebarDragGeometry.bumpRefreshRevision()
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
