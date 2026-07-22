import AgentCLIKit
import Foundation
import SwiftData

@MainActor
final class ScheduledTaskHostToolService {
    private static let pendingConfirmationMessage =
        "Opened a scheduling proposal for confirmation. No scheduled task has changed yet."

    let modelContext: ModelContext
    private let notificationCenter: NotificationCenter
    private let requestParser: ScheduledTaskHostToolRequestParser
    let recurrenceCalculator: ScheduledTaskRecurrenceCalculator
    let currentTimeZone: @MainActor () -> TimeZone
    private let now: () -> Date

    init(
        modelContext: ModelContext,
        notificationCenter: NotificationCenter = .default,
        requestParser: ScheduledTaskHostToolRequestParser = ScheduledTaskHostToolRequestParser(),
        recurrenceCalculator: ScheduledTaskRecurrenceCalculator = ScheduledTaskRecurrenceCalculator(),
        currentTimeZone: @escaping @MainActor () -> TimeZone = { .autoupdatingCurrent },
        now: @escaping () -> Date = Date.init
    ) {
        self.modelContext = modelContext
        self.notificationCenter = notificationCenter
        self.requestParser = requestParser
        self.recurrenceCalculator = recurrenceCalculator
        self.currentTimeZone = currentTimeZone
        self.now = now
    }

    func handle(
        context: AgentCLIKit.AgentHostToolCallContext,
        call: AgentCLIKit.AgentHostToolCall
    ) -> AgentCLIKit.AgentHostToolResult {
        do {
            switch call.name {
            case ScheduledTaskHostToolCatalog.listToolName:
                return try listScheduledTasks(context: context, arguments: call.arguments)
            case ScheduledTaskHostToolCatalog.proposeToolName:
                return try proposeScheduledTask(context: context, arguments: call.arguments)
            default:
                throw ScheduledTaskHostToolServiceError.unsupportedTool
            }
        } catch {
            return errorResult(for: error, toolName: call.name)
        }
    }
}

private extension ScheduledTaskHostToolService {
    func listScheduledTasks(
        context: AgentCLIKit.AgentHostToolCallContext,
        arguments: [String: AgentCLIKit.JSONValue]
    ) throws -> AgentCLIKit.AgentHostToolResult {
        guard arguments.isEmpty else {
            throw ScheduledTaskHostToolServiceError.listDoesNotAcceptArguments
        }
        _ = try resolveSource(context: context)
        let definitions: [ScheduledTask]
        do {
            definitions = try modelContext.fetch(
                FetchDescriptor<ScheduledTask>(
                    sortBy: [
                        SortDescriptor(\ScheduledTask.createdAt),
                        SortDescriptor(\ScheduledTask.id)
                    ]
                )
            )
        } catch {
            throw ScheduledTaskHostToolServiceError.persistenceFailure
        }

        let tasks = definitions.map { definition in
            AgentCLIKit.JSONValue.object([
                "id": .string(definition.id),
                "revision": .number(Double(definition.revision)),
                "title": .string(definition.title),
                "state": .string(definition.state.rawValue),
                "schedule_summary": .string(ScheduledTaskHostToolSupport.scheduleSummary(
                    for: definition,
                    timeZoneIdentifier: currentTimeZone().identifier
                ))
            ])
        }
        let countDescription = definitions.count == 1 ? "1 scheduled task" : "\(definitions.count) scheduled tasks"
        return AgentCLIKit.AgentHostToolResult(
            text: "Found \(countDescription).",
            structuredContent: .object(["tasks": .array(tasks)])
        )
    }

    func proposeScheduledTask(
        context: AgentCLIKit.AgentHostToolCallContext,
        arguments: [String: AgentCLIKit.JSONValue]
    ) throws -> AgentCLIKit.AgentHostToolResult {
        guard let requestID = context.requestId?.trimmingCharacters(in: .whitespacesAndNewlines),
              !requestID.isEmpty else {
            throw ScheduledTaskHostToolServiceError.missingRequestIdentity
        }
        try flushPendingChanges()
        let requestDate = now()

        let sourceConversationID = context.conversationId.rawValue
        let source = try resolveSource(context: context)
        let sourceConversation = source.conversation

        let retryIdentity = try requestParser.parseRetryIdentity(arguments: arguments)
        let deduplicationKey = ScheduledTaskHostToolSupport.deduplicationKey(
            sourceConversationID: sourceConversationID,
            processToken: context.processToken,
            requestID: requestID,
            canonicalPayloadHash: retryIdentity.canonicalPayloadHash
        )

        let receipt = try sourceConversation.scheduledTaskProposalReceipt(
            matching: deduplicationKey,
            currentProcessToken: context.processToken,
            at: requestDate
        )
        try persistReceiptMaintenanceIfNeeded()
        if let receipt {
            return pendingResult(receipt: receipt)
        }

        let parsedRequest = try requestParser.parse(arguments: arguments)

        if let existingResult = try pendingResultForExistingProposal(
            sourceConversation: sourceConversation,
            deduplicationKey: deduplicationKey,
            sourceProcessToken: context.processToken,
            createdAt: requestDate
        ) {
            return existingResult
        }

        return try openProposal(
            context: context,
            source: source,
            identity: ScheduledTaskHostToolProposalIdentity(
                requestID: requestID,
                deduplicationKey: deduplicationKey,
                createdAt: requestDate
            ),
            parsedRequest: parsedRequest
        )
    }

    func pendingResultForExistingProposal(
        sourceConversation: Conversation,
        deduplicationKey: String,
        sourceProcessToken: UUID,
        createdAt: Date
    ) throws -> AgentCLIKit.AgentHostToolResult? {
        guard let existingProposal = modelContext.resolveScheduledTaskProposal(
            sourceConversationID: sourceConversation.id
        ) else {
            return nil
        }
        let message = existingProposal.deduplicationKey == deduplicationKey
            ? Self.pendingConfirmationMessage
            : "A different scheduling proposal from this conversation is already awaiting confirmation. No second proposal was opened."
        let receipt = makeReceipt(
            deduplicationKey: deduplicationKey,
            proposal: existingProposal,
            message: message,
            sourceProcessToken: sourceProcessToken,
            createdAt: createdAt
        )
        try persist(receipt, on: sourceConversation)
        return pendingResult(receipt: receipt)
    }

    func openProposal(
        context: AgentCLIKit.AgentHostToolCallContext,
        source: ScheduledTaskHostToolSource,
        identity: ScheduledTaskHostToolProposalIdentity,
        parsedRequest: ScheduledTaskParsedProposalRequest
    ) throws -> AgentCLIKit.AgentHostToolResult {
        let resolution = try resolveProposal(
            parsedRequest.request,
            sourceThread: source.thread,
            sourceProviderID: context.providerId.rawValue
        )
        let proposal = try makeProposal(
            context: context,
            sourceConversation: source.conversation,
            identity: identity,
            parsedRequest: parsedRequest,
            resolution: resolution
        )
        let receipt = makeReceipt(
            deduplicationKey: identity.deduplicationKey,
            proposal: proposal,
            message: Self.pendingConfirmationMessage,
            sourceProcessToken: context.processToken,
            createdAt: identity.createdAt
        )
        try persist(proposal, receipt: receipt, on: source.conversation)
        notificationCenter.postScheduledTaskProposalsChanged(
            object: self,
            proposalID: proposal.id,
            sourceConversationID: source.conversation.id
        )
        return pendingResult(receipt: receipt)
    }

    func makeProposal(
        context: AgentCLIKit.AgentHostToolCallContext,
        sourceConversation: Conversation,
        identity: ScheduledTaskHostToolProposalIdentity,
        parsedRequest: ScheduledTaskParsedProposalRequest,
        resolution: ScheduledTaskHostToolProposalResolution
    ) throws -> ScheduledTaskProposal {
        let enqueueOrdinal = try nextProposalEnqueueOrdinal()
        return ScheduledTaskProposal(
            deduplicationKey: identity.deduplicationKey,
            action: parsedRequest.request.action,
            canonicalPayloadJSON: parsedRequest.canonicalPayloadJSON,
            canonicalPayloadHash: parsedRequest.canonicalPayloadHash,
            sourceProviderID: context.providerId.rawValue,
            sourceProcessToken: context.processToken,
            sourceRequestID: identity.requestID,
            targetDefinitionID: resolution.targetDefinitionID,
            expectedDefinitionRevision: resolution.expectedDefinitionRevision,
            targetTitleSnapshot: resolution.targetTitleSnapshot,
            targetScheduleSummarySnapshot: resolution.targetScheduleSummarySnapshot,
            definitionDraft: resolution.definitionDraft,
            enqueueOrdinal: enqueueOrdinal,
            createdAt: identity.createdAt,
            sourceConversation: sourceConversation,
            project: resolution.project
        )
    }

    func flushPendingChanges() throws {
        guard modelContext.hasChanges else {
            return
        }
        do {
            try modelContext.save()
        } catch {
            throw ScheduledTaskHostToolServiceError.persistenceFailure
        }
    }

    func nextProposalEnqueueOrdinal() throws -> Int64 {
        let proposals: [ScheduledTaskProposal]
        do {
            proposals = try modelContext.fetch(FetchDescriptor<ScheduledTaskProposal>())
        } catch {
            throw ScheduledTaskHostToolServiceError.persistenceFailure
        }
        let highestOrdinal = proposals.compactMap(\.enqueueOrdinal).filter { $0 > 0 }.max() ?? 0
        guard highestOrdinal < Int64.max else {
            throw ScheduledTaskHostToolServiceError.persistenceFailure
        }
        return highestOrdinal + 1
    }

}
