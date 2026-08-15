import Foundation
import SwiftData

/// Section-row invariants expressed over a `ModelContext`, mirroring `SidebarOrderNormalization`:
/// missing builtin rows are seeded, duplicate builtins collapse to one, membership pointing at a
/// builtin row clears, and `sortOrder` renumbers dense. Callers save — every entry point runs
/// inside someone else's save-with-rollback.
@MainActor
enum SidebarSectionNormalization {
    /// Repairs section rows and reports whether anything changed.
    @discardableResult
    static func normalize(
        in modelContext: ModelContext,
        now: () -> Date = Date.init,
        makeID: () -> String = { UUID().uuidString }
    ) throws -> Bool {
        var sections = try allSections(in: modelContext)
        var didChange = removeDuplicateBuiltins(&sections, in: modelContext)
        didChange = seedMissingBuiltins(&sections, in: modelContext, now: now, makeID: makeID) || didChange
        didChange = clearBuiltinMemberships(sections) || didChange
        didChange = renumber(sections) || didChange
        return didChange
    }

    static func allSections(in modelContext: ModelContext) throws -> [SidebarSection] {
        try modelContext.fetch(FetchDescriptor<SidebarSection>())
    }

    /// The persisted section order: dense `sortOrder` first, then deterministic tiebreaks so
    /// colliding orders (possible before normalization has run) resolve the same way every pass.
    static func orderedSections(_ sections: [SidebarSection]) -> [SidebarSection] {
        sections.sorted { lhs, rhs in
            if lhs.sortOrder != rhs.sortOrder {
                return lhs.sortOrder < rhs.sortOrder
            }
            let lhsSeed = builtinSeedIndex(lhs.kind)
            let rhsSeed = builtinSeedIndex(rhs.kind)
            if lhsSeed != rhsSeed {
                return lhsSeed < rhsSeed
            }
            if lhs.createdAt != rhs.createdAt {
                return lhs.createdAt < rhs.createdAt
            }
            return lhs.id < rhs.id
        }
    }
}

private extension SidebarSectionNormalization {
    static func builtinSeedIndex(_ kind: SidebarSectionKind) -> Int {
        SidebarSectionKind.builtinSeedOrder.firstIndex(of: kind) ?? SidebarSectionKind.builtinSeedOrder.count
    }

    /// One row per builtin kind: the ordered-first row survives, later twins are deleted. Their
    /// members need no rescue — builtin rows hold none once `clearBuiltinMemberships` has run,
    /// and `.nullify` covers any a twin still carried.
    static func removeDuplicateBuiltins(
        _ sections: inout [SidebarSection],
        in modelContext: ModelContext
    ) -> Bool {
        var seenKinds: Set<SidebarSectionKind> = []
        var didChange = false
        var survivors: [SidebarSection] = []
        for section in orderedSections(sections) {
            if section.kind != .custom, !seenKinds.insert(section.kind).inserted {
                modelContext.delete(section)
                didChange = true
                continue
            }
            survivors.append(section)
        }
        sections = survivors
        return didChange
    }

    /// Missing builtins seed at the historical fixed order on a fresh store and append at the
    /// end otherwise, so a partial state never reshuffles rows the user already ordered.
    static func seedMissingBuiltins(
        _ sections: inout [SidebarSection],
        in modelContext: ModelContext,
        now: () -> Date,
        makeID: () -> String
    ) -> Bool {
        let presentKinds = Set(sections.map(\.kind))
        let missingKinds = SidebarSectionKind.builtinSeedOrder.filter { !presentKinds.contains($0) }
        guard !missingKinds.isEmpty else {
            return false
        }
        var nextOrder = sections.isEmpty ? 0 : (sections.map(\.sortOrder).max() ?? -1) + 1
        for kind in missingKinds {
            let section = SidebarSection(
                id: makeID(),
                kind: kind,
                name: kind.builtinDisplayName ?? "",
                sortOrder: nextOrder,
                createdAt: now()
            )
            modelContext.insert(section)
            sections.append(section)
            nextOrder += 1
        }
        return true
    }

    /// Membership is meaningful only on custom sections; a thread pointing at a builtin row
    /// renders nowhere different, so the stale reference clears.
    static func clearBuiltinMemberships(_ sections: [SidebarSection]) -> Bool {
        var didChange = false
        for section in sections where section.kind != .custom {
            for thread in section.threads {
                thread.customSection = nil
                didChange = true
            }
        }
        return didChange
    }

    static func renumber(_ sections: [SidebarSection]) -> Bool {
        var didChange = false
        for (index, section) in orderedSections(sections).enumerated() where section.sortOrder != index {
            section.sortOrder = index
            didChange = true
        }
        return didChange
    }
}
