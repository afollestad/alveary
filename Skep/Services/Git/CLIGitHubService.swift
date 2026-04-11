import Foundation

final class CLIGitHubService: GitHubService, @unchecked Sendable {
    private let ghCLI: GitHubCLIService

    init(ghCLI: GitHubCLIService) {
        self.ghCLI = ghCLI
    }

    func listPRs(in directory: String) async throws -> [PRInfo] {
        let result = try await ghCLI.run(
            args: ["pr", "list", "--state", "open", "--json", "number,title,url,state,headRefName,statusCheckRollup"],
            in: directory
        )
        guard result.succeeded else {
            throw GitError.commandFailed(result.stderr.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        guard let data = result.stdout.data(using: .utf8),
              let payload = try? JSONDecoder().decode([PullRequestPayload].self, from: data) else {
            return []
        }

        return payload.map {
            PRInfo(
                number: $0.number,
                title: $0.title,
                url: $0.url,
                state: $0.state,
                headRefName: $0.headRefName,
                ciStatus: Self.aggregateCIStatus($0.statusCheckRollup ?? [])
            )
        }
    }

    func checkRunStatus(prNumber: Int, in directory: String) async throws -> CIStatus {
        let result = try await ghCLI.run(
            args: ["pr", "view", "\(prNumber)", "--json", "statusCheckRollup"],
            in: directory
        )
        guard result.succeeded else {
            throw GitError.commandFailed(result.stderr.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        guard let data = result.stdout.data(using: .utf8),
              let payload = try? JSONDecoder().decode(PullRequestStatusPayload.self, from: data) else {
            return .none
        }

        return Self.aggregateCIStatus(payload.statusCheckRollup ?? [])
    }

    func checkoutPRBranch(prNumber: Int, branchName: String, in directory: String) async throws {
        let result = try await ghCLI.run(
            args: ["pr", "checkout", "\(prNumber)", "--branch", branchName, "--force"],
            in: directory
        )
        guard result.succeeded else {
            throw GitError.commandFailed(result.stderr.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }
}

private extension CLIGitHubService {
    static func aggregateCIStatus(_ checks: [CheckRollupPayload]) -> CIStatus {
        guard !checks.isEmpty else {
            return .none
        }

        var hasPending = false

        for check in checks {
            switch check.aggregateCIStatus() {
            case .fail:
                return .fail
            case .pending:
                hasPending = true
            case .pass, .none:
                break
            }
        }

        return hasPending ? .pending : .pass
    }
}

private struct PullRequestPayload: Decodable {
    let number: Int
    let title: String
    let url: String
    let state: String
    let headRefName: String
    let statusCheckRollup: [CheckRollupPayload]?
}

private struct PullRequestStatusPayload: Decodable {
    let statusCheckRollup: [CheckRollupPayload]?
}

private struct CheckRollupPayload: Decodable {
    let typeName: String?
    let conclusion: String?
    let status: String?
    let state: String?

    enum CodingKeys: String, CodingKey {
        case typeName = "__typename"
        case conclusion
        case status
        case state
    }
}

private extension CheckRollupPayload {
    func aggregateCIStatus() -> CIStatus {
        if typeName == "StatusContext" {
            return statusContextCIStatus()
        }

        switch conclusion?.uppercased() {
        case "FAILURE", "ERROR":
            return .fail
        case nil, "":
            return .pending
        default:
            break
        }

        switch status?.uppercased() {
        case "QUEUED", "IN_PROGRESS", "PENDING":
            return .pending
        default:
            return .pass
        }
    }

    private func statusContextCIStatus() -> CIStatus {
        switch state?.uppercased() {
        case "FAILURE", "ERROR":
            return .fail
        case "EXPECTED", "PENDING":
            return .pending
        default:
            return .pass
        }
    }
}
