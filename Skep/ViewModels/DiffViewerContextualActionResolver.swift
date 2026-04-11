import Foundation

@MainActor
final class DiffViewerContextualActionResolver {
    private let gitService: GitService
    private let gitHubService: GitHubService

    private var cachedPRs: [PRInfo]?
    private var prCacheTime: Date = .distantPast

    private static let prCacheTTL: TimeInterval = 60

    init(gitService: GitService, gitHubService: GitHubService) {
        self.gitService = gitService
        self.gitHubService = gitHubService
    }

    func determineAction(
        files: [FileStatus],
        baseRef: String,
        remoteName: String?,
        directory: String
    ) async -> DiffViewerContextualAction {
        if !files.isEmpty {
            return .commit
        }

        async let aheadTask = (try? await gitService.commitsAheadOfBase(
            baseBranch: baseRef,
            remoteName: remoteName,
            in: directory
        )) ?? 0
        async let currentBranchTask = try? await gitService.currentBranch(in: directory)
        async let prsTask = cachedListPRs(in: directory)

        let ahead = await aheadTask
        let currentBranch = await currentBranchTask
        let prs = await prsTask

        if let pullRequest = prs.first(where: { $0.state == "OPEN" && $0.headRefName == currentBranch }) {
            return .viewPR(url: pullRequest.url)
        }
        if ahead > 0 {
            return .openPR
        }
        return .none
    }

    func invalidatePRCache() {
        cachedPRs = nil
        prCacheTime = .distantPast
    }

    private func cachedListPRs(in directory: String) async -> [PRInfo] {
        if let cachedPRs,
           Date().timeIntervalSince(prCacheTime) < Self.prCacheTTL {
            return cachedPRs
        }

        do {
            let pullRequests = try await gitHubService.listPRs(in: directory)
            cachedPRs = pullRequests
            prCacheTime = Date()
            return pullRequests
        } catch {
            return cachedPRs ?? []
        }
    }
}
