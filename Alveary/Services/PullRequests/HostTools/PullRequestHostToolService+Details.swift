import AgentCLIKit
import Foundation
import SwiftData

extension PullRequestHostToolService {
    /// One pull request's current high-level state, plus which Alveary threads and projects link it.
    ///
    /// The linked owners come from Alveary's own columns rather than GitHub, which is what makes
    /// this the tool that connects a pull request back to the work happening on it.
    func pullRequestDetail(
        context: AgentCLIKit.AgentHostToolCallContext,
        arguments: [String: AgentCLIKit.JSONValue]
    ) async throws -> AgentCLIKit.AgentHostToolResult {
        _ = try resolveSource(context: context)
        let identifier = try parseIdentifier(arguments: arguments)
        let detail = try await fetchDetail(identifier)
        let owners = try linkedOwners(for: identifier)

        return AgentCLIKit.AgentHostToolResult(
            text: Self.detailText(detail, owners: owners),
            structuredContent: .object(structuredDetail(detail, owners: owners))
        )
    }
}

private extension PullRequestHostToolService {
    /// Threads and projects whose stored links name this pull request. The descriptors narrow to
    /// rows holding any link at all; the JSON columns are opaque to `#Predicate`, so the lookup
    /// decodes and matches those in Swift.
    func linkedOwners(for identifier: PullRequestIdentifier) throws -> [PullRequestLinkingOwner] {
        do {
            let projects = try modelContext.fetch(PullRequestLinkedOwnerLookup.linkHoldingProjects)
            let threads = try modelContext.fetch(PullRequestLinkedOwnerLookup.linkHoldingThreads)
            return PullRequestLinkedOwnerLookup.owners(
                projects: projects,
                threads: threads,
                linking: identifier
            )
        } catch {
            throw PullRequestHostToolServiceError.persistenceFailure
        }
    }

    func structuredDetail(
        _ detail: PullRequestDetail,
        owners: [PullRequestLinkingOwner]
    ) -> [String: AgentCLIKit.JSONValue] {
        let description = PullRequestHostToolJSON.truncated(
            detail.bodyMarkdown,
            limit: PullRequestHostToolLimits.maxDescriptionCharacters
        )
        var content: [String: AgentCLIKit.JSONValue] = [
            "repository": .string(detail.id.nameWithOwner),
            "number": .number(Double(detail.id.number)),
            "title": .string(detail.title),
            "status": .string(detail.status.rawValue),
            "author": PullRequestHostToolJSON.author(
                login: detail.authorLogin,
                avatarURL: detail.authorAvatarURL
            ),
            "head_branch": .string(detail.headRefName),
            "base_branch": .string(detail.baseRefName),
            "additions": .number(Double(detail.additions)),
            "deletions": .number(Double(detail.deletions)),
            "changed_files": .number(Double(detail.changedFiles)),
            "description_markdown": .string(description.text),
            "description_truncated": .bool(description.wasTruncated),
            "reviewers": .array(detail.reviewers.map(Self.structuredReviewer)),
            "checks": Self.structuredChecks(detail.checks),
            "linked_threads": .array(Self.structuredThreads(owners)),
            "linked_projects": .array(Self.structuredProjects(owners)),
            "counts": .object([
                "comments": .number(Double(detail.comments.count)),
                "review_threads": .number(Double(detail.reviewThreads.count)),
                "unresolved_threads": .number(Double(detail.reviewThreads.filter { !$0.isResolved }.count))
            ]),
            "viewer": Self.structuredViewer(detail)
        ]
        if let url = detail.url {
            content["url"] = .string(url.absoluteString)
        }
        if let createdAt = detail.createdAt {
            content["created_at"] = .string(PullRequestHostToolDates.canonical(createdAt))
        }
        if let updatedAt = detail.updatedAt {
            content["updated_at"] = .string(PullRequestHostToolDates.canonical(updatedAt))
        }
        if !detail.reactions.isEmpty {
            content["description_reactions"] = PullRequestHostToolJSON.reactions(detail.reactions)
        }
        if let reviewDecision = detail.reviewDecision {
            content["review_decision"] = .string(reviewDecision)
        }
        return content
    }

    static func structuredViewer(_ detail: PullRequestDetail) -> AgentCLIKit.JSONValue {
        var viewer: [String: AgentCLIKit.JSONValue] = [
            "has_pending_review": .bool(detail.pendingReviewNodeID != nil),
            "pending_comment_count": .number(Double(detail.pendingCommentCount))
        ]
        if let login = detail.viewerLogin {
            viewer["login"] = .string(login)
        }
        return .object(viewer)
    }

    static func structuredChecks(_ checks: [PullRequestCheck]) -> AgentCLIKit.JSONValue {
        .object([
            "passing": .number(Double(checks.filter { $0.state == .passing }.count)),
            "failing": .number(Double(checks.filter { $0.state == .failing }.count)),
            "pending": .number(Double(checks.filter { $0.state == .pending }.count))
        ])
    }

    static func structuredReviewer(_ reviewer: PullRequestReviewer) -> AgentCLIKit.JSONValue {
        var row: [String: AgentCLIKit.JSONValue] = [
            "login": .string(reviewer.login),
            "state": .string(reviewerStateName(reviewer.state)),
            "is_bot": .bool(reviewer.isBot)
        ]
        if let avatarURL = reviewer.avatarURL {
            row["avatar_url"] = .string(avatarURL.absoluteString)
        }
        return .object(row)
    }

    static func reviewerStateName(_ state: PullRequestReviewer.State) -> String {
        switch state {
        case .requested:
            "requested"
        case .approved:
            "approved"
        case .changesRequested:
            "changes_requested"
        case .commented:
            "commented"
        }
    }

    /// A thread's ID here is the same sole-main-conversation handle `list_threads` hands out, so a
    /// linked thread can be named to the thread tools directly. A forked thread has none, and is
    /// listed by name alone rather than dropped.
    static func structuredThreads(_ owners: [PullRequestLinkingOwner]) -> [AgentCLIKit.JSONValue] {
        owners.compactMap { owner in
            guard case .thread(let thread) = owner else {
                return nil
            }
            var row: [String: AgentCLIKit.JSONValue] = ["name": .string(thread.displayName())]
            if let conversationID = thread.soleMainConversation?.id {
                row["thread_id"] = .string(conversationID)
            }
            return .object(row)
        }
    }

    static func structuredProjects(_ owners: [PullRequestLinkingOwner]) -> [AgentCLIKit.JSONValue] {
        owners.compactMap { owner in
            guard case .project(let project) = owner else {
                return nil
            }
            return .object([
                "name": .string(project.name),
                "path": .string(project.path)
            ])
        }
    }

    static func detailText(
        _ detail: PullRequestDetail,
        owners: [PullRequestLinkingOwner]
    ) -> String {
        var lines = [
            "\(detail.id.displayKey) \(detail.title)",
            "Status: \(detail.status.rawValue), by \(detail.authorLogin)",
            "Branch: \(detail.headRefName) into \(detail.baseRefName)",
            "Changes: +\(detail.additions)/-\(detail.deletions) across \(detail.changedFiles) file(s)"
        ]
        if detail.reviewers.isEmpty {
            lines.append("Reviewers: none")
        } else {
            let reviewers = detail.reviewers
                .map { "\($0.login) (\(reviewerStateName($0.state)))" }
                .joined(separator: ", ")
            lines.append("Reviewers: \(reviewers)")
        }
        if !owners.isEmpty {
            lines.append("Linked in Alveary: \(owners.map(\.displayName).joined(separator: ", "))")
        }
        if detail.pendingReviewNodeID != nil {
            lines.append(
                "The user has an unsubmitted review draft with " +
                    "\(detail.pendingCommentCount) pending comment(s)."
            )
        }
        let description = PullRequestHostToolJSON.truncated(
            detail.bodyMarkdown,
            limit: PullRequestHostToolLimits.maxDescriptionCharacters
        )
        if !description.text.isEmpty {
            lines.append("")
            lines.append(description.text)
        }
        return lines.joined(separator: "\n")
    }
}
