import Foundation

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
