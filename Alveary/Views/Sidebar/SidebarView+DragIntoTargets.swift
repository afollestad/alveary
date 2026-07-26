import SwiftData
import SwiftUI

private struct SidebarIntoTargetSection {
    let section: SidebarDropSection
    let items: [SidebarDragItem]
    let occlusionMaxY: CGFloat?
    /// Whether this section's groups share their outer edges with insertion boundaries this source
    /// can actually reach, and so must band those edges away from the container.
    let reservesBoundaryHalfRows: Bool
}

/// Dropping a Task onto a project converts it into one of that project's threads, so the target is
/// the whole project group — header plus any expanded children — rather than an insertion point.
/// Only Task sources qualify; Projects and Project-mode threads keep pure reordering semantics.
func sidebarProjectIntoDropCandidates(
    dragging item: SidebarDragItem,
    geometry: [SidebarDragGeometryRole: [CGRect]],
    viewport: CGRect,
    stickyOcclusionMaxY: CGFloat?,
    logicalOrder: SidebarDragLogicalOrder
) -> [SidebarDropCandidate] {
    switch item {
    case .project, .pinnedThread:
        return []
    case .pinnedTask, .unpinnedTask:
        break
    }

    // Only `Pinned` publishes insertion boundaries to a Task source, and only while the source can
    // hold a standalone pin and is not taking the section as one container. `Projects` offers a
    // Task nothing to reorder against, so banding its groups any wider would turn reachable
    // `.into` area into dead space.
    let pinnedPublishesBoundaries = sidebarSourceCanHoldStandalonePin(item, logicalOrder: logicalOrder)
        && !sidebarPinnedSectionIsContainerTarget(dragging: item, logicalOrder: logicalOrder)
    let sections = [
        SidebarIntoTargetSection(
            section: .pinned,
            items: logicalOrder.pinnedItems,
            occlusionMaxY: nil,
            reservesBoundaryHalfRows: pinnedPublishesBoundaries
        ),
        SidebarIntoTargetSection(
            section: .projects,
            items: logicalOrder.regularProjects,
            occlusionMaxY: stickyOcclusionMaxY,
            reservesBoundaryHalfRows: false
        )
    ]
    // A Task's own project is not a destination: dropping there could only fail validation.
    let ownProjectID: PersistentIdentifier?
    switch item {
    case .pinnedTask(let threadID), .unpinnedTask(let threadID):
        ownProjectID = logicalOrder.projectIDByTaskID[threadID]
    case .project, .pinnedThread:
        ownProjectID = nil
    }
    return sections.flatMap { entry in
        entry.items.compactMap { candidateItem in
            guard case .project(let projectID) = candidateItem, projectID != ownProjectID else {
                return nil
            }
            return sidebarProjectIntoDropCandidate(
                item: candidateItem,
                entry: entry,
                geometry: geometry,
                viewport: viewport
            )
        }
    }
}

private func sidebarProjectIntoDropCandidate(
    item: SidebarDragItem,
    entry: SidebarIntoTargetSection,
    geometry: [SidebarDragGeometryRole: [CGRect]],
    viewport: CGRect
) -> SidebarDropCandidate? {
    guard case .project(let projectID) = item else {
        return nil
    }
    let section = entry.section
    let frames = sidebarItemBoundaryFrames(for: item, section: section, geometry: geometry)
    guard let groupFrame = [frames.header, frames.terminal].compactMap({ $0 }).sidebarUnion else {
        return nil
    }
    // Leave the group's own outer edges to the insertion boundaries that share them, so a pointer
    // near a project's top or bottom still reorders instead of reparenting.
    guard let bandedFrame = sidebarIntoTargetBandedFrame(
        groupFrame,
        frames: frames,
        reservesBoundaryHalfRows: entry.reservesBoundaryHalfRows
    ),
          let hitFrame = sidebarUnoccludedContainerFrame(
              bandedFrame,
              occlusionMaxY: entry.occlusionMaxY
          ) else {
        return nil
    }
    return sidebarSectionCandidate(
        target: SidebarDropTarget(section: section, item: .project(projectID), placement: .into),
        indicatorY: groupFrame.midY,
        hitFrame: hitFrame,
        viewport: viewport,
        priority: 2,
        kind: .container,
        // The border wraps the whole group even though the banded region is what accepts a drop,
        // outset so a selected row's accent fill sits inside it rather than along it.
        containerFrame: groupFrame.insetBy(dx: 0, dy: -SidebarDropTargetingMetrics.containerOutset)
    )
}

/// Where insertion boundaries share this group's outer edges, reserve each one the same half-row it
/// claims for its own hit frame, so a pointer anywhere in the header's upper half or the terminal's
/// lower half still reorders. Pinned items sit only `interThreadRowSpacing` apart, so a narrower
/// band would leave almost nothing to aim at between two expanded groups.
///
/// A collapsed group publishes one frame for both roles, so two half-rows would consume it whole —
/// there the flat `containerEdgeBand` is the only split that fits before/into/after into one row.
/// A missing frame publishes no boundary, so it reserves nothing.
private func sidebarIntoTargetBandedFrame(
    _ groupFrame: CGRect,
    frames: SidebarDragBoundaryFrames,
    reservesBoundaryHalfRows: Bool
) -> CGRect? {
    if reservesBoundaryHalfRows {
        let topInset = (frames.header?.height ?? 0) / 2
        let bottomInset = (frames.terminal?.height ?? 0) / 2
        let halfRowBanded = CGRect(
            x: groupFrame.minX,
            y: groupFrame.minY + topInset,
            width: groupFrame.width,
            height: groupFrame.height - topInset - bottomInset
        )
        if halfRowBanded.height > 0 {
            return halfRowBanded
        }
    }
    let flatBanded = groupFrame.insetBy(dx: 0, dy: SidebarDropTargetingMetrics.containerEdgeBand)
    return flatBanded.height > 0 ? flatBanded : nil
}

private func sidebarUnoccludedContainerFrame(_ frame: CGRect, occlusionMaxY: CGFloat?) -> CGRect? {
    guard let occlusionMaxY, frame.minY < occlusionMaxY else {
        return frame
    }
    // Check the edges rather than the resulting height: `CGRect.height` standardizes, so a fully
    // occluded frame would report a positive height and survive as an inverted rect.
    guard frame.maxY > occlusionMaxY else {
        return nil
    }
    return CGRect(
        x: frame.minX,
        y: occlusionMaxY,
        width: frame.width,
        height: frame.maxY - occlusionMaxY
    )
}

/// A Task nested under a pinned project cannot hold a standalone pin — the project absorbs its
/// children, so normalization would clear the pin in the same commit.
func sidebarSourceCanHoldStandalonePin(
    _ item: SidebarDragItem,
    logicalOrder: SidebarDragLogicalOrder
) -> Bool {
    guard case .unpinnedTask(let threadID) = item,
          let ownProjectID = logicalOrder.projectIDByTaskID[threadID] else {
        return true
    }
    return !logicalOrder.pinnedItems.contains(.project(ownProjectID))
}

/// An unpinnable source's drag offers no Pinned insertion points; `Tasks` and `.into` remain. A
/// source that takes `Pinned` as one container has none either — the container would eclipse them.
func sidebarPinnedBoundaryCandidatesIfPinnable(
    dragging item: SidebarDragItem,
    geometry: [SidebarDragGeometryRole: [CGRect]],
    viewport: CGRect,
    logicalOrder: SidebarDragLogicalOrder
) -> [SidebarDropCandidate] {
    guard sidebarSourceCanHoldStandalonePin(item, logicalOrder: logicalOrder),
          !sidebarPinnedSectionIsContainerTarget(dragging: item, logicalOrder: logicalOrder) else {
        return []
    }
    return sidebarPinnedItemDropCandidates(
        items: logicalOrder.pinnedItems,
        geometry: geometry,
        viewport: viewport
    )
}
