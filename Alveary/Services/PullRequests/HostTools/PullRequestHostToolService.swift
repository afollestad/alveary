import AgentCLIKit
import Foundation
import SwiftData

/// The `alveary_host` pull request tools: read a pull request, comment on it, and propose a review.
///
/// Unlike the other host-tool features these reach GitHub, through the same `PullRequestsService`
/// the pull request pane uses. Only `propose_pr_review` needs the user's confirmation — everything
/// else here is undoable from Alveary's own UI or from github.com.
@MainActor
final class PullRequestHostToolService {
    let modelContext: ModelContext
    let pullRequestsService: any PullRequestsService
    let settingsService: any SettingsService
    /// Required rather than defaulted so a construction site must choose the shared instance —
    /// a private one would compile and silently degrade every `link_pr` back to a fetch.
    let summaryHandoff: PullRequestSummaryHandoff
    /// Seeded at propose time with the diff this service already parsed to validate anchors, so the
    /// transcript card paints its comments without refetching it. Optional because most tests build
    /// the service without one, and a miss only costs the card its usual load.
    let reviewProposalPreviewCache: PullRequestReviewProposalPreviewCache?
    let notificationCenter: NotificationCenter
    private let requestParser: PullRequestHostToolRequestParser
    private let now: () -> Date
    private let proposalIDProvider: () -> String

    init(
        modelContext: ModelContext,
        pullRequestsService: any PullRequestsService,
        settingsService: any SettingsService,
        summaryHandoff: PullRequestSummaryHandoff,
        reviewProposalPreviewCache: PullRequestReviewProposalPreviewCache? = nil,
        notificationCenter: NotificationCenter = .default,
        requestParser: PullRequestHostToolRequestParser = PullRequestHostToolRequestParser(),
        now: @escaping () -> Date = Date.init,
        makeProposalID: @escaping () -> String = { UUID().uuidString }
    ) {
        proposalIDProvider = makeProposalID
        self.modelContext = modelContext
        self.pullRequestsService = pullRequestsService
        self.settingsService = settingsService
        self.summaryHandoff = summaryHandoff
        self.reviewProposalPreviewCache = reviewProposalPreviewCache
        self.notificationCenter = notificationCenter
        self.requestParser = requestParser
        self.now = now
    }

    func handle(
        context: AgentCLIKit.AgentHostToolCallContext,
        call: AgentCLIKit.AgentHostToolCall
    ) async -> AgentCLIKit.AgentHostToolResult {
        do {
            // The whole integration is gated by one setting; with it off the pane the user would
            // check the result in does not exist, so no tool here may act.
            guard settingsService.current.pullRequestsEnabled else {
                throw PullRequestHostToolServiceError.pullRequestsDisabled
            }
            if let result = try await readOnlyResult(context: context, call: call) {
                return result
            }
            let result = try await mutatingResult(context: context, call: call)
            announceChange(for: call)
            return result
        } catch {
            return errorResult(for: error, toolName: call.name)
        }
    }

    /// Tells an open pull request pane to reload after a mutation it cannot see. Announced once
    /// here rather than from each handler, so a tool added later inherits it; every refusal throws
    /// into the `catch` above, so reaching this line means the call landed.
    ///
    /// `propose_pr_review` is excluded: it writes only Alveary's own envelope, which the pane
    /// already re-reads on every render.
    private func announceChange(for call: AgentCLIKit.AgentHostToolCall) {
        guard call.name != PullRequestHostToolCatalog.proposeReviewToolName,
              // Not `parseIdentifier`, whose `requireOnly(["url"])` rejects the further arguments
              // these tools carry; the handler has already proven the URL parses.
              case .string(let url)? = call.arguments["url"],
              let identifier = PullRequestURLParser.identifier(from: url) else {
            return
        }
        notificationCenter.post(
            name: .pullRequestChangedOnGitHub,
            object: self,
            userInfo: [
                PullRequestChangeNotificationKey.announcement: PullRequestChangeAnnouncement(
                    identifier: identifier,
                    affectsListRow: PullRequestHostToolCatalog.stateChangeToolNames.contains(call.name)
                )
            ]
        )
    }

    /// nil when the call names no read-only tool, so `handle` falls through to the mutating ones.
    private func readOnlyResult(
        context: AgentCLIKit.AgentHostToolCallContext,
        call: AgentCLIKit.AgentHostToolCall
    ) async throws -> AgentCLIKit.AgentHostToolResult? {
        switch call.name {
        case PullRequestHostToolCatalog.listToolName:
            return try await listPullRequests(context: context, arguments: call.arguments)
        case PullRequestHostToolCatalog.detailToolName:
            return try await pullRequestDetail(context: context, arguments: call.arguments)
        case PullRequestHostToolCatalog.timelineToolName:
            return try await pullRequestTimeline(context: context, arguments: call.arguments)
        case PullRequestHostToolCatalog.diffToolName:
            return try await pullRequestDiff(context: context, arguments: call.arguments)
        case PullRequestHostToolCatalog.reviewInstructionsToolName:
            return try await pullRequestReviewInstructions(context: context, arguments: call.arguments)
        case PullRequestHostToolCatalog.addressFeedbackInstructionsToolName:
            return try await pullRequestAddressFeedbackInstructions(context: context, arguments: call.arguments)
        default:
            return nil
        }
    }

    private func mutatingResult(
        context: AgentCLIKit.AgentHostToolCallContext,
        call: AgentCLIKit.AgentHostToolCall
    ) async throws -> AgentCLIKit.AgentHostToolResult {
        if let result = try await stateChangingResult(context: context, call: call) {
            return result
        }
        switch call.name {
        case PullRequestHostToolCatalog.replyToThreadToolName:
            return try await replyToThread(context: context, arguments: call.arguments)
        case PullRequestHostToolCatalog.resolveThreadToolName:
            return try await setThreadResolved(context: context, arguments: call.arguments, resolved: true)
        case PullRequestHostToolCatalog.unresolveThreadToolName:
            return try await setThreadResolved(context: context, arguments: call.arguments, resolved: false)
        case PullRequestHostToolCatalog.commentToolName:
            return try await commentOnPullRequest(context: context, arguments: call.arguments)
        case PullRequestHostToolCatalog.proposeReviewToolName:
            return try await proposeReview(context: context, arguments: call.arguments)
        default:
            throw PullRequestHostToolServiceError.unsupportedTool
        }
    }

    /// nil when the call names no state-change tool, so `mutatingResult` falls through to the rest.
    private func stateChangingResult(
        context: AgentCLIKit.AgentHostToolCallContext,
        call: AgentCLIKit.AgentHostToolCall
    ) async throws -> AgentCLIKit.AgentHostToolResult? {
        switch call.name {
        case PullRequestHostToolCatalog.closeToolName:
            return try await closePullRequest(context: context, arguments: call.arguments)
        case PullRequestHostToolCatalog.reopenToolName:
            return try await reopenPullRequest(context: context, arguments: call.arguments)
        case PullRequestHostToolCatalog.markReadyToolName:
            return try await markPullRequestReady(context: context, arguments: call.arguments)
        case PullRequestHostToolCatalog.markDraftToolName:
            return try await convertPullRequestToDraft(context: context, arguments: call.arguments)
        default:
            return nil
        }
    }

    // MARK: - Parsing

    func parseListRequest(
        arguments: [String: AgentCLIKit.JSONValue]
    ) throws -> PullRequestHostToolListRequest {
        try requestParser.parseListRequest(arguments: arguments)
    }

    func parseIdentifier(arguments: [String: AgentCLIKit.JSONValue]) throws -> PullRequestIdentifier {
        try requestParser.parseIdentifier(arguments: arguments)
    }

    func parseTimeline(
        arguments: [String: AgentCLIKit.JSONValue]
    ) throws -> PullRequestHostToolTimelineRequest {
        try requestParser.parseTimeline(arguments: arguments)
    }

    func parseDiff(arguments: [String: AgentCLIKit.JSONValue]) throws -> PullRequestHostToolDiffRequest {
        try requestParser.parseDiff(arguments: arguments)
    }

    func parseThreadReply(
        arguments: [String: AgentCLIKit.JSONValue]
    ) throws -> PullRequestHostToolThreadReplyRequest {
        try requestParser.parseThreadReply(arguments: arguments)
    }

    func parseThreadResolution(
        arguments: [String: AgentCLIKit.JSONValue]
    ) throws -> PullRequestHostToolResolutionRequest {
        try requestParser.parseThreadResolution(arguments: arguments)
    }

    func parseComment(
        arguments: [String: AgentCLIKit.JSONValue]
    ) throws -> PullRequestHostToolCommentRequest {
        try requestParser.parseComment(arguments: arguments)
    }

    func parseReviewProposal(
        arguments: [String: AgentCLIKit.JSONValue]
    ) throws -> PullRequestHostToolReviewProposalRequest {
        try requestParser.parseReviewProposal(arguments: arguments)
    }

    func requestDate() -> Date {
        now()
    }

    func makeProposalID() -> String {
        proposalIDProvider()
    }

    // MARK: - Source resolution

    /// The shared host-tool resolution, with this feature's error vocabulary.
    func resolveSource(
        context: AgentCLIKit.AgentHostToolCallContext
    ) throws -> HostToolCallSource {
        do {
            return try HostToolSourceResolver.resolveSource(context: context, in: modelContext)
        } catch HostToolSourceError.sourceProviderMismatch {
            throw PullRequestHostToolServiceError.sourceProviderMismatch
        } catch {
            throw PullRequestHostToolServiceError.sourceConversationUnavailable
        }
    }

    /// Closing is the one mutation an automated scheduled run may not make. Every other tool here
    /// serves one — a scheduled task acts on the user's standing instruction, each change is
    /// undoable, and the review proposal still waits for the user — but a closed pull request
    /// drops out of review flows, so closing stays a live-conversation decision.
    func refuseAutomatedScheduledRunClose(
        context: AgentCLIKit.AgentHostToolCallContext
    ) throws {
        let source = try resolveSource(context: context)
        let hasLiveScheduledRun = source.thread.scheduledTaskRun.map { !$0.hasKnownTerminalStatus } ?? false
        if hasLiveScheduledRun || source.thread.hasBlockingScheduledTaskRunAttachment {
            throw PullRequestHostToolServiceError.automatedRunCannotClosePullRequest
        }
    }

    func requireRequestID(_ context: AgentCLIKit.AgentHostToolCallContext) throws -> String {
        guard let requestID = context.requestId?.trimmingCharacters(in: .whitespacesAndNewlines),
              !requestID.isEmpty else {
            throw PullRequestHostToolServiceError.missingRequestIdentity
        }
        return requestID
    }

    // MARK: - GitHub access

    /// Every GitHub read goes through here so a service failure reaches the model as a reachability
    /// message it can act on rather than a generic host error.
    func fetchDetail(_ identifier: PullRequestIdentifier) async throws -> PullRequestDetail {
        do {
            return try await pullRequestsService.fetchDetail(identifier)
        } catch let error as PullRequestsServiceError {
            throw Self.unavailable(error)
        }
    }

    func fetchDiff(_ identifier: PullRequestIdentifier) async throws -> String {
        do {
            return try await pullRequestsService.fetchDiff(identifier)
        } catch PullRequestsServiceError.responseTooLarge {
            throw PullRequestHostToolServiceError.diffTooLarge
        } catch let error as PullRequestsServiceError {
            throw Self.unavailable(error)
        }
    }

    static func unavailable(_ error: PullRequestsServiceError) -> PullRequestHostToolServiceError {
        .pullRequestUnavailable(error.errorDescription ?? error.localizedDescription)
    }

    // MARK: - Persistence

    func flushPendingChanges() throws {
        guard modelContext.hasChanges else {
            return
        }
        do {
            try modelContext.save()
        } catch {
            throw PullRequestHostToolServiceError.persistenceFailure
        }
    }

    func save() throws {
        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw PullRequestHostToolServiceError.persistenceFailure
        }
    }

    // MARK: - Results

    /// The rows go into the text as well as `structuredContent`: a plain-text-fallback provider
    /// sees only the text, and the transcript's Output section shows the same string.
    func listText(header: String, rows: [String]) -> String {
        rows.isEmpty ? "\(header)." : "\(header):\n\(rows.joined(separator: "\n"))"
    }

    func count(_ value: Int, singular: String) -> String {
        value == 1 ? "1 \(singular)" : "\(value) \(singular)s"
    }

    /// A mutating tool's result: `message` is the text fallback verbatim, so both channels say the
    /// same thing.
    func mutationResult(
        status: String,
        message: String,
        fields: [String: AgentCLIKit.JSONValue] = [:]
    ) -> AgentCLIKit.AgentHostToolResult {
        var content = fields
        content["status"] = .string(status)
        content["message"] = .string(message)
        return AgentCLIKit.AgentHostToolResult(text: message, structuredContent: .object(content))
    }

    func errorResult(
        for error: Error,
        toolName: String
    ) -> AgentCLIKit.AgentHostToolResult {
        let message: String
        switch error {
        case let requestError as HostToolRequestError:
            message = requestError.localizedDescription
        case let serviceError as PullRequestHostToolServiceError:
            message = serviceError.localizedDescription
        case let pullRequestError as PullRequestsServiceError:
            // A GitHub reachability failure is the model's to report, not Alveary's to swallow as
            // a generic persistence problem.
            message = Self.unavailable(pullRequestError).localizedDescription
        default:
            message = PullRequestHostToolServiceError.persistenceFailure.localizedDescription
        }
        let structuredContent: AgentCLIKit.JSONValue? =
            PullRequestHostToolCatalog.mutatingToolNames.contains(toolName)
            ? .object(["status": .string("error"), "message": .string(message)])
            : nil
        return AgentCLIKit.AgentHostToolResult(text: message, structuredContent: structuredContent, isError: true)
    }
}

extension PullRequestHostToolService: HostToolFeature {
    var featureID: String {
        PullRequestHostToolCatalog.featureID
    }

    /// Derived from the catalog so routing cannot drift from what the server advertises.
    var hostToolNames: Set<String> {
        Set(PullRequestHostToolCatalog.tools.map(\.name))
    }
}
