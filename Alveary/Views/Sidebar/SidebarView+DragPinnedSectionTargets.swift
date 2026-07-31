import SwiftUI

/// Everything the `Pinned` section itself offers a source: one container for a Task arriving from
/// `Tasks`, otherwise the section's start and end insertion boundaries. The container is exclusive
/// by construction — it scores a perfect hit across the whole section, so any boundary left
/// alongside it would be unreachable.
func sidebarPinnedSectionCandidates(
    dragging item: SidebarDragItem,
    geometry: [SidebarDragGeometryRole: [CGRect]],
    projectsHeaderFrame: CGRect?,
    viewport: CGRect,
    logicalOrder: SidebarDragLogicalOrder
) -> [SidebarDropCandidate] {
    if sidebarPinnedSectionIsContainerTarget(dragging: item, logicalOrder: logicalOrder) {
        // All or nothing: falling back to a boundary here would contradict the suppression every
        // other caller applies. A frame without header geometry is transient, and the
        // geometry-miss grace holds the previous candidate across it.
        return [
            sidebarPinnedSectionContainerCandidate(
                dragging: item,
                geometry: geometry,
                viewport: viewport,
                logicalOrder: logicalOrder
            )
        ].compactMap { $0 }
    }
    guard sidebarSourceCanHoldStandalonePin(item, logicalOrder: logicalOrder) else {
        return []
    }

    var candidates: [SidebarDropCandidate] = []
    if !logicalOrder.pinnedItems.isEmpty,
       let pinnedHeaderFrame = geometry[.pinnedHeader]?.sidebarUnion,
       let sectionStart = sidebarSectionCandidate(
           target: SidebarDropTarget(section: .pinned, item: nil, placement: .before),
           indicatorY: pinnedHeaderFrame.maxY,
           hitFrame: pinnedHeaderFrame.sidebarLowerHalf,
           viewport: viewport
       ) {
        candidates.append(sectionStart)
    }
    if let projectsHeaderFrame,
       let sectionEnd = sidebarPinnedSectionEndCandidate(
           geometry: geometry,
           projectsHeaderFrame: projectsHeaderFrame,
           viewport: viewport,
           logicalOrder: logicalOrder
       ) {
        candidates.append(sectionEnd)
    }
    return candidates
}

/// The `Pinned` section's end target, which doubles as the only way to create the very first pin.
///
/// While `Pinned` has items this is an ordinary insertion boundary at the `Projects` header's top
/// edge, sharing that line with the last pinned item's `.after`. While `Pinned` is empty there is
/// no `Pinned` header to aim at, and the top-level rows above `Projects` publish no geometry at
/// all, so the target additionally claims the last top-level row's lower half — otherwise a drop
/// anywhere in that region finds no candidate and silently no-ops.
func sidebarPinnedSectionEndCandidate(
    geometry: [SidebarDragGeometryRole: [CGRect]],
    projectsHeaderFrame: CGRect,
    viewport: CGRect,
    logicalOrder: SidebarDragLogicalOrder
) -> SidebarDropCandidate? {
    let pinnedIsEmpty = logicalOrder.pinnedItems.isEmpty
    return sidebarSectionCandidate(
        target: SidebarDropTarget(section: .pinned, item: nil, placement: .end),
        indicatorY: projectsHeaderFrame.minY,
        hitFrame: pinnedIsEmpty
            ? sidebarHiddenPinnedHitFrame(
                projectsHeaderFrame: projectsHeaderFrame,
                geometry: geometry,
                viewport: viewport
            )
            : projectsHeaderFrame.sidebarUpperHalf,
        viewport: viewport,
        priority: -1,
        // Only the hidden target spans a region without competing boundaries; once `Pinned` has
        // items this line is local to the last one, like every other insertion boundary.
        ignoresIndicatorProximity: pinnedIsEmpty
    )
}

/// A Task arriving from `Tasks` is choosing membership, not position, so it takes the whole
/// `Pinned` section as one container — the same affordance `Tasks` offers for the reverse trip —
/// and pins at the end. Sources already inside `Pinned` keep their insertion boundaries, because
/// reordering against their neighbours is the only thing they are for.
func sidebarPinnedSectionContainerCandidate(
    dragging item: SidebarDragItem,
    geometry: [SidebarDragGeometryRole: [CGRect]],
    viewport: CGRect,
    logicalOrder: SidebarDragLogicalOrder
) -> SidebarDropCandidate? {
    guard sidebarPinnedSectionIsContainerTarget(dragging: item, logicalOrder: logicalOrder),
          let headerFrame = geometry[.pinnedHeader]?.sidebarUnion else {
        return nil
    }
    let sectionFrame = sidebarSectionContainerFrame(
        headerFrame: headerFrame,
        contentFrames: logicalOrder.pinnedItems.flatMap { pinnedItem -> [CGRect] in
            let frames = sidebarItemBoundaryFrames(
                for: pinnedItem,
                section: .pinned,
                geometry: geometry
            )
            return [frames.header, frames.terminal].compactMap { $0 }
        }
    )
    return sidebarSectionCandidate(
        target: SidebarDropTarget(section: .pinned, item: nil, placement: .end),
        indicatorY: sectionFrame.midY,
        hitFrame: sectionFrame,
        viewport: viewport,
        // Higher than `.into` so a pinned project group nested inside still wins its own drop;
        // both score 0 while the pointer is inside, so this tie-break is what separates them.
        priority: 3,
        kind: .container
    )
}

/// Whether `Pinned` presents itself as one container rather than a set of insertion boundaries.
/// Callers must suppress its boundaries when this holds, or the container would eclipse them
/// anyway by scoring a perfect hit across the whole section.
///
/// Sources arriving from outside `Pinned` — an unpinned Task from `Tasks`, or a project-nested
/// Project-mode thread pinning itself — are choosing membership, not position, so the whole
/// section is one appending target for both.
func sidebarPinnedSectionIsContainerTarget(
    dragging item: SidebarDragItem,
    logicalOrder: SidebarDragLogicalOrder
) -> Bool {
    switch item {
    case .unpinnedTask, .projectThread:
        break
    case .project, .pinnedThread, .pinnedTask:
        return false
    }
    guard !logicalOrder.pinnedItems.isEmpty else {
        return false
    }
    return sidebarSourceCanHoldStandalonePin(item, logicalOrder: logicalOrder)
}

/// Claims the last top-level row's lower half — the same half-row every other insertion boundary
/// takes — so the hidden target covers where a pinned row would actually appear.
private func sidebarHiddenPinnedHitFrame(
    projectsHeaderFrame: CGRect,
    geometry: [SidebarDragGeometryRole: [CGRect]],
    viewport: CGRect
) -> CGRect {
    let upperHalf = projectsHeaderFrame.sidebarUpperHalf
    guard let topLevelTerminal = geometry[.topLevelTerminal]?.sidebarUnion,
          sidebarLineIsVisible(topLevelTerminal.midY, viewport: viewport, stickyOcclusionMaxY: nil),
          // Keeps the constructed rect from inverting if a transient preference map places the row
          // below the header it precedes. Coalescing rejects that map too, one pass later.
          topLevelTerminal.midY < upperHalf.maxY else {
        return upperHalf
    }
    return CGRect(
        x: upperHalf.minX,
        y: topLevelTerminal.midY,
        width: upperHalf.width,
        height: upperHalf.maxY - topLevelTerminal.midY
    )
}
