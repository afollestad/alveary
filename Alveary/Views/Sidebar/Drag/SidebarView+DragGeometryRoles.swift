import SwiftData
import SwiftUI

/// What each participating row publishes about itself, and the preference pipeline that
/// collects those frames at the list root. Targeting reads only this map, never the views.

enum SidebarDragGeometryRole: Hashable {
    case projectHeader(SidebarDropSection, PersistentIdentifier)
    case projectTerminal(SidebarDropSection, PersistentIdentifier)
    case pinnedThread(PersistentIdentifier)
    case pinnedTask(PersistentIdentifier)
    case pinnedHeader
    case projectsHeader
    /// Last visible top-level row, so the empty-`Pinned` target can reach the region where a
    /// pinned row would appear rather than clinging to the `Projects` header's top edge.
    case topLevelTerminal
    case tasksHeader
    /// Last visible Tasks row (or the empty placeholder), so the section's border can hug content.
    case tasksTerminal
    /// A custom section's header row, keyed by `SidebarSection.id`.
    case customSectionHeader(String)
    /// A custom section's last visible row, or its empty placeholder — the same contract
    /// `tasksTerminal` carries, so a custom section's drop container hugs its content.
    case customSectionTerminal(String)
    case viewport

    /// The header role a section publishes. Built-ins keep their own cases rather than becoming
    /// `custom` payloads: their frames are read by name across the targeting code, and a string
    /// key would let a typo compile.
    static func sectionHeader(_ id: SidebarSectionID) -> SidebarDragGeometryRole {
        switch id {
        case .pinned: .pinnedHeader
        case .projects: .projectsHeader
        case .tasks: .tasksHeader
        case .custom(let sectionID): .customSectionHeader(sectionID)
        }
    }

    /// The terminal role a section publishes from its last visible row. `Pinned` and `Projects`
    /// have none: their per-item boundaries already expose every edge targeting needs.
    static func sectionTerminal(_ id: SidebarSectionID) -> SidebarDragGeometryRole? {
        switch id {
        case .tasks: .tasksTerminal
        case .custom(let sectionID): .customSectionTerminal(sectionID)
        case .pinned, .projects: nil
        }
    }
}

struct SidebarDragGeometryPreferenceKey: PreferenceKey {
    static let defaultValue: [SidebarDragGeometryRole: [CGRect]] = [:]

    static func reduce(
        value: inout [SidebarDragGeometryRole: [CGRect]],
        nextValue: () -> [SidebarDragGeometryRole: [CGRect]]
    ) {
        for (role, frames) in nextValue() {
            value[role, default: []].append(contentsOf: frames)
        }
    }
}

extension View {
    /// Disabling suppresses preference emission without changing view structure, preserving identity during animations.
    func sidebarDragGeometry(
        _ role: SidebarDragGeometryRole,
        isEnabled: Bool = true,
        excludingTopInset topInset: CGFloat = 0
    ) -> some View {
        background {
            GeometryReader { proxy in
                Color.clear.preference(
                    key: SidebarDragGeometryPreferenceKey.self,
                    value: isEnabled
                        ? [role: [sidebarDragGeometryFrame(
                            proxy.frame(in: .named(SidebarDragCoordinateSpace.name)),
                            excludingTopInset: topInset
                        )]]
                        : [:]
                )
            }
        }
    }
}

func sidebarDragGeometryFrame(
    _ frame: CGRect,
    excludingTopInset topInset: CGFloat
) -> CGRect {
    let excludedTopInset = min(max(topInset, 0), frame.height)
    return CGRect(
        x: frame.minX,
        y: frame.minY + excludedTopInset,
        width: frame.width,
        height: frame.height - excludedTopInset
    )
}
