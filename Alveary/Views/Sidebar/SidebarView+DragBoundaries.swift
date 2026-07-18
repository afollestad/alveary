import SwiftUI

func sidebarCoalescedDropCandidates(
    _ candidates: [SidebarDropCandidate],
    geometry: [SidebarDragGeometryRole: [CGRect]],
    viewport: CGRect,
    logicalOrder: SidebarDragLogicalOrder
) -> [SidebarDropCandidate] {
    let boundaryIndices = sidebarCandidateIndicesByBoundary(candidates, logicalOrder: logicalOrder)
    var result = candidates
    var rejectedIndices: Set<Int> = []

    for (boundary, indices) in boundaryIndices {
        // Preserve source-specific anchors while making an equivalent insertion boundary visually singular.
        let resolution = sidebarVisualDropBoundary(
            boundary,
            geometry: geometry,
            viewport: viewport,
            logicalOrder: logicalOrder
        )
        switch resolution {
        case .unavailable:
            continue
        case .inverted:
            rejectedIndices.formUnion(indices)
        case .valid(let visualBoundary):
            for index in indices {
                let candidate = candidates[index]
                result[index] = SidebarDropCandidate(
                    target: candidate.target,
                    indicatorY: visualBoundary.indicatorY,
                    hitFrame: candidate.hitFrame.sidebarExtendingVertically(to: visualBoundary.indicatorY),
                    priority: candidate.priority
                )
            }
        }
    }
    return result.enumerated().compactMap { index, candidate in
        rejectedIndices.contains(index) ? nil : candidate
    }
}

private func sidebarCandidateIndicesByBoundary(
    _ candidates: [SidebarDropCandidate],
    logicalOrder: SidebarDragLogicalOrder
) -> [SidebarLogicalDropBoundary: [Int]] {
    var result: [SidebarLogicalDropBoundary: [Int]] = [:]
    for (index, candidate) in candidates.enumerated() {
        guard let boundary = sidebarLogicalDropBoundary(
            for: candidate.target,
            logicalOrder: logicalOrder
        ) else {
            continue
        }
        result[boundary, default: []].append(index)
    }
    return result
}

private func sidebarLogicalDropBoundary(
    for target: SidebarDropTarget,
    logicalOrder: SidebarDragLogicalOrder
) -> SidebarLogicalDropBoundary? {
    let items = sidebarLogicalItems(in: target.section, logicalOrder: logicalOrder)
    guard let targetItem = target.item else {
        let insertionIndex = target.placement == .before ? 0 : items.count
        return SidebarLogicalDropBoundary(section: target.section, insertionIndex: insertionIndex)
    }
    guard let targetIndex = items.firstIndex(of: targetItem) else {
        return nil
    }

    let insertionIndex: Int
    switch target.placement {
    case .before:
        insertionIndex = targetIndex
    case .after, .end:
        insertionIndex = targetIndex + 1
    }
    return SidebarLogicalDropBoundary(section: target.section, insertionIndex: insertionIndex)
}

private func sidebarVisualDropBoundary(
    _ boundary: SidebarLogicalDropBoundary,
    geometry: [SidebarDragGeometryRole: [CGRect]],
    viewport: CGRect,
    logicalOrder: SidebarDragLogicalOrder
) -> SidebarVisualDropBoundaryResolution {
    let items = sidebarLogicalItems(in: boundary.section, logicalOrder: logicalOrder)
    guard boundary.insertionIndex >= 0, boundary.insertionIndex <= items.count else {
        return .unavailable
    }
    let projectsHeaderFrame = sidebarProjectsHeaderFrame(
        geometry: geometry,
        viewport: viewport,
        isSticky: logicalOrder.projectsHeaderIsSticky
    )
    let stickyOcclusionMaxY: CGFloat? = boundary.section == .projects && logicalOrder.projectsHeaderIsSticky
        ? projectsHeaderFrame?.maxY
        : nil
    let context = SidebarVisualDropBoundaryContext(
        geometry: geometry,
        viewport: viewport,
        projectsHeaderFrame: projectsHeaderFrame,
        stickyOcclusionMaxY: stickyOcclusionMaxY
    )
    let endpointYs = [
        sidebarPreviousDropBoundaryEndpoint(
            boundary,
            items: items,
            context: context
        ),
        sidebarNextDropBoundaryEndpoint(
            boundary,
            items: items,
            context: context
        )
    ].compactMap { $0 }
    guard let minimumY = endpointYs.min(),
          let maximumY = endpointYs.max() else {
        return .unavailable
    }
    // Transient preference churn can place an item above its owning section or predecessor.
    guard endpointYs == endpointYs.sorted() else {
        return .inverted
    }
    return .valid(SidebarVisualDropBoundary(indicatorY: (minimumY + maximumY) / 2))
}

private func sidebarPreviousDropBoundaryEndpoint(
    _ boundary: SidebarLogicalDropBoundary,
    items: [SidebarDragItem],
    context: SidebarVisualDropBoundaryContext
) -> CGFloat? {
    if boundary.insertionIndex > 0 {
        let previousItem = items[boundary.insertionIndex - 1]
        let frames = sidebarItemBoundaryFrames(
            for: previousItem,
            section: boundary.section,
            geometry: context.geometry
        )
        guard let terminal = frames.terminal else {
            return nil
        }
        return sidebarVisualDropBoundaryEndpoint(
            boundaryFrame: terminal,
            usesUpperHalf: false,
            viewport: context.viewport,
            stickyOcclusionMaxY: context.stickyOcclusionMaxY
        )
    }

    // A removed `Pinned` header can keep publishing during its `List` transition.
    if boundary.section == .pinned, items.isEmpty {
        return nil
    }

    guard let startFrame = sidebarSectionStartFrame(for: boundary.section, geometry: context.geometry) else {
        return nil
    }
    return sidebarVisualDropBoundaryEndpoint(
        boundaryFrame: startFrame,
        usesUpperHalf: false,
        viewport: context.viewport,
        stickyOcclusionMaxY: nil
    )
}

private func sidebarNextDropBoundaryEndpoint(
    _ boundary: SidebarLogicalDropBoundary,
    items: [SidebarDragItem],
    context: SidebarVisualDropBoundaryContext
) -> CGFloat? {
    if boundary.insertionIndex < items.count {
        let nextItem = items[boundary.insertionIndex]
        let frames = sidebarItemBoundaryFrames(
            for: nextItem,
            section: boundary.section,
            geometry: context.geometry
        )
        guard let header = frames.header else {
            return nil
        }
        return sidebarVisualDropBoundaryEndpoint(
            boundaryFrame: header,
            usesUpperHalf: true,
            viewport: context.viewport,
            stickyOcclusionMaxY: context.stickyOcclusionMaxY
        )
    }

    guard boundary.section == .pinned, let projectsHeaderFrame = context.projectsHeaderFrame else {
        return nil
    }
    return sidebarVisualDropBoundaryEndpoint(
        boundaryFrame: projectsHeaderFrame,
        usesUpperHalf: true,
        viewport: context.viewport,
        stickyOcclusionMaxY: nil
    )
}

private func sidebarLogicalItems(
    in section: SidebarDropSection,
    logicalOrder: SidebarDragLogicalOrder
) -> [SidebarDragItem] {
    switch section {
    case .pinned:
        logicalOrder.pinnedItems
    case .projects:
        logicalOrder.regularProjects
    }
}

private func sidebarSectionStartFrame(
    for section: SidebarDropSection,
    geometry: [SidebarDragGeometryRole: [CGRect]]
) -> CGRect? {
    switch section {
    case .pinned:
        geometry[.pinnedHeader]?.sidebarUnion
    case .projects:
        geometry[.projectsHeader]?.sidebarUnion
    }
}

private func sidebarVisualDropBoundaryEndpoint(
    boundaryFrame: CGRect,
    usesUpperHalf: Bool,
    viewport: CGRect,
    stickyOcclusionMaxY: CGFloat?
) -> CGFloat? {
    let indicatorY = usesUpperHalf ? boundaryFrame.minY : boundaryFrame.maxY
    return sidebarLineIsVisible(
        indicatorY,
        viewport: viewport,
        stickyOcclusionMaxY: stickyOcclusionMaxY
    ) ? indicatorY : nil
}

func sidebarItemBoundaryFrames(
    for item: SidebarDragItem,
    section: SidebarDropSection,
    geometry: [SidebarDragGeometryRole: [CGRect]]
) -> SidebarDragBoundaryFrames {
    switch item {
    case .project(let projectID):
        return SidebarDragBoundaryFrames(
            header: geometry[.projectHeader(section, projectID)]?.sidebarUnion,
            terminal: geometry[.projectTerminal(section, projectID)]?.sidebarUnion
        )
    case .pinnedThread(let threadID):
        let frame = geometry[.pinnedThread(threadID)]?.sidebarUnion
        return SidebarDragBoundaryFrames(header: frame, terminal: frame)
    case .pinnedTask(let threadID):
        let frame = geometry[.pinnedTask(threadID)]?.sidebarUnion
        return SidebarDragBoundaryFrames(header: frame, terminal: frame)
    }
}

func sidebarLineIsVisible(
    _ lineY: CGFloat,
    viewport: CGRect,
    stickyOcclusionMaxY: CGFloat?
) -> Bool {
    guard lineY >= viewport.minY, lineY <= viewport.maxY else {
        return false
    }
    if let stickyOcclusionMaxY, lineY <= stickyOcclusionMaxY + 0.5 {
        return false
    }
    return true
}

struct SidebarDragBoundaryFrames {
    let header: CGRect?
    let terminal: CGRect?
}

private struct SidebarLogicalDropBoundary: Hashable {
    let section: SidebarDropSection
    let insertionIndex: Int
}

private struct SidebarVisualDropBoundary {
    let indicatorY: CGFloat
}

private enum SidebarVisualDropBoundaryResolution {
    case valid(SidebarVisualDropBoundary)
    case unavailable
    case inverted
}

private struct SidebarVisualDropBoundaryContext {
    let geometry: [SidebarDragGeometryRole: [CGRect]]
    let viewport: CGRect
    let projectsHeaderFrame: CGRect?
    let stickyOcclusionMaxY: CGFloat?
}

private extension CGRect {
    func sidebarExtendingVertically(to positionY: CGFloat) -> CGRect {
        let extendedMinY = min(minY, positionY)
        let extendedMaxY = max(maxY, positionY)
        return CGRect(x: minX, y: extendedMinY, width: width, height: extendedMaxY - extendedMinY)
    }
}
