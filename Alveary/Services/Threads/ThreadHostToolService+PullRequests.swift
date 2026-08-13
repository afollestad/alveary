import AgentCLIKit
import Foundation
import SwiftData

extension ThreadHostToolService {
    /// Links a pull request to a thread. Immediate. A pull request the involved-list tool recently
    /// returned is stored from that row; anything else is validated by the same GitHub fetch the
    /// UI uses, so a mistyped or unreachable pull request is refused rather than stored.
    func linkPullRequest(
        context: AgentCLIKit.AgentHostToolCallContext,
        arguments: [String: AgentCLIKit.JSONValue]
    ) async throws -> AgentCLIKit.AgentHostToolResult {
        try flushPendingChanges()
        // Source first: a caller Alveary cannot place gets the source refusal, not an argument
        // critique of a request it was never entitled to make.
        let source = try resolveSource(context: context)
        let request = try parsePullRequestLink(arguments: arguments)
        let target = try pullRequestTarget(source: source, threadID: request.threadID)

        let outcome = try await linkService.link(
            request.identifier,
            owner: .thread(target.threadID),
            // The listed-then-linked flow — a scheduled run fanning out reviews — pays one search,
            // not one fetch per link; the search already proved these rows reachable.
            summary: summaryHandoff.summary(for: request.identifier)
        )
        switch outcome {
        case .linked(let link):
            return pullRequestResult(
                status: "linked",
                target: target,
                link: link,
                message: "Linked \(link.summary.id.displayKey) to the thread \"\(target.name)\" in Alveary. " +
                    "The pull request on GitHub is unchanged."
            )
        case .alreadyLinked(let link):
            return pullRequestResult(
                status: "already_linked",
                target: target,
                link: link,
                message: alreadyLinkedMessage(link.summary.id, target: target)
            )
        case .superseded:
            // The thread vanished mid-fetch, or a concurrent link landed. Neither is an error the
            // model can act on; re-listing is.
            throw ThreadHostToolServiceError.threadNotFound
        }
    }

    /// Removes Alveary's local link. Never touches the pull request on GitHub.
    func unlinkPullRequest(
        context: AgentCLIKit.AgentHostToolCallContext,
        arguments: [String: AgentCLIKit.JSONValue]
    ) async throws -> AgentCLIKit.AgentHostToolResult {
        try flushPendingChanges()
        let source = try resolveSource(context: context)
        let request = try parsePullRequestUnlink(arguments: arguments)
        let target = try pullRequestTarget(source: source, threadID: request.threadID)
        guard let identifier = try resolvedUnlinkIdentifier(request.identifier, target: target) else {
            return pullRequestResult(
                status: "not_linked",
                target: target,
                message: "The thread \"\(target.name)\" has no linked pull requests. Nothing changed."
            )
        }

        switch try linkService.unlink(identifier, owner: .thread(target.threadID)) {
        case .unlinked(let link):
            return pullRequestResult(
                status: "unlinked",
                target: target,
                link: link,
                message: "Removed \(link.summary.id.displayKey) from the thread \"\(target.name)\" in Alveary. " +
                    "The pull request itself was not closed, merged, or deleted."
            )
        case .notLinked:
            return pullRequestResult(
                status: "not_linked",
                target: target,
                identifier: identifier,
                message: "\(identifier.displayKey) was not linked to the thread \"\(target.name)\". Nothing changed."
            )
        case .ownerUnavailable:
            throw ThreadHostToolServiceError.threadNotFound
        }
    }

    /// Lists what a thread already carries, so the model can name one for `unlink_pr` without
    /// asking the user. Reads Alveary's stored snapshots only — nothing here calls GitHub.
    func listPullRequests(
        context: AgentCLIKit.AgentHostToolCallContext,
        arguments: [String: AgentCLIKit.JSONValue]
    ) throws -> AgentCLIKit.AgentHostToolResult {
        let source = try resolveSource(context: context)
        let threadID = try parseOptionalThreadIdentifier(arguments: arguments)
        let target = try pullRequestTarget(source: source, threadID: threadID)
        // Newest link first: the one the user means by "the PR" is usually the one just attached.
        let links = linkedPullRequests(for: target)
            .enumerated()
            .sorted { lhs, rhs in
                guard lhs.element.linkedAt == rhs.element.linkedAt else {
                    return lhs.element.linkedAt > rhs.element.linkedAt
                }
                // The stored array is append-ordered, so the later entry is the newer link. Two
                // links can share a timestamp — the clock's resolution is not the ordering.
                return lhs.offset > rhs.offset
            }
            .map(\.element)

        return AgentCLIKit.AgentHostToolResult(
            text: listText(
                header: "The thread \"\(target.name)\" has \(count(links.count, singular: "linked pull request"))",
                rows: links.map { "- \($0.id.displayKey) \($0.summary.title) (\($0.summary.status.rawValue))" }
            ),
            structuredContent: .object([
                "thread_id": .string(target.conversationID),
                "thread_name": .string(target.name),
                "pull_requests": .array(links.map(Self.structuredLink))
            ])
        )
    }
}

/// The thread a pull-request link acts on, resolved from trusted state.
private struct ThreadHostToolPullRequestTarget {
    let conversationID: String
    let threadID: PersistentIdentifier
    let name: String
}

private extension ThreadHostToolService {
    /// An omitted `thread_id` means the calling conversation's own thread, which is the common
    /// case; `list_threads` marks that row `is_current` so the default is not a guess.
    func pullRequestTarget(
        source: HostToolCallSource,
        threadID: String?
    ) throws -> ThreadHostToolPullRequestTarget {
        guard let threadID else {
            return ThreadHostToolPullRequestTarget(
                conversationID: source.conversation.id,
                threadID: source.thread.persistentModelID,
                name: source.thread.displayName()
            )
        }
        guard let conversation = modelContext.resolveConversation(conversationID: threadID),
              let thread = conversation.thread,
              !thread.isDraft,
              thread.archivedAt == nil else {
            throw ThreadHostToolServiceError.threadNotFound
        }
        return ThreadHostToolPullRequestTarget(
            conversationID: conversation.id,
            threadID: thread.persistentModelID,
            name: thread.displayName()
        )
    }

    func linkedPullRequests(for target: ThreadHostToolPullRequestTarget) -> [LinkedPullRequest] {
        modelContext.linkedPullRequests(for: .thread(target.threadID)) ?? []
    }

    /// With automatic linking on, Alveary links a pull request the moment its URL lands in a
    /// transcript message — including the very message asking for the link — so `link_pr` reaches
    /// an already-linked thread almost every time and a bare "already linked" reads as if the user
    /// asked twice. Naming the automatic link is the difference between a confusing report and a
    /// true one.
    func alreadyLinkedMessage(
        _ identifier: PullRequestIdentifier,
        target: ThreadHostToolPullRequestTarget
    ) -> String {
        let base = "\(identifier.displayKey) was already linked to the thread \"\(target.name)\". Nothing changed."
        // Both flags, matching the detection path's gate: with the PR feature off, automatic
        // linking never fires, and naming it would be a false explanation.
        let settings = settingsService.current
        guard settings.pullRequestsEnabled, settings.automaticallyLinkPullRequests else {
            return base
        }
        return base + " Alveary links pull requests automatically as soon as their URL appears in a conversation, " +
            "so it most likely linked this one itself rather than the user having asked twice."
    }

    /// An omitted `url` means "the pull request this thread carries", which is unambiguous only
    /// when it carries exactly one. `nil` means there is none to remove — already the end state the
    /// caller wanted — while several is a refusal that names them, so the model can call again
    /// instead of asking the user.
    func resolvedUnlinkIdentifier(
        _ identifier: PullRequestIdentifier?,
        target: ThreadHostToolPullRequestTarget
    ) throws -> PullRequestIdentifier? {
        if let identifier {
            return identifier
        }
        let links = linkedPullRequests(for: target)
        guard links.count <= 1 else {
            throw ThreadHostToolServiceError.ambiguousPullRequestUnlink(
                threadName: target.name,
                linked: links.map(\.id.displayKey).sorted()
            )
        }
        return links.first?.id
    }

    /// A `list_linked_prs` row: the same snapshot the mutating tools echo, plus the link's own
    /// timestamp, which is what makes the list orderable.
    static func structuredLink(_ link: LinkedPullRequest) -> AgentCLIKit.JSONValue {
        var row = snapshotFields(link)
        row["linked_at"] = .string(ThreadHostToolDates.canonical(link.linkedAt))
        return .object(row)
    }

    static func snapshotFields(_ link: LinkedPullRequest) -> [String: AgentCLIKit.JSONValue] {
        var fields: [String: AgentCLIKit.JSONValue] = [
            "repository": .string(link.summary.id.nameWithOwner),
            "number": .number(Double(link.summary.id.number)),
            "title": .string(link.summary.title),
            "status": .string(link.summary.status.rawValue)
        ]
        if let url = link.summary.url {
            fields["url"] = .string(url.absoluteString)
        }
        return fields
    }

    func pullRequestResult(
        status: String,
        target: ThreadHostToolPullRequestTarget,
        link: LinkedPullRequest,
        message: String
    ) -> AgentCLIKit.AgentHostToolResult {
        pullRequestResult(
            status: status,
            target: target,
            pullRequest: .object(Self.snapshotFields(link)),
            message: message
        )
    }

    /// The not-linked case has no stored snapshot, so it echoes only what the caller named.
    func pullRequestResult(
        status: String,
        target: ThreadHostToolPullRequestTarget,
        identifier: PullRequestIdentifier,
        message: String
    ) -> AgentCLIKit.AgentHostToolResult {
        pullRequestResult(
            status: status,
            target: target,
            pullRequest: .object([
                "repository": .string(identifier.nameWithOwner),
                "number": .number(Double(identifier.number))
            ]),
            message: message
        )
    }

    /// `pullRequest` is nil only when the caller named none and the thread carried none, so there
    /// is nothing to echo; `pull_request` is optional in the output schema for that case.
    func pullRequestResult(
        status: String,
        target: ThreadHostToolPullRequestTarget,
        pullRequest: AgentCLIKit.JSONValue? = nil,
        message: String
    ) -> AgentCLIKit.AgentHostToolResult {
        var content: [String: AgentCLIKit.JSONValue] = [
            "status": .string(status),
            "thread_id": .string(target.conversationID),
            "thread_name": .string(target.name),
            "message": .string(message)
        ]
        if let pullRequest {
            content["pull_request"] = pullRequest
        }
        return AgentCLIKit.AgentHostToolResult(text: message, structuredContent: .object(content))
    }
}
