import SwiftData
import SwiftUI

func sidebarDropCandidateForLocation(
    at location: CGPoint,
    dragging item: SidebarDragItem,
    geometry: [SidebarDragGeometryRole: [CGRect]],
    logicalOrder: SidebarDragLogicalOrder,
    retainingTarget: SidebarDropTarget? = nil
) -> SidebarDropCandidate? {
    guard let viewport = geometry[.viewport]?.sidebarUnion,
          viewport.sidebarContains(location) else {
        return nil
    }

    let candidates = sidebarDropCandidates(
        dragging: item,
        geometry: geometry,
        viewport: viewport,
        logicalOrder: logicalOrder
    ).filter { candidate in
        let hitSlop = candidate.target == retainingTarget
            ? SidebarDropTargetingMetrics.retentionHitSlop
            : SidebarDropTargetingMetrics.acquisitionHitSlop
        guard candidate.target.item != item,
              candidate.hitFrame.insetBy(dx: 0, dy: -hitSlop).contains(location) else {
            return false
        }
        // Containers accept a drop anywhere inside them, so the indicator-proximity gate that
        // keeps insertion lines local would reject their taller frames. The boundaries that opt
        // out do so for the same reason: each owns a region no other candidate publishes in.
        return candidate.kind == .container
            || candidate.ignoresIndicatorProximity
            || abs(candidate.indicatorY - location.y) <= SidebarDropTargetingMetrics.maximumIndicatorDistance
    }

    return candidates.min { lhs, rhs in
        let lhsDistance = sidebarDropCandidateDistance(
            lhs,
            from: location,
            retainingTarget: retainingTarget
        )
        let rhsDistance = sidebarDropCandidateDistance(
            rhs,
            from: location,
            retainingTarget: retainingTarget
        )
        if lhsDistance != rhsDistance {
            return lhsDistance < rhsDistance
        }
        if lhs.priority != rhs.priority {
            return lhs.priority < rhs.priority
        }
        return lhs.hitFrame.height < rhs.hitFrame.height
    }
}

private func sidebarDropCandidateDistance(
    _ candidate: SidebarDropCandidate,
    from location: CGPoint,
    retainingTarget: SidebarDropTarget?
) -> CGFloat {
    // A point inside a container scores a perfect hit, so an overlapping boundary can only tie and
    // must win on `priority`. `.into` containers do overlap `Pinned` boundaries, which is why they
    // band their frame away from the half-rows those boundaries claim rather than relying on this.
    let distance = candidate.kind == .container && candidate.hitFrame.contains(location)
        ? 0
        : abs(candidate.indicatorY - location.y)
    guard candidate.target == retainingTarget else {
        return distance
    }
    return max(distance - SidebarDropTargetingMetrics.retentionDistanceBias, 0)
}

func sidebarDropCandidates(
    dragging item: SidebarDragItem,
    geometry: [SidebarDragGeometryRole: [CGRect]],
    viewport: CGRect,
    logicalOrder: SidebarDragLogicalOrder
) -> [SidebarDropCandidate] {
    let projectsHeaderFrame = geometry[.projectsHeader]?.sidebarUnion
    var candidates = sidebarSectionDropCandidates(
        dragging: item,
        geometry: geometry,
        projectsHeaderFrame: projectsHeaderFrame,
        viewport: viewport,
        logicalOrder: logicalOrder
    )

    candidates += sidebarItemDropCandidates(
        dragging: item,
        geometry: geometry,
        viewport: viewport,
        logicalOrder: logicalOrder
    )

    return sidebarCoalescedDropCandidates(
        candidates,
        geometry: geometry,
        viewport: viewport,
        logicalOrder: logicalOrder
    )
}

private func sidebarItemDropCandidates(
    dragging item: SidebarDragItem,
    geometry: [SidebarDragGeometryRole: [CGRect]],
    viewport: CGRect,
    logicalOrder: SidebarDragLogicalOrder
) -> [SidebarDropCandidate] {
    switch item {
    case .project:
        return sidebarProjectDropCandidates(
            section: .pinned,
            items: logicalOrder.pinnedItems,
            geometry: geometry,
            viewport: viewport
        ) + sidebarProjectDropCandidates(
            section: .projects,
            items: logicalOrder.regularProjects,
            geometry: geometry,
            viewport: viewport
        )
    case .section:
        // A section reorders only against its siblings; every row-domain target is meaningless.
        return sidebarSectionReorderCandidates(
            dragging: item,
            geometry: geometry,
            viewport: viewport,
            logicalOrder: logicalOrder
        )
    case .pinnedThread, .pinnedTask, .unpinnedTask, .projectThread:
        return sidebarPinnedBoundaryCandidatesIfPinnable(
            dragging: item,
            geometry: geometry,
            viewport: viewport,
            logicalOrder: logicalOrder
        ) + sidebarProjectIntoDropCandidates(
            dragging: item,
            geometry: geometry,
            viewport: viewport,
            logicalOrder: logicalOrder
        )
    }
}

private func sidebarSectionDropCandidates(
    dragging item: SidebarDragItem,
    geometry: [SidebarDragGeometryRole: [CGRect]],
    projectsHeaderFrame: CGRect?,
    viewport: CGRect,
    logicalOrder: SidebarDragLogicalOrder
) -> [SidebarDropCandidate] {
    var candidates = sidebarPinnedSectionCandidates(
        dragging: item,
        geometry: geometry,
        projectsHeaderFrame: projectsHeaderFrame,
        viewport: viewport,
        logicalOrder: logicalOrder
    )
    if let tasksCandidate = sidebarTasksSectionDropCandidate(
        dragging: item,
        geometry: geometry,
        viewport: viewport,
        logicalOrder: logicalOrder
    ) {
        candidates.append(tasksCandidate)
    }
    candidates += sidebarCustomSectionDropCandidates(
        dragging: item,
        geometry: geometry,
        viewport: viewport,
        logicalOrder: logicalOrder
    )

    guard let projectsHeaderFrame else {
        return candidates
    }
    if case .project = item,
       let projectsStart = sidebarSectionCandidate(
           target: SidebarDropTarget(section: .projects, item: nil, placement: .before),
           indicatorY: projectsHeaderFrame.maxY,
           hitFrame: projectsHeaderFrame.sidebarLowerHalf,
           viewport: viewport,
           priority: -1
       ) {
        candidates.append(projectsStart)
    }
    return candidates
}

private func sidebarTasksSectionDropCandidate(
    dragging item: SidebarDragItem,
    geometry: [SidebarDragGeometryRole: [CGRect]],
    viewport: CGRect,
    logicalOrder: SidebarDragLogicalOrder
) -> SidebarDropCandidate? {
    // A pinned Task drops here to unpin; a Task that lives in a project or a custom section
    // drops here to leave it. A Task already resting in `Tasks` has nowhere to arrive from.
    let accepts: Bool
    switch item {
    case .pinnedTask(let threadID):
        accepts = logicalOrder.unpinnableTaskIDs.contains(threadID)
    case .unpinnedTask(let threadID):
        accepts = logicalOrder.projectIDByTaskID[threadID] != nil
            || logicalOrder.customSectionIDByTaskID[threadID] != nil
    case .project, .pinnedThread, .projectThread, .section:
        accepts = false
    }
    guard accepts, let tasksHeaderFrame = geometry[.tasksHeader]?.sidebarUnion else {
        return nil
    }
    // Tasks is activity-sorted, so the whole section is one target rather than an insertion point.
    let sectionFrame = sidebarSectionContainerFrame(
        headerFrame: tasksHeaderFrame,
        contentFrames: [geometry[.tasksTerminal]?.sidebarUnion].compactMap { $0 }
    )
    return sidebarSectionCandidate(
        target: SidebarDropTarget(section: .tasks, item: nil, placement: .end),
        indicatorY: sectionFrame.midY,
        hitFrame: sectionFrame,
        viewport: viewport,
        kind: .container
    )
}

/// The frame a whole-section container borders: the header's visible title row through the
/// section's last row, plus `containerOutset` of breathing room so the border clears a selected
/// row's accent fill instead of tracing it.
///
/// `Pinned` and `Tasks` share this so their borders sit identically. Both headers publish only
/// their title row (`inlineHeaderTotalTopPadding` excluded), so neither border floats up into the
/// divider's spacing.
func sidebarSectionContainerFrame(headerFrame: CGRect, contentFrames: [CGRect]) -> CGRect {
    (([headerFrame] + contentFrames).sidebarUnion ?? headerFrame)
        .insetBy(dx: 0, dy: -SidebarDropTargetingMetrics.containerOutset)
}

func sidebarSectionCandidate(
    target: SidebarDropTarget,
    indicatorY: CGFloat,
    hitFrame: CGRect,
    viewport: CGRect,
    priority: Int = 0,
    kind: SidebarDropCandidateKind = .boundary,
    containerFrame: CGRect? = nil,
    ignoresIndicatorProximity: Bool = false
) -> SidebarDropCandidate? {
    guard let clippedHitFrame = hitFrame.sidebarIntersection(with: viewport) else {
        return nil
    }
    // A container is anchored to its visible extent, so scrolling its midpoint out of view must
    // not drop the target while part of it is still under the pointer. A boundary is a single
    // line, so it stays subject to the ordinary visibility check.
    guard kind == .container || sidebarLineIsVisible(indicatorY, viewport: viewport) else {
        return nil
    }
    return SidebarDropCandidate(
        target: target,
        indicatorY: kind == .container ? clippedHitFrame.midY : indicatorY,
        hitFrame: clippedHitFrame,
        priority: priority,
        kind: kind,
        containerFrame: containerFrame?.sidebarIntersection(with: viewport),
        ignoresIndicatorProximity: ignoresIndicatorProximity
    )
}

private func sidebarProjectDropCandidates(
    section: SidebarDropSection,
    items: [SidebarDragItem],
    geometry: [SidebarDragGeometryRole: [CGRect]],
    viewport: CGRect
) -> [SidebarDropCandidate] {
    let projectEntries = items.compactMap { item -> SidebarDragProjectEntry? in
        guard case .project(let projectID) = item else {
            return nil
        }
        return SidebarDragProjectEntry(item: item, projectID: projectID)
    }
    let context = SidebarProjectCandidateContext(
        section: section,
        logicalItems: items,
        geometry: geometry,
        viewport: viewport
    )

    return projectEntries.enumerated().flatMap { index, entry in
        sidebarProjectDropCandidates(
            entry: entry,
            entryIndex: index,
            entryCount: projectEntries.count,
            context: context
        )
    }
}

private func sidebarProjectDropCandidates(
    entry: SidebarDragProjectEntry,
    entryIndex: Int,
    entryCount: Int,
    context: SidebarProjectCandidateContext
) -> [SidebarDropCandidate] {
    let header = context.geometry[.projectHeader(context.section, entry.projectID)]?.sidebarUnion
    let terminal = context.geometry[.projectTerminal(context.section, entry.projectID)]?.sidebarUnion
    let headerIsVisible = header.map {
        sidebarLineIsVisible($0.minY, viewport: context.viewport)
    } ?? false
    let terminalIsVisible = terminal.map {
        sidebarLineIsVisible($0.maxY, viewport: context.viewport)
    } ?? false
    var candidates: [SidebarDropCandidate] = []

    if let header, headerIsVisible {
        let hitFrame = sidebarBoundaryHitFrame(
            boundaryFrame: header,
            usesUpperHalf: true
        )
        candidates.append(SidebarDropCandidate(
            target: SidebarDropTarget(section: context.section, item: entry.item, placement: .before),
            indicatorY: header.minY,
            hitFrame: hitFrame.sidebarIntersection(with: context.viewport) ?? header,
            priority: 1
        ))
    }

    if let terminal, terminalIsVisible {
        let target = context.logicalItems.last == entry.item
            ? SidebarDropTarget(section: context.section, item: nil, placement: .end)
            : SidebarDropTarget(section: context.section, item: entry.item, placement: .after)
        let hitFrame = sidebarBoundaryHitFrame(
            boundaryFrame: terminal,
            usesUpperHalf: false
        )
        candidates.append(SidebarDropCandidate(
            target: target,
            indicatorY: terminal.maxY,
            hitFrame: hitFrame.sidebarIntersection(with: context.viewport) ?? terminal,
            priority: entryIndex == entryCount - 1 ? 0 : 1
        ))
    }
    return candidates
}

func sidebarPinnedItemDropCandidates(
    items: [SidebarDragItem],
    geometry: [SidebarDragGeometryRole: [CGRect]],
    viewport: CGRect
) -> [SidebarDropCandidate] {
    var candidates: [SidebarDropCandidate] = []

    for item in items {
        let frames = sidebarItemBoundaryFrames(for: item, section: .pinned, geometry: geometry)
        let headerIsVisible = frames.header.map {
            sidebarLineIsVisible($0.minY, viewport: viewport)
        } ?? false
        let terminalIsVisible = frames.terminal.map {
            sidebarLineIsVisible($0.maxY, viewport: viewport)
        } ?? false
        if let header = frames.header, headerIsVisible {
            let hitFrame = sidebarBoundaryHitFrame(
                boundaryFrame: header,
                usesUpperHalf: true
            )
            candidates.append(SidebarDropCandidate(
                target: SidebarDropTarget(section: .pinned, item: item, placement: .before),
                indicatorY: header.minY,
                hitFrame: hitFrame.sidebarIntersection(with: viewport) ?? header,
                priority: 0
            ))
        }
        if let terminal = frames.terminal, terminalIsVisible {
            let target = items.last == item
                ? SidebarDropTarget(section: .pinned, item: nil, placement: .end)
                : SidebarDropTarget(section: .pinned, item: item, placement: .after)
            let hitFrame = sidebarBoundaryHitFrame(
                boundaryFrame: terminal,
                usesUpperHalf: false
            )
            candidates.append(SidebarDropCandidate(
                target: target,
                indicatorY: terminal.maxY,
                hitFrame: hitFrame.sidebarIntersection(with: viewport) ?? terminal,
                priority: 1
            ))
        }
    }
    return candidates
}

private func sidebarBoundaryHitFrame(
    boundaryFrame: CGRect,
    usesUpperHalf: Bool
) -> CGRect {
    usesUpperHalf ? boundaryFrame.sidebarUpperHalf : boundaryFrame.sidebarLowerHalf
}

private struct SidebarDragProjectEntry {
    let item: SidebarDragItem
    let projectID: PersistentIdentifier
}

private struct SidebarProjectCandidateContext {
    let section: SidebarDropSection
    let logicalItems: [SidebarDragItem]
    let geometry: [SidebarDragGeometryRole: [CGRect]]
    let viewport: CGRect
}

enum SidebarDropTargetingMetrics {
    static let maximumIndicatorDistance: CGFloat = 20
    static let acquisitionHitSlop: CGFloat = 4
    static let retentionHitSlop: CGFloat = 8
    static let retentionDistanceBias: CGFloat = 4
    /// Reserved at a container's top and bottom so the insertion boundaries sharing those edges
    /// stay reachable.
    static let containerEdgeBand: CGFloat = 6
    /// Breathing room so a container border clears the content it wraps — in particular a selected
    /// row's accent fill, which otherwise traces almost exactly the same rectangle.
    ///
    /// Matches the horizontal clearance the border already has: the pill is inset 10pt and
    /// `SidebarDragBorderMetrics.horizontalInset` puts the border 3pt from the edge, leaving 7pt.
    /// The pill has no bottom inset, so anything smaller here reads as pinched top and bottom
    /// against those sides — most visibly in `Pinned`, whose row is usually the selected one.
    static let containerOutset: CGFloat = 7
}

enum SidebarDragCoordinateSpace {
    static let name = "sidebar.drag.coordinate-space"
}

extension Array where Element == CGRect {
    var sidebarUnion: CGRect? {
        guard var result = first else {
            return nil
        }
        for frame in dropFirst() {
            result = result.union(frame)
        }
        return result
    }
}

extension CGRect {
    var sidebarUpperHalf: CGRect {
        CGRect(x: minX, y: minY, width: width, height: height / 2)
    }

    var sidebarLowerHalf: CGRect {
        CGRect(x: minX, y: midY, width: width, height: height / 2)
    }
}

private extension CGRect {
    func sidebarIntersection(with other: CGRect) -> CGRect? {
        let result = intersection(other)
        return result.isNull || result.isEmpty ? nil : result
    }

    func sidebarContains(_ point: CGPoint) -> Bool {
        point.x >= minX && point.x <= maxX
            && point.y >= minY && point.y <= maxY
    }
}
