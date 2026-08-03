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
    let mutationService: ScheduledTaskMutationService
    let runNowAction: @MainActor (ScheduledTaskRunNowRequest) -> Bool
    private let now: () -> Date

    init(
        modelContext: ModelContext,
        mutationService: ScheduledTaskMutationService,
        notificationCenter: NotificationCenter = .default,
        requestParser: ScheduledTaskHostToolRequestParser = ScheduledTaskHostToolRequestParser(),
        recurrenceCalculator: ScheduledTaskRecurrenceCalculator = ScheduledTaskRecurrenceCalculator(),
        currentTimeZone: @escaping @MainActor () -> TimeZone = { .autoupdatingCurrent },
        runNow: @escaping @MainActor (ScheduledTaskRunNowRequest) -> Bool = { _ in false },
        now: @escaping () -> Date = Date.init
    ) {
        self.modelContext = modelContext
        self.mutationService = mutationService
        self.notificationCenter = notificationCenter
        self.requestParser = requestParser
        self.recurrenceCalculator = recurrenceCalculator
        self.currentTimeZone = currentTimeZone
        runNowAction = runNow
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

extension ScheduledTaskHostToolService: HostToolFeature {
    var featureID: String {
        ScheduledTaskHostToolCatalog.featureID
    }

    /// Derived from the catalog so routing cannot drift from what the server advertises.
    var hostToolNames: Set<String> {
        Set(ScheduledTaskHostToolCatalog.tools.map(\.name))
    }
}

private extension ScheduledTaskHostToolService {
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

        let source = try resolveSource(context: context)
        let sourceConversation = source.conversation
        let deduplicationKey = try deduplicationKey(
            context: context,
            requestID: requestID,
            arguments: arguments
        )

        if let receipt = try replayedReceipt(
            on: sourceConversation,
            deduplicationKey: deduplicationKey,
            processToken: context.processToken,
            at: requestDate
        ) {
            return pendingResult(receipt: receipt)
        }

        let parsedRequest = try requestParser.parse(arguments: arguments)
        let identity = ScheduledTaskHostToolProposalIdentity(
            requestID: requestID,
            deduplicationKey: deduplicationKey,
            createdAt: requestDate
        )

        // Pause, resume, and run-now are reversible and revision-checked, so they apply
        // straight away; only definition changes and deletion need native confirmation.
        if ScheduledTaskHostToolService.appliesWithoutConfirmation(parsedRequest.request.action) {
            return try applyImmediately(
                parsedRequest.request,
                source: source,
                identity: identity,
                context: context
            )
        }

        if let existingResult = try pendingResultForExistingProposal(
            sourceConversation: sourceConversation,
            deduplicationKey: deduplicationKey,
            sourceProcessToken: context.processToken,
            createdAt: requestDate,
            supersedingRequest: parsedRequest.request
        ) {
            return existingResult
        }

        return try openProposal(
            context: context,
            source: source,
            identity: identity,
            parsedRequest: parsedRequest
        )
    }

    func deduplicationKey(
        context: AgentCLIKit.AgentHostToolCallContext,
        requestID: String,
        arguments: [String: AgentCLIKit.JSONValue]
    ) throws -> String {
        let retryIdentity = try requestParser.parseRetryIdentity(arguments: arguments)
        return ScheduledTaskHostToolSupport.deduplicationKey(
            sourceConversationID: context.conversationId.rawValue,
            processToken: context.processToken,
            requestID: requestID,
            canonicalPayloadHash: retryIdentity.canonicalPayloadHash
        )
    }

    /// An exact retry replays its recorded receipt instead of acting again.
    func replayedReceipt(
        on sourceConversation: Conversation,
        deduplicationKey: String,
        processToken: UUID,
        at requestDate: Date
    ) throws -> ScheduledTaskProposalReceipt? {
        let receipt = try sourceConversation.scheduledTaskProposalReceipt(
            matching: deduplicationKey,
            currentProcessToken: processToken,
            at: requestDate
        )
        try persistReceiptMaintenanceIfNeeded()
        return receipt
    }

    func pendingResultForExistingProposal(
        sourceConversation: Conversation,
        deduplicationKey: String,
        sourceProcessToken: UUID,
        createdAt: Date,
        supersedingRequest: ScheduledTaskProposalRequest
    ) throws -> AgentCLIKit.AgentHostToolResult? {
        guard let existingProposal = modelContext.resolveScheduledTaskProposal(
            sourceConversationID: sourceConversation.id
        ) else {
            return nil
        }
        // A follow-up prompt that revises the same target replaces the unconfirmed
        // proposal rather than being refused; the superseded widget records a rejection
        // so the transcript never keeps two live confirmations for one task.
        if existingProposal.deduplicationKey != deduplicationKey,
           targetsSameDefinition(existingProposal, as: supersedingRequest) {
            try rejectSupersededProposal(existingProposal, at: createdAt)
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

    /// Same definition, or both untargeted creates, counts as the same task.
    func targetsSameDefinition(
        _ proposal: ScheduledTaskProposal,
        as request: ScheduledTaskProposalRequest
    ) -> Bool {
        switch request {
        case .create:
            return proposal.targetDefinitionID == nil
        case let .edit(definitionID, _, _),
             let .pause(definitionID, _),
             let .resume(definitionID, _),
             let .delete(definitionID, _),
             let .runNow(definitionID, _):
            return proposal.targetDefinitionID == definitionID
        }
    }

    func rejectSupersededProposal(_ proposal: ScheduledTaskProposal, at timestamp: Date) throws {
        let outcomeTarget = ScheduledTaskProposalOutcomeTarget(proposal: proposal)
        do {
            modelContext.delete(proposal)
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw ScheduledTaskHostToolServiceError.persistenceFailure
        }
        ScheduledTaskProposalOutcomeRecorder.record(
            outcomeTarget,
            outcome: .rejected,
            in: modelContext,
            at: timestamp
        )
        notificationCenter.postScheduledTaskProposalsChanged(object: self)
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
            message: [Self.pendingConfirmationMessage, resolution.placementSummary]
                .compactMap { $0 }
                .joined(separator: " "),
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
