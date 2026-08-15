import Foundation
import SwiftData

/// One sidebar section row — builtin (`Pinned`, `Projects`, `Tasks`) or user-created.
///
/// Builtins are persisted rows rather than hardcoded slots so all sections share one dense
/// `sortOrder` namespace and every reorder, create, and remove commits in a single save; an
/// order list kept elsewhere (settings, say) would split one logical mutation across two stores
/// with no transaction. `SidebarSectionNormalization` seeds missing builtin rows idempotently,
/// so a fresh or recovered store self-heals.
@Model
final class SidebarSection {
    /// Stable identity for custom sections, safe to hand to MCP callers and to embed in view
    /// state: unlike `name` it survives renames, and unlike `persistentModelID` it round-trips
    /// as a plain string.
    @Attribute(.unique) var id: String
    var kindRawValue: String
    /// Canonical display name, stored trimmed. Builtins store their fixed display name, but
    /// renders read `SidebarSectionKind.builtinDisplayName` so a stale row cannot relabel them.
    var name: String
    /// Dense `0..<count` across ALL sections, builtins included; `SidebarSectionNormalization`
    /// renumbers. Non-optional unlike `pinnedSortOrder`: a section always participates in the
    /// order, so there is no "unordered" state to model.
    var sortOrder: Int
    /// Deterministic tiebreak for normalization when sort orders collide.
    var createdAt: Date
    /// `.nullify` is what makes section removal safe: deleting the row clears membership on
    /// every member in the same save — archived threads included, which a fetch-and-clear loop
    /// over visible rows would miss.
    @Relationship(deleteRule: .nullify, inverse: \AgentThread.customSection)
    var threads: [AgentThread]

    init(
        id: String = UUID().uuidString,
        kind: SidebarSectionKind,
        name: String,
        sortOrder: Int,
        createdAt: Date = Date(),
        threads: [AgentThread] = []
    ) {
        self.id = id
        self.kindRawValue = kind.rawValue
        self.name = name
        self.sortOrder = sortOrder
        self.createdAt = createdAt
        self.threads = threads
    }
}

extension SidebarSection {
    var kind: SidebarSectionKind {
        get { SidebarSectionKind(rawValue: kindRawValue) ?? .custom }
        set { kindRawValue = newValue.rawValue }
    }

    var sectionID: SidebarSectionID {
        switch kind {
        case .pinned: .pinned
        case .projects: .projects
        case .tasks: .tasks
        case .custom: .custom(id)
        }
    }

    var descriptor: SidebarSectionDescriptor {
        SidebarSectionDescriptor(id: sectionID, name: kind.builtinDisplayName ?? name)
    }
}

enum SidebarSectionKind: String {
    case pinned
    case projects
    case tasks
    case custom

    /// Fixed labels for builtin rows; also the names custom sections may not collide with.
    var builtinDisplayName: String? {
        switch self {
        case .pinned: "Pinned"
        case .projects: "Projects"
        case .tasks: "Tasks"
        case .custom: nil
        }
    }

    /// Seed order for a fresh store, matching the sidebar's historical fixed layout.
    static let builtinSeedOrder: [SidebarSectionKind] = [.pinned, .projects, .tasks]
}

/// Model-independent section identity, safe to embed in view `@State`, geometry roles, drag
/// items, and drop targets — none of which may hold a `@Model` reference.
enum SidebarSectionID: Hashable {
    case pinned
    case projects
    case tasks
    case custom(String)

    var customID: String? {
        guard case .custom(let id) = self else {
            return nil
        }
        return id
    }
}

/// What the view layer renders a section from: identity plus display name, derived per pass
/// from `SidebarSection` rows and never cached.
struct SidebarSectionDescriptor: Identifiable, Equatable {
    let id: SidebarSectionID
    let name: String

    /// The pre-seed fixed layout, rendered until section rows exist so a store that was never
    /// sectioned looks exactly like a freshly seeded one.
    static let builtinFallback: [SidebarSectionDescriptor] = [
        SidebarSectionDescriptor(id: .pinned, name: SidebarSectionKind.pinned.builtinDisplayName ?? ""),
        SidebarSectionDescriptor(id: .projects, name: SidebarSectionKind.projects.builtinDisplayName ?? ""),
        SidebarSectionDescriptor(id: .tasks, name: SidebarSectionKind.tasks.builtinDisplayName ?? "")
    ]
}
