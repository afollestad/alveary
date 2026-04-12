enum CIStatus: Sendable, Equatable {
    case pass
    case fail
    case pending
    case none
}

struct PRInfo: Identifiable, Sendable, Equatable {
    var id: Int { number }

    let number: Int
    let title: String
    let url: String
    let state: String
    let headRefName: String
    let ciStatus: CIStatus
}

protocol GitHubService: Sendable {
    func listPRs(in directory: String) async throws -> [PRInfo]
    func checkRunStatus(prNumber: Int, in directory: String) async throws -> CIStatus
    func checkoutPRBranch(prNumber: Int, branchName: String, in directory: String) async throws
}
