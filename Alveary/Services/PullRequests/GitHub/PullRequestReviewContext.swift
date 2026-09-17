import Foundation

/// Revision validation deliberately excludes conversation data and always reads GitHub afresh.
struct PullRequestRevision: Equatable, Sendable {
    let status: PullRequestStatus
    let baseRefOid: String?
    let headRefOid: String?
}

/// The worker packet needs metadata, not the pane's checks, reactions, or conversation timeline.
struct PullRequestReviewContext: Equatable, Sendable {
    let title: String
    let bodyMarkdown: String
    let changedFiles: Int
    let authorLogin: String
    let viewerLogin: String?
    let revision: PullRequestRevision

    init(detail: PullRequestDetail) {
        title = detail.title
        bodyMarkdown = detail.bodyMarkdown
        changedFiles = detail.changedFiles
        authorLogin = detail.authorLogin
        viewerLogin = detail.viewerLogin
        revision = PullRequestRevision(status: detail.status, baseRefOid: detail.baseRefOid, headRefOid: detail.headRefOid)
    }

    var status: PullRequestStatus { revision.status }
    var baseRefOid: String? { revision.baseRefOid }
    var headRefOid: String? { revision.headRefOid }
}

extension PullRequestsService {
    func fetchReviewContext(_ id: PullRequestIdentifier) async throws -> PullRequestReviewContext {
        try await PullRequestReviewContext(detail: fetchDetail(id))
    }

    func fetchRevision(_ id: PullRequestIdentifier) async throws -> PullRequestRevision {
        try await fetchReviewContext(id).revision
    }
}
