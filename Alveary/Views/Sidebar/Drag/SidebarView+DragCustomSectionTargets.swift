import SwiftData
import SwiftUI

/// Every custom section offers itself as one whole-section container, the same affordance `Tasks`
/// and `Pinned` give a source that is choosing membership rather than position: a custom section's
/// threads are activity-sorted, so there is no insertion point to aim at.
///
/// Unlike `Tasks` — which only accepts a Task arriving from somewhere else — a custom section is a
/// destination for every eligible Task except its own members, including a plain `Tasks` row that
/// today has no membership container at all.
func sidebarCustomSectionDropCandidates(
    dragging item: SidebarDragItem,
    geometry: [SidebarDragGeometryRole: [CGRect]],
    viewport: CGRect,
    logicalOrder: SidebarDragLogicalOrder
) -> [SidebarDropCandidate] {
    guard let threadID = sidebarCustomSectionEligibleTaskID(dragging: item, logicalOrder: logicalOrder) else {
        return []
    }
    let currentSectionID = logicalOrder.customSectionIDByTaskID[threadID]

    return sidebarCustomSectionIDs(in: geometry).compactMap { sectionID -> SidebarDropCandidate? in
        guard sectionID != currentSectionID,
              let headerFrame = geometry[.customSectionHeader(sectionID)]?.sidebarUnion else {
            return nil
        }
        let sectionFrame = sidebarSectionContainerFrame(
            headerFrame: headerFrame,
            contentFrames: [geometry[.customSectionTerminal(sectionID)]?.sidebarUnion].compactMap { $0 }
        )
        return sidebarSectionCandidate(
            target: SidebarDropTarget(section: .customSection(sectionID), item: nil, placement: .end),
            indicatorY: sectionFrame.midY,
            hitFrame: sectionFrame,
            viewport: viewport,
            kind: .container
        )
    }
}

/// The Task a source represents when it may join a custom section, or nil when the source cannot.
///
/// Mirrors the `Tasks` container's eligibility: only Task-shaped sources qualify, a pinned one
/// only while it may actually unpin. A `.projectThread` is Project-mode and a `.pinnedThread`
/// stays one, so neither belongs in a section whose whole population is Tasks.
func sidebarCustomSectionEligibleTaskID(
    dragging item: SidebarDragItem,
    logicalOrder: SidebarDragLogicalOrder
) -> PersistentIdentifier? {
    switch item {
    case .pinnedTask(let threadID):
        return logicalOrder.unpinnableTaskIDs.contains(threadID) ? threadID : nil
    case .unpinnedTask(let threadID):
        return threadID
    case .project, .pinnedThread, .projectThread, .section:
        return nil
    }
}

/// Custom sections currently publishing a header, in no particular order — each candidate stands
/// alone, so ordering would only matter if they competed, and their frames never overlap.
private func sidebarCustomSectionIDs(in geometry: [SidebarDragGeometryRole: [CGRect]]) -> [String] {
    geometry.keys.compactMap { role in
        guard case .customSectionHeader(let sectionID) = role else {
            return nil
        }
        return sectionID
    }
}
