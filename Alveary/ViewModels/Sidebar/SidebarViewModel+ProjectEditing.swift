import Foundation
import SwiftData

extension SidebarViewModel {
    /// Import already resolved each new path. Do not resolve it again here: Save commits the path the form showed.
    func saveProjectConfiguration(
        _ configuration: ProjectConfiguration,
        projectID: String? = nil,
        save: (ModelContext) throws -> Void = { try $0.save() }
    ) throws -> Project {
        let configuration = try configuration.validated()
        if modelContext.hasChanges { try modelContext.save() }
        var draftChanges: [DraftProjectWorkspaceChange] = []
        var insertedFolders: [ProjectFolder] = []
        var previousMembership: ProjectMembershipRollback?
        do {
            let project: Project
            if let projectID {
                guard let existing = modelContext.resolveProject(projectID: projectID) else { throw SidebarViewModelError.projectMissing }
                project = existing
                previousMembership = ProjectMembershipRollback(project: project)
                replaceProjectFolders(configuration, in: project, insertedFolders: &insertedFolders)
                project.name = configuration.name
                try refreshProjectDraftWorkspaces(project, changes: &draftChanges)
            } else {
                _ = try initializeSidebarOrderingForMutation()
                project = Project(
                    name: configuration.name, sidebarSortOrder: try currentRegularProjectAppendOrder(),
                    folders: configuration.folders, primaryFolderPath: configuration.primaryFolderPath
                )
                modelContext.insert(project)
            }
            try save(modelContext)
            for change in draftChanges {
                if let oldWorkspace = change.previous.privateWorkspace, oldWorkspace != change.privateWorkspace {
                    releaseDraftWorkspace(oldWorkspace)
                }
                publishDraftWorkspaceChanged(change.thread, placementChanged: false)
            }
            NotificationCenter.default.post(name: .workspaceConfigurationChanged, object: nil)
            return project
        } catch {
            rollbackProjectConfiguration(draftChanges: draftChanges, insertedFolders: insertedFolders)
            do {
                try previousMembership?.restore(in: modelContext)
            } catch let rollbackError {
                throw ProjectMembershipRollbackError(original: error, rollback: rollbackError)
            }
            throw error
        }
    }

    private func rollbackProjectConfiguration(draftChanges: [DraftProjectWorkspaceChange], insertedFolders: [ProjectFolder]) {
        for change in draftChanges {
            change.previous.restore(change.thread)
            if let newWorkspace = change.privateWorkspace, newWorkspace != change.previous.privateWorkspace {
                releaseDraftWorkspace(newWorkspace)
            }
        }
        // Rollback can leave a transient membership in a persisted project's cached inverse.
        // Unlink new rows while their backing objects are still live.
        for folder in insertedFolders { folder.project = nil }
        modelContext.rollback()
    }

    private func replaceProjectFolders(
        _ configuration: ProjectConfiguration, in project: Project, insertedFolders: inout [ProjectFolder]
    ) {
        let previous = project.orderedFolders
        var existing = Dictionary(uniqueKeysWithValues: previous.map { ($0.path, $0) })
        let replacements = configuration.folders.enumerated().map { index, source in
            let folder: ProjectFolder
            if let retained = existing.removeValue(forKey: source.path) {
                folder = retained
            } else {
                folder = ProjectFolder(snapshot: source, sortOrder: index)
                modelContext.insert(folder)
                insertedFolders.append(folder)
            }
            folder.apply(source, sortOrder: index)
            folder.project = project
            return folder
        }
        for folder in existing.values {
            _ = folder.snapshot
            modelContext.delete(folder)
        }
        project.folders = replacements
        project.primaryFolderID = replacements.first { $0.path == configuration.primaryFolderPath }?.id
    }
}

/// SwiftData rollback does not reliably restore cached to-many inverses. Resolve the saved rows
/// after rollback and rebuild both sides from their pre-edit identities, including an empty list.
@MainActor
private struct ProjectMembershipRollback {
    let projectID: String
    let name: String
    let primaryFolderID: String?
    let folders: [Folder]

    struct Folder {
        let id: String
        let source: SourceFolderSnapshot
        let sortOrder: Int
    }

    init(project: Project) {
        projectID = project.id
        name = project.name
        primaryFolderID = project.primaryFolderID
        folders = project.orderedFolders.map { Folder(id: $0.id, source: $0.snapshot, sortOrder: $0.sortOrder) }
    }

    func restore(in context: ModelContext) throws {
        guard let project = context.resolveProject(projectID: projectID) else {
            throw SidebarViewModelError.projectMissing
        }
        let savedIDs = folders.map(\.id)
        let restoredFolders = try context.fetch(FetchDescriptor<ProjectFolder>(predicate: #Predicate { savedIDs.contains($0.id) }))
        let byID = Dictionary(uniqueKeysWithValues: restoredFolders.map { ($0.id, $0) })
        guard restoredFolders.count == savedIDs.count else { throw WorkspaceFolderError.invalidSnapshot }
        for saved in folders { byID[saved.id]?.apply(saved.source, sortOrder: saved.sortOrder) }
        project.folders = savedIDs.compactMap { byID[$0] }
        for folder in project.folders { folder.project = project }
        project.name = name
        project.primaryFolderID = primaryFolderID
    }
}

private extension ProjectFolder {
    func apply(_ source: SourceFolderSnapshot, sortOrder: Int) {
        path = source.path
        self.sortOrder = sortOrder
        gitRemote = source.gitRemote
        remoteName = source.remoteName
        gitBranch = source.gitBranch
        baseRef = source.baseRef
        githubRepository = source.githubRepository
        githubConnected = source.githubConnected
    }
}

private struct ProjectMembershipRollbackError: LocalizedError {
    let original: Error
    let rollback: Error

    var errorDescription: String? {
        "Project save failed: \(original.localizedDescription). Folder restoration also failed: \(rollback.localizedDescription)"
    }
}
