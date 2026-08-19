import Foundation
import SwiftData

/// App-scoped custom-section lifecycle: create, rename, remove, reorder, and thread membership.
///
/// `SidebarViewModel` is per-window, but the `alveary_host` thread tools mutate sections with no
/// window at all, so both route through this service over the shared `mainContext` — the
/// `ThreadLifecycleService` split. It holds no state; every mutation flushes unrelated pending
/// work first, then commits in one save with rollback, so a refused mutation discards nothing.
@MainActor
final class SidebarSectionService {
    /// Custom names are capped so sidebar labels and the every-turn MCP catalog stay sane.
    /// `nonisolated` so the error enum's description can name the limit.
    nonisolated static let maximumNameLength = 64

    let modelContext: ModelContext
    private let saveSectionChanges: @MainActor (ModelContext) throws -> Void
    private let now: () -> Date
    private let makeID: () -> String
    private let notificationCenter: NotificationCenter

    init(
        modelContext: ModelContext,
        saveSectionChanges: @escaping @MainActor (ModelContext) throws -> Void = { try $0.save() },
        now: @escaping () -> Date = Date.init,
        makeID: @escaping () -> String = { UUID().uuidString },
        notificationCenter: NotificationCenter = .default
    ) {
        self.modelContext = modelContext
        self.saveSectionChanges = saveSectionChanges
        self.now = now
        self.makeID = makeID
        self.notificationCenter = notificationCenter
    }

    /// Posted after every successful mutating save. The sidebar sees section changes through its
    /// own `@Query`, but window-less observers — the Scheduled editor's Section options — have no
    /// query and would otherwise never learn about a section created mid-session, including by
    /// the `create_section` host tool.
    func publishSectionsChanged() {
        notificationCenter.post(name: .sidebarSectionsChanged, object: self)
    }

    enum CreateOutcome: Equatable {
        case created(SidebarSectionDescriptor)
        /// A live section (builtin display names included) already carries this name,
        /// compared case-insensitively — idempotent success, not an error.
        case alreadyExists(SidebarSectionDescriptor)
    }

    enum MoveTarget: Equatable {
        case tasks
        case custom(sectionID: String)
    }

    enum MoveOutcome: Equatable {
        case moved
        /// Already resting in the target: right membership, projectless, and unpinned.
        case alreadyThere
    }

    /// Seeds missing builtin rows and repairs section invariants, reporting whether anything
    /// changed. Safe to call every launch; every other entry point runs it inside its own save.
    @discardableResult
    func ensureBuiltinSections() throws -> Bool {
        try flushPendingChanges()
        do {
            guard try normalizeSections() else {
                return false
            }
            try saveSectionChanges(modelContext)
            return true
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    /// Every section in persisted order, builtins included — the MCP tools' view of the sidebar.
    func orderedSections() throws -> [SidebarSectionDescriptor] {
        try ensureBuiltinSections()
        return try orderedSectionRows().map(\.descriptor)
    }

    /// Case-insensitive lookup across custom names and builtin display names.
    func section(named name: String) throws -> SidebarSectionDescriptor? {
        let target = Self.normalizedName(name)
        return try orderedSections().first {
            $0.name.caseInsensitiveCompare(target) == .orderedSame
        }
    }

    func createSection(name: String) throws -> CreateOutcome {
        let validatedName = try Self.validatedSectionName(name)
        try flushPendingChanges()
        do {
            let didNormalize = try normalizeSections()
            if let existing = try existingSection(named: validatedName) {
                if didNormalize {
                    try saveSectionChanges(modelContext)
                }
                return .alreadyExists(existing)
            }
            // Normalization renumbered densely, so the append slot equals the count.
            let section = SidebarSection(
                id: makeID(),
                kind: .custom,
                name: validatedName,
                sortOrder: try SidebarSectionNormalization.allSections(in: modelContext).count,
                createdAt: now()
            )
            modelContext.insert(section)
            try saveSectionChanges(modelContext)
            publishSectionsChanged()
            return .created(section.descriptor)
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    func renameSection(id: String, to newName: String) throws -> SidebarSectionDescriptor {
        let validatedName = try Self.validatedSectionName(newName)
        try flushPendingChanges()
        do {
            try normalizeSections()
            let section = try requireCustomSection(id: id)
            if let existing = try existingSection(named: validatedName),
               existing.id != section.sectionID {
                throw SidebarSectionServiceError.duplicateName(existing: existing.name)
            }
            section.name = validatedName
            try saveSectionChanges(modelContext)
            publishSectionsChanged()
            return section.descriptor
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    /// Removes a custom section; `.nullify` clears membership on every member — archived
    /// included — in the same save, so they all fall back to `Tasks`. Returns the member count.
    @discardableResult
    func removeSection(id: String) throws -> Int {
        try flushPendingChanges()
        do {
            try normalizeSections()
            let section = try requireCustomSection(id: id)
            let memberCount = section.threads.count
            modelContext.delete(section)
            try normalizeSections()
            try saveSectionChanges(modelContext)
            publishSectionsChanged()
            return memberCount
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    /// Reorders `sectionID` to sit immediately before `anchorID` (nil appends to the end).
    /// Anchoring on a neighbor rather than taking a full permutation lets the caller pass only
    /// the sections it can see: a hidden section between the two keeps its relative slot.
    @discardableResult
    func moveSection(id sectionID: SidebarSectionID, before anchorID: SidebarSectionID?) throws -> Bool {
        try flushPendingChanges()
        do {
            var didChange = try normalizeSections()
            var ordered = SidebarSectionNormalization.orderedSections(
                try SidebarSectionNormalization.allSections(in: modelContext)
            )
            guard let movingIndex = ordered.firstIndex(where: { $0.sectionID == sectionID }) else {
                throw SidebarSectionServiceError.sectionMissing
            }
            let moving = ordered.remove(at: movingIndex)
            let insertionIndex: Int
            if let anchorID {
                guard let anchorIndex = ordered.firstIndex(where: { $0.sectionID == anchorID }) else {
                    throw SidebarSectionServiceError.sectionMissing
                }
                insertionIndex = anchorIndex
            } else {
                insertionIndex = ordered.count
            }
            ordered.insert(moving, at: insertionIndex)
            for (index, section) in ordered.enumerated() where section.sortOrder != index {
                section.sortOrder = index
                didChange = true
            }
            guard didChange else {
                return false
            }
            try saveSectionChanges(modelContext)
            publishSectionsChanged()
            return true
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    /// Moves a task thread's sidebar placement in ONE save, and is the sole commit behind both of
    /// the drag's membership drops: unpin, detach from any project, then set or clear
    /// membership. Unpinning is deliberate — reporting "moved" while the row
    /// visibly stays under `Pinned` would be the lie the absorbed-pin refusal exists to prevent.
    ///
    /// Placement is the only thing that changes: the Task keeps its workspace grants, so leaving a
    /// project does not pull folder access out from under an agent mid-work.
    func moveThread(threadID: PersistentIdentifier, to target: MoveTarget) throws -> MoveOutcome {
        try flushPendingChanges()
        var restorePlacement: (() -> Void)?
        do {
            let didNormalize = try normalizeSections()
            guard let thread = modelContext.resolveThread(id: threadID),
                  thread.archivedAt == nil,
                  !thread.isDraft else {
                throw SidebarViewModelError.threadMissing
            }
            guard thread.effectiveMode == .task else {
                throw SidebarSectionServiceError.threadNotEligible
            }
            let targetSection: SidebarSection?
            switch target {
            case .tasks:
                targetSection = nil
            case .custom(let sectionID):
                targetSection = try requireCustomSection(id: sectionID)
            }
            if thread.customSection?.id == targetSection?.id, thread.project == nil, !thread.isPinned {
                // A no-op move still commits any rows normalization just seeded, so the context
                // never holds unsaved inserts a later unrelated rollback would discard.
                if didNormalize {
                    try saveSectionChanges(modelContext)
                }
                return .alreadyThere
            }
            restorePlacement = applyPlacement(of: thread, membership: targetSection)
            try SidebarOrderNormalization.normalize(in: modelContext)
            try saveSectionChanges(modelContext)
            return .moved
        } catch {
            modelContext.rollback()
            restorePlacement?()
            throw error
        }
    }

    /// Applies `moveThread`'s placement mutation — unpin, detach, set or clear membership — and
    /// returns its undo, captured before mutating. The failure path runs that undo *after*
    /// `rollback()`: macOS 26's rollback restores the scalar pin flag but drops changes whose old
    /// or new value is nil — the cleared sort order and the set membership survive it — so the
    /// catch repairs the thread's placement itself rather than trusting rollback alone.
    private func applyPlacement(of thread: AgentThread, membership targetSection: SidebarSection?) -> () -> Void {
        let captured = (
            isPinned: thread.isPinned,
            pinnedSortOrder: thread.pinnedSortOrder,
            project: thread.project,
            customSection: thread.customSection
        )
        if thread.isPinned {
            thread.isPinned = false
            thread.pinnedSortOrder = nil
        }
        thread.project = nil
        thread.customSection = targetSection
        return {
            thread.isPinned = captured.isPinned
            thread.pinnedSortOrder = captured.pinnedSortOrder
            thread.project = captured.project
            thread.customSection = captured.customSection
        }
    }
}

extension SidebarSectionService {
    static func normalizedName(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Shared name validation for the UI and MCP: trimmed, non-empty, capped.
    static func validatedSectionName(_ name: String) throws -> String {
        let trimmed = normalizedName(name)
        guard !trimmed.isEmpty else {
            throw SidebarSectionServiceError.invalidName
        }
        guard trimmed.count <= maximumNameLength else {
            throw SidebarSectionServiceError.nameTooLong
        }
        return trimmed
    }
}

private extension SidebarSectionService {
    func flushPendingChanges() throws {
        guard modelContext.hasChanges else {
            return
        }
        try saveSectionChanges(modelContext)
    }

    @discardableResult
    func normalizeSections() throws -> Bool {
        try SidebarSectionNormalization.normalize(in: modelContext, now: now, makeID: makeID)
    }

    func orderedSectionRows() throws -> [SidebarSection] {
        SidebarSectionNormalization.orderedSections(
            try SidebarSectionNormalization.allSections(in: modelContext)
        )
    }

    func existingSection(named name: String) throws -> SidebarSectionDescriptor? {
        try orderedSectionRows()
            .map(\.descriptor)
            .first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
    }

    func requireCustomSection(id: String) throws -> SidebarSection {
        guard let section = modelContext.resolveSidebarSection(id: id) else {
            throw SidebarSectionServiceError.sectionMissing
        }
        guard section.kind == .custom else {
            throw SidebarSectionServiceError.builtinSectionImmutable
        }
        return section
    }
}

enum SidebarSectionServiceError: LocalizedError, Equatable {
    case invalidName
    case nameTooLong
    case duplicateName(existing: String)
    case builtinSectionImmutable
    case sectionMissing
    /// Only projectless task-mode threads live in sidebar sections.
    case threadNotEligible

    var errorDescription: String? {
        switch self {
        case .invalidName:
            return "Section names cannot be empty"
        case .nameTooLong:
            return "Section names are limited to \(SidebarSectionService.maximumNameLength) characters"
        case .duplicateName(let existing):
            return "A section named \"\(existing)\" already exists"
        case .builtinSectionImmutable:
            return "Built-in sections cannot be renamed or removed"
        case .sectionMissing:
            return "Section no longer exists"
        case .threadNotEligible:
            return "Only task threads can be placed in sidebar sections"
        }
    }
}
