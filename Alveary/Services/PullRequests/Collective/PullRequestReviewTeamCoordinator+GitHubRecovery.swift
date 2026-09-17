import Foundation

struct ReviewTeamGitHubWait: Codable, Equatable, Sendable {
    let resumePhase: ReviewTeamRun.Phase
    let limit: GitHubRateLimit
}

/// A run supplies recovery for each read so a later quota failure cannot repeat earlier successful requests.
@MainActor
struct ReviewGitHubRecovery {
    var wait: ((PullRequestsServiceError) async throws -> Void)?
    var succeeded: (() throws -> Void)?

    func read<Value>(_ operation: () async throws -> Value) async throws -> Value {
        while true {
            do {
                let value = try await operation()
                try succeeded?()
                return value
            } catch let error as PullRequestsServiceError {
                guard let wait else { throw error }
                try await wait(error)
            }
        }
    }
}

/// Quota waits retain the current step's input and paid reports instead of restarting the pipeline.
extension PullRequestReviewTeamCoordinator {
    func restoreGitHubQuota(from conversations: [Conversation]) -> Task<Void, Never> {
        let limits = conversations.compactMap { conversation -> GitHubRateLimit? in
            guard let run = try? conversation.collectiveReviewRun(),
                  run.phase.isUnfinished || run.phase == .failed else { return nil }
            return run.gitHubWait?.limit
        }
        return Task { [service] in await service.restoreRateLimits(limits) }
    }

    func withGitHubRecovery<Value>(
        _ run: ReviewTeamRun, operation: @MainActor () async throws -> Value
    ) async throws -> Value {
        try await gitHubRecovery(run).read(operation)
    }

    func gitHubRecovery(_ run: ReviewTeamRun) -> ReviewGitHubRecovery {
        ReviewGitHubRecovery(
            wait: { try await self.waitAfterGitHubLimit($0, run: run) },
            succeeded: {
                // Staging may have atomically made the run terminal.
                if let current = try? self.requireActive(run.conversationID, generation: run.generation),
                   current.gitHubRateLimitFailures != nil {
                    try self.update(run.conversationID, generation: run.generation) { $0.gitHubRateLimitFailures = nil }
                }
            }
        )
    }

    func resumeGitHubWait(conversationID: String, generation: Int) async throws {
        let run = try requireActive(conversationID, generation: generation)
        guard let wait = run.gitHubWait else { return }
        try await waitForGitHub(wait.limit.retryAt)
        try update(conversationID, generation: generation) {
            $0.phase = wait.resumePhase
            $0.gitHubWait = nil
        }
    }

    /// History verifies owned bytes and digests; an old packet lease is never trusted after relaunch.
    func restorePreparedInput(_ run: ReviewTeamRun) async throws -> PreparedInput {
        guard let historyStore, let hash = run.inputHash,
              let attempt = run.history?.first(where: { $0.phase == .inspecting && $0.packetHash == hash }) else {
            throw ReviewTeamHistoryStoreError.missingArtifact
        }
        let detail = try await withGitHubRecovery(run) { try await self.service.fetchReviewContext(run.identifier) }
        guard detail.status == .open || detail.status == .draft, detail.viewerLogin != nil,
              detail.baseRefOid == run.baseOID, detail.headRefOid == run.headOID else { throw ReviewTeamError.revisionChanged }
        var files: [String: Data] = [:]
        for name in ["context.json", "changes.diff", "published-feedback.json", "prior-proposal.json"] {
            guard let artifact = attempt.inputs.first(where: { $0.name == name }) else {
                throw ReviewTeamHistoryStoreError.missingArtifact
            }
            files[name] = try await historyStore.read(artifact, conversationID: run.conversationID, runID: run.id)
        }
        _ = try requireActive(run.conversationID, generation: run.generation)
        let lease = try await packets.create(runID: run.id, files: files)
        guard lease.inputHash == hash, let diff = files["changes.diff"], let text = String(data: diff, encoding: .utf8) else {
            throw ReviewTeamHistoryStoreError.changedArtifact
        }
        let parsed = await Task.detached { DiffParser.parse(text) }.value
        guard parsed.count == detail.changedFiles else { throw ReviewTeamError.revisionChanged }
        return PreparedInput(detail: detail, files: parsed, packetFiles: files, lease: lease)
    }

    private func waitAfterGitHubLimit(_ error: PullRequestsServiceError, run: ReviewTeamRun) async throws {
        let limit: GitHubRateLimit
        switch error {
        case .rateLimit(let value): limit = value
        case .rateLimited:
            let failures = runs[run.conversationID]?.gitHubRateLimitFailures ?? 0
            limit = GitHubRateLimit(resource: "graphql", isSecondary: true,
                                   retryAt: Date().addingTimeInterval(60 * pow(2, Double(min(failures, 4)))))
        default: throw error
        }
        try update(run.conversationID, generation: run.generation) { current in
            if limit.isResponse { current.gitHubRateLimitFailures = (current.gitHubRateLimitFailures ?? 0) + 1 }
            current.preserveReviewInput = current.inputHash != nil
            current.gitHubWait = ReviewTeamGitHubWait(resumePhase: current.phase, limit: limit)
            current.phase = .waitingForGitHub
        }
        if (runs[run.conversationID]?.gitHubRateLimitFailures ?? 0) >= 5 {
            let time = limit.retryAt.formatted(date: .omitted, time: .standard)
            throw PullRequestsServiceError.transport("GitHub is still limiting requests after five attempts. Retry the review after \(time).")
        }
        try await resumeGitHubWait(conversationID: run.conversationID, generation: run.generation)
    }
}
