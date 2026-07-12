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
    }

    func createProject(path: String) async throws -> Project {
        let projectDetails = try await resolveProjectDetails(for: path)

        // Load the shared repo config once during import so later settings/worktree flows
        // reuse the same parse path. Invalid JSON intentionally degrades to defaults.
        _ = await AlvearyProjectConfig(projectPath: projectDetails.path)
        _ = try initializeSidebarOrderingForMutation()
        let sidebarSortOrder = try currentRegularProjectAppendOrder()

        let project = Project(
            path: projectDetails.path,
            name: URL(fileURLWithPath: projectDetails.path).lastPathComponent,
            gitRemote: projectDetails.remoteURL,
            remoteName: projectDetails.remoteName,
            gitBranch: projectDetails.gitBranch,
            baseRef: projectDetails.baseRef,
            githubRepository: projectDetails.githubRepository,
            githubConnected: projectDetails.githubConnected,
            sidebarSortOrder: sidebarSortOrder
        )
        modelContext.insert(project)
        try modelContext.save()
        return project
    }

    func resolveProjectDetails(for path: String) async throws -> ProjectImportDetails {
        let selectedPath = CanonicalPath.normalize(path)

        do {
            let projectPath = try await gitOutput(
                args: ["rev-parse", "--show-toplevel"],
                in: path
            )
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
