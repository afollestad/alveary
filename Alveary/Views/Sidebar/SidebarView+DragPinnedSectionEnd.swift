import SwiftUI

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
