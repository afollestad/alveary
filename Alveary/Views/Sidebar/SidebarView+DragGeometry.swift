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
        return candidate.target.item != item
            && abs(candidate.indicatorY - location.y) <= SidebarDropTargetingMetrics.maximumIndicatorDistance
            && candidate.hitFrame.insetBy(dx: 0, dy: -hitSlop).contains(location)
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
    let distance = abs(candidate.indicatorY - location.y)
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
    let stickyOcclusionMaxY: CGFloat? = logicalOrder.projectsHeaderIsSticky
        ? projectsHeaderFrame?.intersection(viewport).maxY
        : nil
    var candidates = sidebarSectionDropCandidates(
        dragging: item,
        geometry: geometry,
        viewport: viewport,
        pinnedSectionIsVisible: !logicalOrder.pinnedItems.isEmpty
    )

    switch item {
    case .project:
        candidates += sidebarProjectDropCandidates(
            section: .pinned,
            items: logicalOrder.pinnedItems,
            geometry: geometry,
            viewport: viewport,
            stickyOcclusionMaxY: nil
        )
        candidates += sidebarProjectDropCandidates(
            section: .projects,
            items: logicalOrder.regularProjects,
            geometry: geometry,
            viewport: viewport,
            stickyOcclusionMaxY: stickyOcclusionMaxY
        )
    case .pinnedThread:
        candidates += sidebarPinnedThreadDropCandidates(
            items: logicalOrder.pinnedItems,
            geometry: geometry,
            viewport: viewport
        )
    }

    return sidebarCoalescedDropCandidates(
        candidates,
        geometry: geometry,
        viewport: viewport,
        logicalOrder: logicalOrder
    )
}

private func sidebarSectionDropCandidates(
    dragging item: SidebarDragItem,
    geometry: [SidebarDragGeometryRole: [CGRect]],
    viewport: CGRect,
    pinnedSectionIsVisible: Bool
) -> [SidebarDropCandidate] {
    var candidates: [SidebarDropCandidate] = []

    if pinnedSectionIsVisible,
       let pinnedHeaderFrame = geometry[.pinnedHeader]?.sidebarUnion,
       let candidate = sidebarSectionCandidate(
           target: SidebarDropTarget(section: .pinned, item: nil, placement: .before),
           indicatorY: pinnedHeaderFrame.maxY,
           hitFrame: pinnedHeaderFrame.sidebarLowerHalf,
           viewport: viewport
       ) {
        candidates.append(candidate)
    }

    guard let projectsHeaderFrame = geometry[.projectsHeader]?.sidebarUnion else {
        return candidates
    }
    if let pinnedEnd = sidebarSectionCandidate(
        target: SidebarDropTarget(section: .pinned, item: nil, placement: .end),
        indicatorY: projectsHeaderFrame.minY,
        hitFrame: projectsHeaderFrame.sidebarUpperHalf,
        viewport: viewport,
        priority: -1
    ) {
        candidates.append(pinnedEnd)
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

private func sidebarSectionCandidate(
    target: SidebarDropTarget,
    indicatorY: CGFloat,
    hitFrame: CGRect,
    viewport: CGRect,
    priority: Int = 0
) -> SidebarDropCandidate? {
    guard sidebarLineIsVisible(indicatorY, viewport: viewport, stickyOcclusionMaxY: nil),
          let clippedHitFrame = hitFrame.sidebarIntersection(with: viewport) else {
        return nil
    }
    return SidebarDropCandidate(
        target: target,
        indicatorY: indicatorY,
        hitFrame: clippedHitFrame,
        priority: priority
    )
}

private func sidebarProjectDropCandidates(
    section: SidebarDropSection,
    items: [SidebarDragItem],
    geometry: [SidebarDragGeometryRole: [CGRect]],
    viewport: CGRect,
    stickyOcclusionMaxY: CGFloat?
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
        viewport: viewport,
        stickyOcclusionMaxY: stickyOcclusionMaxY
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
        sidebarLineIsVisible($0.minY, viewport: context.viewport, stickyOcclusionMaxY: context.stickyOcclusionMaxY)
    } ?? false
    let terminalIsVisible = terminal.map {
        sidebarLineIsVisible($0.maxY, viewport: context.viewport, stickyOcclusionMaxY: context.stickyOcclusionMaxY)
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

private func sidebarPinnedThreadDropCandidates(
    items: [SidebarDragItem],
    geometry: [SidebarDragGeometryRole: [CGRect]],
    viewport: CGRect
) -> [SidebarDropCandidate] {
    var candidates: [SidebarDropCandidate] = []

    for item in items {
        let frames = sidebarItemBoundaryFrames(for: item, section: .pinned, geometry: geometry)
        let headerIsVisible = frames.header.map {
            sidebarLineIsVisible($0.minY, viewport: viewport, stickyOcclusionMaxY: nil)
        } ?? false
        let terminalIsVisible = frames.terminal.map {
            sidebarLineIsVisible($0.maxY, viewport: viewport, stickyOcclusionMaxY: nil)
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
    let stickyOcclusionMaxY: CGFloat?
}

private enum SidebarDropTargetingMetrics {
    static let maximumIndicatorDistance: CGFloat = 20
    static let acquisitionHitSlop: CGFloat = 4
    static let retentionHitSlop: CGFloat = 8
    static let retentionDistanceBias: CGFloat = 4
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

private extension CGRect {
    var sidebarUpperHalf: CGRect {
        CGRect(x: minX, y: minY, width: width, height: height / 2)
    }

    var sidebarLowerHalf: CGRect {
        CGRect(x: minX, y: midY, width: width, height: height / 2)
    }

    func sidebarIntersection(with other: CGRect) -> CGRect? {
        let result = intersection(other)
        return result.isNull || result.isEmpty ? nil : result
    }

    func sidebarContains(_ point: CGPoint) -> Bool {
        point.x >= minX && point.x <= maxX
            && point.y >= minY && point.y <= maxY
    }
}
