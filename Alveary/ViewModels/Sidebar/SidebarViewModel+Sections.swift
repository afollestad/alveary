import Foundation
import SwiftData

/// The windowed half of custom-section mutations: delegate to `SidebarSectionService`, then
/// refresh whatever thread ordering the mutation moved. Section-row changes themselves reach the
/// view through its `SidebarSection` query, so only thread-moving mutations refresh here.
extension SidebarViewModel {
    @discardableResult
    func createSection(name: String) throws -> SidebarSectionService.CreateOutcome {
        try sectionService.createSection(name: name)
    }

    @discardableResult
    func renameSection(id: String, to newName: String) throws -> SidebarSectionDescriptor {
        try sectionService.renameSection(id: id, to: newName)
    }

    /// Removes the section; its member threads land in `Tasks`, so the thread order refreshes.
    @discardableResult
    func removeSection(id: String) throws -> Int {
        let movedCount = try sectionService.removeSection(id: id)
        refreshThreadOrder(animated: true)
        return movedCount
    }

    @discardableResult
    func moveThreadToSection(
        threadID: PersistentIdentifier,
        target: SidebarSectionService.MoveTarget
    ) throws -> SidebarSectionService.MoveOutcome {
        let outcome = try sectionService.moveThread(threadID: threadID, to: target)
        if outcome == .moved {
            refreshThreadOrder(animated: true)
        }
        return outcome
    }

    @discardableResult
    func moveSection(id: SidebarSectionID, before anchorID: SidebarSectionID?) throws -> Bool {
        try sectionService.moveSection(id: id, before: anchorID)
    }
}
