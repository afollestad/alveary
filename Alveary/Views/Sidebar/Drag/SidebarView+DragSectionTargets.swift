import SwiftUI

/// The boundaries a dragged section may land on: one before each visible section, plus one after
/// the last. Sections are the only source whose targets live entirely between other sections —
/// a section is never a container, and never drops inside one.
///
/// Each `.before` boundary claims its header's upper half, the same half-row claim every row
/// boundary makes. Where the preceding section publishes a terminal, coalescing then centers the
/// line in the gap and extends the hit region up to it; where it publishes none (`Pinned`,
/// `Projects`), the line stays on the header's own top edge.
///
/// The trailing `.end` boundary is the exception: it anchors on the last section's whole rendered
/// extent rather than a half-row, because "after everything" is a place the pointer reaches by
/// leaving the rows entirely.
func sidebarSectionReorderCandidates(
    dragging item: SidebarDragItem,
    geometry: [SidebarDragGeometryRole: [CGRect]],
    viewport: CGRect,
    logicalOrder: SidebarDragLogicalOrder
) -> [SidebarDropCandidate] {
    guard case .section = item else {
        return []
    }
    let sections = logicalOrder.sections
    var candidates: [SidebarDropCandidate] = []

    for (index, sectionItem) in sections.enumerated() {
        guard let sectionID = sectionItem.sectionID,
              let headerFrame = geometry[.sectionHeader(sectionID)]?.sidebarUnion else {
            continue
        }
        if let candidate = sidebarSectionCandidate(
            target: SidebarDropTarget(section: .sectionList, item: sectionItem, placement: .before),
            indicatorY: headerFrame.minY,
            hitFrame: headerFrame.sidebarUpperHalf,
            viewport: viewport,
            priority: 0
        ) {
            candidates.append(candidate)
        }
        guard index == sections.count - 1 else {
            continue
        }
        let anchorFrame = sidebarSectionAppendAnchorFrame(
            sectionID: sectionID,
            headerFrame: headerFrame,
            geometry: geometry,
            logicalOrder: logicalOrder
        )
        guard let endCandidate = sidebarSectionCandidate(
            target: SidebarDropTarget(section: .sectionList, item: nil, placement: .end),
            indicatorY: anchorFrame.maxY,
            hitFrame: sidebarSectionAppendHitFrame(anchorFrame: anchorFrame, viewport: viewport),
            viewport: viewport,
            // Nothing else publishes below the last section during a section drag, so the gate
            // that keeps an insertion line local to its own row has nothing to arbitrate here.
            ignoresIndicatorProximity: true
        ) else {
            continue
        }
        candidates.append(endCandidate)
    }
    return candidates
}

/// Everything the last section rendered, header through last row — the extent the append boundary
/// anchors on.
///
/// `Tasks` and custom sections publish a terminal role from their last row; `Pinned` and
/// `Projects` publish none, because their per-project and per-thread rows publish their own. This
/// used to fall back to the header alone for those two, which drew the append line under that
/// header and *above the section's own rows* — reading as a drop into the section rather than
/// after it. A collapsed or empty section publishes no rows, and there the header really is the
/// section's whole extent.
private func sidebarSectionAppendAnchorFrame(
    sectionID: SidebarSectionID,
    headerFrame: CGRect,
    geometry: [SidebarDragGeometryRole: [CGRect]],
    logicalOrder: SidebarDragLogicalOrder
) -> CGRect {
    let rowFrames: [CGRect]
    switch sectionID {
    case .tasks, .custom:
        rowFrames = SidebarDragGeometryRole.sectionTerminal(sectionID).flatMap { geometry[$0] } ?? []
    case .pinned:
        rowFrames = sidebarSectionRowTerminalFrames(logicalOrder.pinnedItems, section: .pinned, geometry: geometry)
    case .projects:
        rowFrames = sidebarSectionRowTerminalFrames(logicalOrder.regularProjects, section: .projects, geometry: geometry)
    }
    // Union the header in as well: virtualization can unmount the rows that would otherwise set
    // this frame's top edge, and an anchor above its own header would invert the hit region.
    return ([headerFrame] + rowFrames).sidebarUnion ?? headerFrame
}

private func sidebarSectionRowTerminalFrames(
    _ items: [SidebarDragItem],
    section: SidebarDropSection,
    geometry: [SidebarDragGeometryRole: [CGRect]]
) -> [CGRect] {
    items.compactMap { sidebarItemBoundaryFrames(for: $0, section: section, geometry: geometry).terminal }
}

/// The append boundary's reach: the last section's lower half, plus the empty area beneath it
/// where a section dropped after everything is naturally released.
private func sidebarSectionAppendHitFrame(anchorFrame: CGRect, viewport: CGRect) -> CGRect {
    let minY = anchorFrame.midY
    let maxY = max(anchorFrame.maxY, viewport.maxY)
    return CGRect(x: anchorFrame.minX, y: minY, width: anchorFrame.width, height: maxY - minY)
}

/// Where a section reorder actually lands: the section it should sit before, or nil to append.
///
/// Dropping a section on its own boundary — or on the one immediately after it — leaves the order
/// unchanged, so both resolve to no move rather than a redundant commit.
func sidebarSectionReorderAnchor(
    dragging item: SidebarDragItem,
    target: SidebarDropTarget,
    sections: [SidebarDragItem]
) -> SidebarSectionReorderRequest? {
    guard case .section(let movingID) = item,
          target.section == .sectionList,
          let movingIndex = sections.firstIndex(of: item) else {
        return nil
    }
    let insertionIndex: Int
    switch target.placement {
    case .before:
        guard let anchorItem = target.item,
              let anchorIndex = sections.firstIndex(of: anchorItem) else {
            return nil
        }
        insertionIndex = anchorIndex
    case .end:
        insertionIndex = sections.count
    case .after, .into:
        return nil
    }
    guard insertionIndex != movingIndex, insertionIndex != movingIndex + 1 else {
        return nil
    }
    var remaining = sections
    remaining.remove(at: movingIndex)
    let adjustedIndex = insertionIndex > movingIndex ? insertionIndex - 1 : insertionIndex
    let anchorID = adjustedIndex < remaining.count ? remaining[adjustedIndex].sectionID : nil
    return SidebarSectionReorderRequest(sectionID: movingID, beforeSectionID: anchorID)
}

/// A resolved section reorder: move `sectionID` before `beforeSectionID`, or to the end when nil.
struct SidebarSectionReorderRequest: Equatable {
    let sectionID: SidebarSectionID
    let beforeSectionID: SidebarSectionID?
}
