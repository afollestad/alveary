import AgentCLIKit
import Foundation

/// Tool waits are bounded independently of shared preparation, including the detail read.
extension PullRequestHostToolService {
    func pullRequestDiff(
        context: AgentCLIKit.AgentHostToolCallContext,
        arguments: [String: AgentCLIKit.JSONValue]
    ) async throws -> AgentCLIKit.AgentHostToolResult {
        _ = try resolveSource(context: context)
        let request = try parseDiff(arguments: arguments)
        let source = context.conversationId.rawValue
        let cursor: PullRequestHostToolDiffCursor
        if let continued = request.cursor {
            cursor = continued
        } else {
            let service = pullRequestsService
            let identifier = request.identifier
            let job = await diffJobs.start(key: UUID().uuidString) {
                async let snapshot = service.fetchDiffSnapshot(identifier)
                async let detail = service.fetchDetail(identifier)
                let session = try await PullRequestHostToolDiffSession(
                    snapshot: snapshot, detail: detail, source: source, identifier: identifier, paths: request.paths
                )
                if let head = session.snapshot.headOID,
                   head != session.detail.headRefOid || session.snapshot.baseOID != session.detail.baseRefOid {
                    throw PullRequestDiffError.revisionChanged
                }
                return session
            }
            cursor = PullRequestHostToolDiffCursor(job: job, identifier: identifier, paths: request.paths, file: request.offset)
        }
        let session: PullRequestHostToolDiffSession?
        do {
            session = try await diffJobs.value(id: cursor.job, wait: diffWait)
        } catch PullRequestsServiceError.responseTooLarge {
            throw PullRequestHostToolServiceError.diffTooLarge
        } catch let error as PullRequestsServiceError {
            throw Self.unavailable(error)
        }
        guard let session else { return try Self.preparingDiff(cursor: cursor) }
        guard session.source == source, session.identifier == cursor.identifier else {
            throw HostToolRequestError.invalidArguments("cursor belongs to a different conversation or pull request.")
        }
        var resolvedCursor = cursor
        resolvedCursor.paths = session.paths
        let page = PullRequestHostToolDiffPage(session: session, cursor: resolvedCursor)
        let result = try await Task.detached {
            try page.render()
        }.value
        reviewedDiffRevisions["\(source):\(request.identifier.displayKey)"] = (session.snapshot.baseOID, session.snapshot.headOID)
        return result
    }

    private static func preparingDiff(cursor: PullRequestHostToolDiffCursor) throws -> AgentCLIKit.AgentHostToolResult {
        let token = try cursor.encoded()
        let guidance = "The complete diff is still preparing. Call get_pr_diff again with cursor \(token)."
        return AgentCLIKit.AgentHostToolResult(
            text: guidance,
            structuredContent: .object([
                "status": .string("preparing"), "repository": .string(cursor.identifier.nameWithOwner),
                "number": .number(Double(cursor.identifier.number)), "next_cursor": .string(token),
                "guidance": .string(guidance)
            ])
        )
    }
}
