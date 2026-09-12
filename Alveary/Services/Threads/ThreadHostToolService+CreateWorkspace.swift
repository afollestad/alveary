import Foundation

extension ThreadHostToolService {
    func validatedWorkspace(
        _ requested: ThreadHostToolRequestedWorkspace,
        placement: ThreadHostToolSourcePlacement
    ) async throws -> ThreadHostToolCreateWorkspace {
        switch requested {
        case let .project(key, primaryPath, grants, isID, privateWorkspace):
            let project = isID ? modelContext.resolveProject(projectID: key) : modelContext.resolveProject(path: key)
            guard let project else { throw ThreadHostToolServiceError.projectNotRegistered(path: key) }
            if let primaryPath, !project.orderedFolders.contains(where: { $0.path == primaryPath }) {
                throw ThreadHostToolServiceError.grantedRootUnavailable(path: primaryPath)
            }
            let defaults = project.workspaceSnapshot(primaryPath: primaryPath)
            let snapshot = privateWorkspace
                ? WorkspaceSnapshot(primarySource: nil, grants: defaults.sourceFolders) : defaults
            let projectID = project.id
            return ThreadHostToolCreateWorkspace(
                snapshot: try await replacingGrants(grants, in: snapshot), placement: .project(id: projectID)
            )
        case let .task(grants, sectionName):
            var snapshot = placement.snapshot ?? WorkspaceSnapshot(primarySource: nil)
            snapshot = WorkspaceSnapshot(primarySource: nil, grants: snapshot.sourceFolders)
            let explicitDestination = try sectionName.map { name in
                try resolvedSectionID(named: name).map { TaskThreadSidebarPlacement.section(id: $0) } ?? .tasks
            }
            let grantedSnapshot = try await replacingGrants(grants, in: snapshot)
            return ThreadHostToolCreateWorkspace(
                snapshot: grantedSnapshot, placement: explicitDestination ?? inheritedTaskPlacement(placement)
            )
        case .inherit(let grants, let sectionName):
            guard let snapshot = placement.snapshot else { throw ThreadHostToolServiceError.sourcePlacementUnavailable }
            let explicitDestination = try sectionName.map { name in
                try resolvedSectionID(named: name).map { TaskThreadSidebarPlacement.section(id: $0) } ?? .tasks
            }
            let grantedSnapshot = try await replacingGrants(grants, in: snapshot)
            // An inherited placement may disappear during discovery; only an explicit choice remains binding.
            return ThreadHostToolCreateWorkspace(
                snapshot: grantedSnapshot, placement: explicitDestination ?? inheritedTaskPlacement(placement), useWorktree: placement.useWorktree
            )
        }
    }

    /// Retained grants keep their literal paths; only newly supplied access is canonicalized.
    private func replacingGrants(_ roots: [String]?, in original: WorkspaceSnapshot) async throws -> WorkspaceSnapshot {
        var snapshot = original
        snapshot.rootsExplicitlyManaged = true
        if let roots {
            var grants: [SourceFolderSnapshot] = []
            for path in roots {
                if let saved = original.sourceFolders.first(where: { $0.path == path }) {
                    grants.append(saved)
                    continue
                }
                guard let normalized = try canonicalGrantedRoots([path]).first else {
                    throw ThreadHostToolServiceError.grantedRootUnavailable(path: path)
                }
                if let saved = original.sourceFolders.first(where: { $0.path == normalized }) {
                    grants.append(saved)
                } else {
                    let folder = await resolveSourceFolder(normalized)
                    try Task.checkCancellation()
                    guard folder.path == normalized else {
                        throw ThreadHostToolServiceError.grantedRootUnavailable(path: path)
                    }
                    grants.append(folder)
                }
            }
            snapshot.grants = grants
        }
        snapshot = WorkspaceSnapshot(primarySource: snapshot.primarySource, grants: snapshot.grants)
        // Do not silently redirect a saved path through a replacement symlink.
        for folder in snapshot.sourceFolders {
            _ = try WorkspaceFolderTarget(directory: folder.path, source: folder, isPrimary: true).requireDirectory()
            guard CanonicalPath.normalize(folder.path) == folder.path else {
                throw ThreadHostToolServiceError.grantedRootUnavailable(path: folder.path)
            }
        }
        return snapshot
    }

    private func inheritedTaskPlacement(_ placement: ThreadHostToolSourcePlacement) -> TaskThreadSidebarPlacement {
        if let id = placement.projectID, modelContext.resolveProject(projectID: id) != nil { return .project(id: id) }
        if let id = placement.sectionID, modelContext.resolveSidebarSection(id: id)?.kind == .custom { return .section(id: id) }
        return .tasks
    }

    /// The section a `create_thread` request named, as a `SidebarSection.id`.
    ///
    /// `Tasks` resolves to nil — a Task with no membership already renders there — and every other
    /// built-in is refused, because a thread cannot live in `Pinned` or `Projects`. An unknown name
    /// is refused rather than created: composing `create_section` first keeps a typo from silently
    /// minting a section the user never asked for.
    func resolvedSectionID(named sectionName: String) throws -> String? {
        let match = try sectionMatch(named: sectionName)
        switch match.id {
        case .tasks:
            return nil
        case .custom(let sectionID):
            return sectionID
        case .pinned, .projects:
            throw ThreadHostToolServiceError.sectionNotCustom(name: match.name)
        }
    }

    /// Each grant must be an absolute path to an existing folder and is stored canonically
    /// resolved — the same rule `propose_scheduled_task`'s `granted_roots` follows — so a symlink
    /// spelling cannot show the user one folder while granting another. Two spellings of the same
    /// folder collapse, which the parser's literal duplicate check cannot see.
    func canonicalGrantedRoots(_ requested: [String]) throws -> [String] {
        var canonical: [String] = []
        for path in requested {
            guard path.hasPrefix("/") else {
                throw ThreadHostToolServiceError.grantedRootUnavailable(path: path)
            }
            let normalized = CanonicalPath.normalize(path)
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: normalized, isDirectory: &isDirectory),
                  isDirectory.boolValue else {
                throw ThreadHostToolServiceError.grantedRootUnavailable(path: path)
            }
            if !canonical.contains(normalized) {
                canonical.append(normalized)
            }
        }
        return canonical
    }
}
