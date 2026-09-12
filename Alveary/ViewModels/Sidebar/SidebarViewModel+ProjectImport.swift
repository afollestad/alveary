import Foundation
import SwiftData

extension SidebarViewModel {
    struct ProjectImportDetails {
        let path: String
        let gitBranch: String?
        let remoteName: String?
        let remoteURL: String?
        let baseRef: String?
        let githubRepository: String?
        let githubConnected: Bool

        var sourceFolder: SourceFolderSnapshot {
            SourceFolderSnapshot(
                path: path, gitRemote: remoteURL, remoteName: remoteName, gitBranch: gitBranch,
                baseRef: baseRef, githubRepository: githubRepository, githubConnected: githubConnected
            )
        }

    }

    func createProject(path: String) async throws -> Project {
        let projectDetails = try await resolveProjectDetails(for: path)

        // Load the shared repo config once during import so later settings/worktree flows
        // reuse the same parse path, and so the first selection of the new project renders
        // from cache. Invalid JSON intentionally degrades to defaults.
        await ProjectConfigStore.shared.reload(forProjectPath: projectDetails.path)
        return try saveProjectConfiguration(ProjectConfiguration(
            name: URL(fileURLWithPath: projectDetails.path).lastPathComponent,
            folders: [projectDetails.sourceFolder]
        ))
    }

    func resolveProjectDetails(for path: String) async throws -> ProjectImportDetails {
        let selectedPath = CanonicalPath.normalize(path)

        do {
            let projectPath = CanonicalPath.normalize(try await gitOutput(
                args: ["rev-parse", "--show-toplevel"],
                in: selectedPath
            ))
            let currentBranch = try await gitOutput(
                args: ["rev-parse", "--abbrev-ref", "HEAD"],
                in: projectPath
            )
            let remoteName = try await resolvePreferredRemoteName(
                in: projectPath,
                currentBranch: currentBranch
            )
            let remoteURL = try await resolveRemoteURL(in: projectPath, remoteName: remoteName)
            let githubRepository = remoteURL.flatMap(Project.parseGitHubRepository(from:))
            let githubConnected = await resolveGitHubConnectionState(for: githubRepository)
            let baseRef = try await resolveBaseRef(
                in: projectPath,
                remoteName: remoteName,
                fallbackBranch: currentBranch
            )

            return ProjectImportDetails(
                path: projectPath,
                gitBranch: currentBranch,
                remoteName: remoteName,
                remoteURL: remoteURL,
                baseRef: baseRef,
                githubRepository: githubRepository,
                githubConnected: githubConnected
            )
        } catch let error as GitError {
            guard error == .notARepository else {
                throw error
            }

            return ProjectImportDetails(
                path: selectedPath,
                gitBranch: nil,
                remoteName: nil,
                remoteURL: nil,
                baseRef: nil,
                githubRepository: nil,
                githubConnected: false
            )
        }
    }
}
