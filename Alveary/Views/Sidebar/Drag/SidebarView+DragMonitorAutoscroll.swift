import AppKit

/// How fast an edge-band autoscroll should run for a pointer inside the viewport: ramping to
/// `maximumSpeed` toward either edge, `0` in the middle band and for a pointer outside. Split with
/// its session and origin companions from `SidebarView+DragMonitor.swift`, which keeps the event
/// monitor itself under the file-length limit.
func sidebarAutoscrollVelocity(
    location: CGPoint,
    viewport: CGRect,
    edgeBand: CGFloat = 32,
    maximumSpeed: CGFloat = 12
) -> CGFloat {
    guard edgeBand > 0,
          maximumSpeed > 0,
          location.x >= viewport.minX,
          location.x <= viewport.maxX,
          location.y >= viewport.minY,
          location.y <= viewport.maxY else {
        return 0
    }

    let distanceFromTop = location.y - viewport.minY
    if distanceFromTop < edgeBand {
        return -maximumSpeed * (1 - distanceFromTop / edgeBand)
    }

    let distanceFromBottom = viewport.maxY - location.y
    if distanceFromBottom < edgeBand {
        return maximumSpeed * (1 - distanceFromBottom / edgeBand)
    }

    return 0
}

func sidebarAutoscrollSessionID(
    interactionState: SidebarDragInteractionState,
    pointerLocation: CGPoint?,
    viewport: CGRect
) -> UUID? {
    guard case .active(let session) = interactionState,
          let pointerLocation,
          sidebarAutoscrollVelocity(location: pointerLocation, viewport: viewport) != 0 else {
        return nil
    }
    return session.id
}

/// The next clip-view origin for one autoscroll tick. `constrainBoundsRect(_:)` is the clamp on
/// purpose: a zero-based range derived from document and viewport heights looks equivalent and is
/// not, because `List` insets can give a short document a legitimate *negative* resting origin.
@MainActor
func sidebarAutoscrollOriginY(
    contentView: NSClipView,
    velocity: CGFloat,
    documentIsFlipped: Bool
) -> CGFloat {
    let directionalVelocity = documentIsFlipped ? velocity : -velocity
    var proposedBounds = contentView.bounds
    proposedBounds.origin.y += directionalVelocity
    return contentView.constrainBoundsRect(proposedBounds).origin.y
}

func sidebarAutoscrollTickOwnsTimer(tickSessionID: UUID, timerSessionID: UUID?) -> Bool {
    tickSessionID == timerSessionID
}
