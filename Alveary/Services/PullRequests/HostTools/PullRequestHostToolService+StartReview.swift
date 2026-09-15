import AgentCLIKit
import Foundation

extension PullRequestHostToolService {
    /// Coalesces transport retries before any suspension; the durable receipt also survives a service replacement.
    func startPullRequestReview(
        context: AgentCLIKit.AgentHostToolCallContext,
        arguments: [String: AgentCLIKit.JSONValue]
    ) async throws -> AgentCLIKit.AgentHostToolResult {
        let source = try resolveSource(context: context)
        let identifier = try parseIdentifier(arguments: arguments)
        let payload = AgentCLIKit.JSONValue.object([
            "tool": .string(PullRequestHostToolCatalog.startReviewToolName),
            "repository": .string(identifier.nameWithOwner.lowercased()),
            "number": .number(Double(identifier.number))
        ])
        let identity = try callIdentity(
            context: context, source: source,
            canonicalPayloadHash: HostToolDeduplication.sha256(try HostToolDeduplication.canonicalJSON(payload))
        )
        try flushPendingChanges()
        if let pending = reviewLaunchCalls[identity.deduplicationKey] {
            return await pending.value
        }
        if let fallback = reviewLaunchFallbackReceipts[identity.deduplicationKey] {
            return reviewLaunchRecordedResult(fallback)
        }
        let receipt = try replayedReceipt(on: source.conversation, identity: identity)
        if let receipt, receipt.status != "pending_dispatch", receipt.status != "pending_existing" {
            return reviewLaunchRecordedResult(receipt)
        }
        let task = Task {
            if let receipt {
                return await resumeReviewLaunch(receipt, identity: identity, identifier: identifier, context: context)
            }
            return await performReviewLaunch(identifier: identifier, identity: identity, context: context)
        }
        reviewLaunchCalls[identity.deduplicationKey] = task
        defer { reviewLaunchCalls.removeValue(forKey: identity.deduplicationKey) }
        return await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }
    }
}

private extension PullRequestHostToolService {
    func performReviewLaunch(
        identifier: PullRequestIdentifier,
        identity: PullRequestHostToolCallIdentity,
        context: AgentCLIKit.AgentHostToolCallContext
    ) async -> AgentCLIKit.AgentHostToolResult {
        var identifier = identifier
        var destination: PullRequestAgenticThreadDestination?
        do {
            guard let reviewLauncher else {
                throw ReviewTeamError.invalidOutput("Review launching is unavailable. Try again after restarting Alveary.")
            }
            let detail = try await fetchDetail(identifier)
            if let url = detail.url, let canonical = PullRequestURLParser.identifier(from: url.absoluteString) {
                identifier = canonical
            }
            try validateReviewLaunchSource(context)
            let start = try await reviewLauncher.start(
                kind: .review, identifier: identifier,
                url: detail.url ?? Self.fallbackURL(for: identifier), knownDetail: detail,
                validateSource: { try self.validateReviewLaunchSource(context) },
                checkpoint: { target in
                    destination = target
                    try self.storeReviewLaunchResult(
                        self.reviewLaunchResult(
                            status: target.disposition == .created ? "pending_dispatch" : "pending_existing",
                            destination: target, identifier: identifier
                        ),
                        identity: identity, context: context
                    )
                }
            )
            destination = start.destination
            let outcome = try await start.dispatch.value
            let refreshed = try reviewLauncher.destination(
                conversationID: start.conversationID, disposition: start.destination.disposition
            )
            let result = reviewLaunchResult(
                status: refreshed.disposition == .created ? "started" : "existing",
                destination: refreshed, identifier: identifier, linkWarning: outcome.linkFailure
            )
            try storeReviewLaunchResult(result, identity: identity, context: context)
            return result
        } catch {
            if let launchError = error as? PullRequestAgenticThreadLaunchError {
                destination = launchError.destination
            }
            let result = reviewLaunchFailure(error, destination: destination, identifier: identifier)
            if destination != nil {
                storeReviewLaunchFailure(result, identity: identity, context: context)
            }
            return result
        }
    }

    func validateReviewLaunchSource(_ context: AgentCLIKit.AgentHostToolCallContext) throws {
        try Task.checkCancellation()
        guard settingsService.current.pullRequestsEnabled else {
            throw PullRequestHostToolServiceError.pullRequestsDisabled
        }
        _ = try resolveSource(context: context)
    }

    /// A saved destination never authorizes another launch, even if startup was interrupted by app termination.
    func resumeReviewLaunch(
        _ receipt: PullRequestHostToolReceipt,
        identity: PullRequestHostToolCallIdentity,
        identifier: PullRequestIdentifier,
        context: AgentCLIKit.AgentHostToolCallContext
    ) async -> AgentCLIKit.AgentHostToolResult {
        var destination: PullRequestAgenticThreadDestination?
        do {
            guard let reviewLauncher,
                  case .object(let content) = receipt.reviewLaunchResult,
                  case .string(let conversationID) = content["thread_id"] else {
                throw ReviewTeamError.invalidOutput("The saved review launch could not be restored.")
            }
            let disposition: PullRequestAgenticThreadDestination.Disposition = receipt.status == "pending_existing" ? .existing : .created
            destination = try reviewLauncher.destination(conversationID: conversationID, disposition: disposition)
            let outcome: PullRequestAgenticDispatchOutcome
            if let dispatch = reviewLauncher.dispatch(conversationID: conversationID) {
                outcome = try await dispatch.value
            } else if destination?.runID != nil {
                outcome = PullRequestAgenticDispatchOutcome(linkFailure: nil)
            } else {
                throw ReviewTeamError.invalidOutput("The review launch outcome is unavailable. Check its task before starting another review.")
            }
            let refreshed = try reviewLauncher.destination(conversationID: conversationID, disposition: disposition)
            let result = reviewLaunchResult(
                status: disposition == .created ? "started" : "existing",
                destination: refreshed, identifier: identifier, linkWarning: outcome.linkFailure
            )
            try storeReviewLaunchResult(result, identity: identity, context: context)
            return result
        } catch {
            return reviewLaunchFailure(error, destination: destination, identifier: identifier)
        }
    }

    func reviewLaunchResult(
        status: String,
        destination: PullRequestAgenticThreadDestination,
        identifier: PullRequestIdentifier,
        linkWarning: String? = nil,
        failure: String? = nil
    ) -> AgentCLIKit.AgentHostToolResult {
        let target = "the thread \"\(destination.name)\" (id: \(destination.conversationID))"
        var message: String
        if let failure {
            message = "Could not complete the review launch in \(target). \(failure)"
        } else if status == "existing" {
            message = "Review already exists in \(target). Open that task for progress or required action."
        } else if status == "pending_dispatch" || status == "pending_existing" {
            message = "Review launch is preparing in \(target)."
        } else {
            message = "Started the review in \(target). The review runs there and submits nothing without confirmation."
        }
        var fields: [String: AgentCLIKit.JSONValue] = [
            "repository": .string(identifier.nameWithOwner), "number": .number(Double(identifier.number)),
            "thread_id": .string(destination.conversationID), "name": .string(destination.name),
            "review_mode": .string(destination.reviewMode.rawValue)
        ]
        if let runID = destination.runID { fields["run_id"] = .string(runID) }
        if let phase = destination.phase {
            fields["phase"] = .string(phase.rawValue)
            message += " Review phase: \(phase.rawValue)."
        }
        if let linkWarning {
            fields["link_warning"] = .string(linkWarning)
            message += " Link warning: \(linkWarning)"
        }
        fields["status"] = .string(status)
        fields["message"] = .string(message)
        return AgentCLIKit.AgentHostToolResult(text: message, structuredContent: .object(fields), isError: failure != nil)
    }

    func reviewLaunchFailure(
        _ error: Error,
        destination: PullRequestAgenticThreadDestination?,
        identifier: PullRequestIdentifier
    ) -> AgentCLIKit.AgentHostToolResult {
        let underlying = (error as? PullRequestAgenticThreadLaunchError)?.underlying ?? error
        let message = underlying is CancellationError ? "The review launch was cancelled." : underlying.localizedDescription
        guard let destination else {
            return AgentCLIKit.AgentHostToolResult(
                text: message, structuredContent: .object(["status": .string("error"), "message": .string(message)]), isError: true
            )
        }
        return reviewLaunchResult(status: "error", destination: destination, identifier: identifier, failure: message)
    }
}
