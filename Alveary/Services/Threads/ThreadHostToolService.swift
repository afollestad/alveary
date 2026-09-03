import AgentCLIKit
import Foundation
import SwiftData

/// The `alveary_host` thread tools: list, create, archive, and send a prompt into another thread.
/// Never delete — no tool here removes a thread, and none should be added.
@MainActor
final class ThreadHostToolService {
    let modelContext: ModelContext
    let lifecycleService: ThreadLifecycleService
    /// Shared with `SidebarViewModel`, so a section the user just made is immediately nameable
    /// here and a tool-made one appears in the sidebar without a refresh.
    let sectionService: SidebarSectionService
    let linkService: PullRequestLinkService
    /// Must be the same instance the pull request tools write, or `link_pr` silently degrades
    /// back to a fetch per link; required in the initializer so a construction site must choose.
    let summaryHandoff: PullRequestSummaryHandoff
    let settingsService: SettingsService
    let providerDiscovery: (any AgentCLIKit.AgentProviderDiscoveryService)?
    /// Starts a created thread's first turn headlessly. Fire-and-forget: `create_thread` reports
    /// dispatch, never the turn's outcome.
    let startInitialPrompt: @MainActor (Conversation, String) -> Void
    /// Posts a relayed prompt into an existing thread and reports whether it started a turn or
    /// queued behind one. Awaited, unlike `startInitialPrompt`, because `send_prompt_to_thread`
    /// answers with that distinction; required so a construction site must choose.
    let deliverPrompt: @MainActor (Conversation, OutboundMessageText) async throws -> RelayedPromptDelivery
    private let requestParser: ThreadHostToolRequestParser
    private let now: () -> Date

    init(
        modelContext: ModelContext,
        lifecycleService: ThreadLifecycleService,
        sectionService: SidebarSectionService,
        linkService: PullRequestLinkService,
        summaryHandoff: PullRequestSummaryHandoff,
        settingsService: SettingsService,
        providerDiscovery: (any AgentCLIKit.AgentProviderDiscoveryService)? = nil,
        startInitialPrompt: @escaping @MainActor (Conversation, String) -> Void = { _, _ in },
        deliverPrompt: @escaping @MainActor (Conversation, OutboundMessageText) async throws -> RelayedPromptDelivery,
        requestParser: ThreadHostToolRequestParser = ThreadHostToolRequestParser(),
        now: @escaping () -> Date = Date.init
    ) {
        self.modelContext = modelContext
        self.lifecycleService = lifecycleService
        self.sectionService = sectionService
        self.linkService = linkService
        self.summaryHandoff = summaryHandoff
        self.settingsService = settingsService
        self.providerDiscovery = providerDiscovery
        self.startInitialPrompt = startInitialPrompt
        self.deliverPrompt = deliverPrompt
        self.requestParser = requestParser
        self.now = now
    }

    func handle(
        context: AgentCLIKit.AgentHostToolCallContext,
        call: AgentCLIKit.AgentHostToolCall
    ) async -> AgentCLIKit.AgentHostToolResult {
        do {
            if let result = try readOnlyResult(context: context, call: call) {
                return result
            }
            return try await mutatingResult(context: context, call: call)
        } catch {
            return errorResult(for: error, toolName: call.name)
        }
    }

    /// nil when the call names no read-only tool, so `handle` falls through to the mutating ones.
    /// A tool added to `mutatingResult` must also join `ThreadHostToolCatalog.mutatingToolNames`,
    /// or its failures lose the `status` field its output schema promises.
    private func readOnlyResult(
        context: AgentCLIKit.AgentHostToolCallContext,
        call: AgentCLIKit.AgentHostToolCall
    ) throws -> AgentCLIKit.AgentHostToolResult? {
        switch call.name {
        case ThreadHostToolCatalog.listThreadsToolName:
            try listThreads(context: context, arguments: call.arguments)
        case ThreadHostToolCatalog.listProjectsToolName:
            try listProjects(context: context, arguments: call.arguments)
        case ThreadHostToolCatalog.listPullRequestsToolName:
            try listPullRequests(context: context, arguments: call.arguments)
        default:
            nil
        }
    }

    private func mutatingResult(
        context: AgentCLIKit.AgentHostToolCallContext,
        call: AgentCLIKit.AgentHostToolCall
    ) async throws -> AgentCLIKit.AgentHostToolResult {
        switch call.name {
        case ThreadHostToolCatalog.createThreadToolName:
            return try await createThread(context: context, arguments: call.arguments)
        case ThreadHostToolCatalog.archiveThreadToolName:
            return try await archiveThread(context: context, arguments: call.arguments)
        case ThreadHostToolCatalog.linkPullRequestToolName:
            return try await linkPullRequest(context: context, arguments: call.arguments)
        case ThreadHostToolCatalog.unlinkPullRequestToolName:
            return try await unlinkPullRequest(context: context, arguments: call.arguments)
        case ThreadHostToolCatalog.pinThreadToolName:
            return try await setThreadPinned(context: context, arguments: call.arguments, isPinned: true)
        case ThreadHostToolCatalog.unpinThreadToolName:
            return try await setThreadPinned(context: context, arguments: call.arguments, isPinned: false)
        case ThreadHostToolCatalog.createSectionToolName:
            return try createSection(context: context, arguments: call.arguments)
        case ThreadHostToolCatalog.moveThreadToSectionToolName:
            return try moveThreadToSection(context: context, arguments: call.arguments)
        case ThreadHostToolCatalog.sendPromptToThreadToolName:
            return try await sendPromptToThread(context: context, arguments: call.arguments)
        default:
            throw ThreadHostToolServiceError.unsupportedTool
        }
    }

    func parseCreate(arguments: [String: AgentCLIKit.JSONValue]) throws -> ThreadHostToolParsedCreateRequest {
        try requestParser.parseCreate(arguments: arguments)
    }

    func parseSendPrompt(arguments: [String: AgentCLIKit.JSONValue]) throws -> ThreadHostToolParsedSendPromptRequest {
        try requestParser.parseSendPrompt(arguments: arguments)
    }

    func parseArchive(arguments: [String: AgentCLIKit.JSONValue]) throws -> String {
        try requestParser.parseArchive(arguments: arguments)
    }

    func parseThreadIdentifier(arguments: [String: AgentCLIKit.JSONValue]) throws -> String {
        try requestParser.parseThreadIdentifier(arguments: arguments)
    }

    func parseCreateSection(arguments: [String: AgentCLIKit.JSONValue]) throws -> String {
        try requestParser.parseCreateSection(arguments: arguments)
    }

    func parseMoveThreadToSection(
        arguments: [String: AgentCLIKit.JSONValue]
    ) throws -> ThreadHostToolSectionMoveRequest {
        try requestParser.parseMoveThreadToSection(arguments: arguments)
    }

    func parsePullRequestLink(
        arguments: [String: AgentCLIKit.JSONValue]
    ) throws -> ThreadHostToolPullRequestLinkRequest {
        try requestParser.parsePullRequestLink(arguments: arguments)
    }

    func parsePullRequestUnlink(
        arguments: [String: AgentCLIKit.JSONValue]
    ) throws -> ThreadHostToolPullRequestUnlinkRequest {
        try requestParser.parsePullRequestUnlink(arguments: arguments)
    }

    func parseOptionalThreadIdentifier(arguments: [String: AgentCLIKit.JSONValue]) throws -> String? {
        try requestParser.parseOptionalThreadIdentifier(arguments: arguments)
    }

    func requestDate() -> Date {
        now()
    }

    /// Every tool's first step, restating the shared resolution's failures in this feature's error
    /// type so a caller Alveary cannot place gets a thread-tool message rather than a generic one.
    ///
    /// It adds no automated-run refusal, and must not grow one: a scheduled run reaches these tools
    /// on purpose, and what an unattended run may do to a *given* thread is decided at that thread
    /// — `archiveThread` and `ThreadLifecycleService.setThreadPinned` each carry their own guard.
    func resolveSource(
        context: AgentCLIKit.AgentHostToolCallContext
    ) throws -> HostToolCallSource {
        let source: HostToolCallSource
        do {
            source = try HostToolSourceResolver.resolveSource(context: context, in: modelContext)
        } catch HostToolSourceError.sourceProviderMismatch {
            throw ThreadHostToolServiceError.sourceProviderMismatch
        } catch {
            throw ThreadHostToolServiceError.sourceConversationUnavailable
        }
        return source
    }

    func requireRequestID(_ context: AgentCLIKit.AgentHostToolCallContext) throws -> String {
        guard let requestID = context.requestId?.trimmingCharacters(in: .whitespacesAndNewlines),
              !requestID.isEmpty else {
            throw ThreadHostToolServiceError.missingRequestIdentity
        }
        return requestID
    }

    func requireNoArguments(
        _ arguments: [String: AgentCLIKit.JSONValue],
        toolName: String
    ) throws {
        guard arguments.isEmpty else {
            throw ThreadHostToolServiceError.listDoesNotAcceptArguments(toolName: toolName)
        }
    }

    func fetchAll<Model: PersistentModel>(
        _ type: Model.Type,
        sortBy: [SortDescriptor<Model>] = []
    ) throws -> [Model] {
        do {
            return try modelContext.fetch(FetchDescriptor<Model>(sortBy: sortBy))
        } catch {
            throw ThreadHostToolServiceError.persistenceFailure
        }
    }

    func flushPendingChanges() throws {
        guard modelContext.hasChanges else {
            return
        }
        do {
            try modelContext.save()
        } catch {
            throw ThreadHostToolServiceError.persistenceFailure
        }
    }

    /// The rows go into the text as well as `structuredContent`: a plain-text-fallback provider
    /// sees only the text, and the transcript's Output section shows the same string.
    func listText(header: String, rows: [String]) -> String {
        rows.isEmpty ? "\(header)." : "\(header):\n\(rows.joined(separator: "\n"))"
    }

    func count(_ value: Int, singular: String) -> String {
        value == 1 ? "1 \(singular)" : "\(value) \(singular)s"
    }

    func errorResult(
        for error: Error,
        toolName: String
    ) -> AgentCLIKit.AgentHostToolResult {
        let message: String
        switch error {
        case let requestError as HostToolRequestError:
            message = requestError.localizedDescription
        case let serviceError as ThreadHostToolServiceError:
            message = serviceError.localizedDescription
        case let sidebarError as SidebarViewModelError:
            message = sidebarError.localizedDescription
        case let sectionError as SidebarSectionServiceError:
            // Its refusals already name the valid values, so passing them through beats
            // collapsing "only task threads live in sections" into a persistence failure.
            message = sectionError.localizedDescription
        case let pullRequestError as PullRequestsServiceError:
            // A GitHub reachability failure is the model's to report, not Alveary's to swallow as
            // a generic persistence problem.
            message = ThreadHostToolServiceError
                .pullRequestUnavailable(pullRequestError.errorDescription ?? pullRequestError.localizedDescription)
                .localizedDescription
        default:
            message = ThreadHostToolServiceError.persistenceFailure.localizedDescription
        }
        let structuredContent: AgentCLIKit.JSONValue? = ThreadHostToolCatalog.mutatingToolNames.contains(toolName)
            ? .object(["status": .string("error"), "message": .string(message)])
            : nil
        return AgentCLIKit.AgentHostToolResult(text: message, structuredContent: structuredContent, isError: true)
    }
}

extension ThreadHostToolService: HostToolFeature {
    var featureID: String {
        ThreadHostToolCatalog.featureID
    }

    /// Derived from the catalog so routing cannot drift from what the server advertises.
    var hostToolNames: Set<String> {
        Set(ThreadHostToolCatalog.tools.map(\.name))
    }
}
