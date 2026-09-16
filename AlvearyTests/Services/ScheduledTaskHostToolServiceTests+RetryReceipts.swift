import AgentCLIKit
import Foundation
import SwiftData
import XCTest

@testable import Alveary

@MainActor
extension ScheduledTaskHostToolServiceTests {
    func testExactRetryReturnsSameProposalAndRevisedRequestSupersedesIt() async throws {
        let fixture = try ScheduledTaskHostToolFixture.project()
        let call = AgentCLIKit.AgentHostToolCall(
            name: ScheduledTaskHostToolCatalog.proposeToolName,
            arguments: createArguments()
        )
        let context = fixture.agentContext(requestID: "string:retry")

        let first = await fixture.service.handle(context: context, call: call)
        let retry = await fixture.service.handle(context: context, call: call)
        let different = await fixture.service.handle(
            context: fixture.agentContext(requestID: "string:different"),
            call: AgentCLIKit.AgentHostToolCall(
                name: ScheduledTaskHostToolCatalog.proposeToolName,
                arguments: createArguments(title: "Different title")
            )
        )

        XCTAssertEqual(try proposalID(first), try proposalID(retry))
        // A follow-up prompt revising the same task replaces the unconfirmed proposal.
        XCTAssertNotEqual(try proposalID(first), try proposalID(different))
        XCTAssertFalse(different.text.contains("No second proposal was opened"))
        XCTAssertEqual(try fixture.modelContext.fetchCount(FetchDescriptor<ScheduledTaskProposal>()), 1)
        XCTAssertNil(fixture.modelContext.resolveScheduledTaskProposal(id: try proposalID(first)))

        let markers = try fixture.modelContext.fetch(
            FetchDescriptor<ConversationEventRecord>(
                predicate: #Predicate { $0.type == "host_tool_outcome" }
            )
        )
        XCTAssertEqual(markers.count, 1)
        XCTAssertEqual(markers.first?.toolId, try proposalID(first))
        let content = try XCTUnwrap(markers.first?.content)
        XCTAssertEqual(HostToolWidgetOutcomeMarker.outcome(fromContent: content), .rejected)
        // The superseded proposal's captured title rides along so a plain-text-fallback
        // harness's widget can still name the task.
        XCTAssertEqual(HostToolWidgetOutcomeMarker.title(fromContent: content), "Daily review")
    }

    func testExactRetryAfterProposalRejectionReturnsReceiptWithoutReopeningProposal() async throws {
        let fixture = try ScheduledTaskHostToolFixture.project()
        let call = AgentCLIKit.AgentHostToolCall(
            name: ScheduledTaskHostToolCatalog.proposeToolName,
            arguments: createArguments()
        )
        let context = fixture.agentContext(requestID: "string:rejected-retry")

        let first = await fixture.service.handle(context: context, call: call)
        let firstProposalID = try proposalID(first)
        let proposal = try XCTUnwrap(fixture.modelContext.resolveScheduledTaskProposal(id: firstProposalID))
        fixture.modelContext.delete(proposal)
        try fixture.modelContext.save()

        let retry = await fixture.service.handle(context: context, call: call)

        XCTAssertFalse(retry.isError)
        XCTAssertEqual(try proposalID(retry), firstProposalID)
        XCTAssertEqual(retry.text, first.text)
        XCTAssertEqual(try fixture.modelContext.fetchCount(FetchDescriptor<ScheduledTaskProposal>()), 0)
        XCTAssertNotNil(fixture.conversation.scheduledTaskProposalReceiptsJSON)
    }

    func testExactRetryAfterProposalRejectionSurvivesMacTimeZoneChange() async throws {
        let fixture = try ScheduledTaskHostToolFixture.project()
        let timeZone = ScheduledTaskHostToolRetryTimeZoneBox("UTC")
        let service = fixture.makeService(
            requestParser: ScheduledTaskHostToolRequestParser(
                defaultTimeZoneIdentifierProvider: { timeZone.identifier }
            )
        )
        let call = AgentCLIKit.AgentHostToolCall(
            name: ScheduledTaskHostToolCatalog.proposeToolName,
            arguments: createArgumentsOmittingTimeZone()
        )
        let context = fixture.agentContext(requestID: "string:rejected-cross-zone-retry")
        let first = await service.handle(context: context, call: call)
        let firstProposalID = try proposalID(first)
        let proposal = try XCTUnwrap(fixture.modelContext.resolveScheduledTaskProposal(id: firstProposalID))
        fixture.modelContext.delete(proposal)
        try fixture.modelContext.save()
        timeZone.identifier = "America/Chicago"

        let retry = await service.handle(context: context, call: call)

        XCTAssertFalse(retry.isError)
        XCTAssertEqual(try proposalID(retry), firstProposalID)
        XCTAssertEqual(retry.text, first.text)
        XCTAssertEqual(try fixture.modelContext.fetchCount(FetchDescriptor<ScheduledTaskProposal>()), 0)
    }

    func testExactRetryAfterProposalConfirmationDoesNotCreateDuplicateDefinitionOrProposal() async throws {
        let fixture = try ScheduledTaskHostToolFixture.project()
        let call = AgentCLIKit.AgentHostToolCall(
            name: ScheduledTaskHostToolCatalog.proposeToolName,
            arguments: createArguments()
        )
        let context = fixture.agentContext(requestID: "string:confirmed-retry")

        let first = await fixture.service.handle(context: context, call: call)
        let firstProposalID = try proposalID(first)
        let proposal = try XCTUnwrap(fixture.modelContext.resolveScheduledTaskProposal(id: firstProposalID))
        let draft = try XCTUnwrap(proposal.definitionDraft)
        let edit = ScheduledTaskDefinitionEdit(
            title: draft.title,
            prompt: draft.prompt,
            destination: .newThreadPerRun,
            recurrence: draft.recurrence,
            timeZoneIdentifier: draft.timeZoneIdentifier,
            harnessID: draft.harnessID,
            model: draft.model,
            effort: draft.effort,
            permissionMode: draft.permissionMode,
            workspaceKind: draft.workspaceKind,
            workspaceStrategy: draft.workspaceStrategy,
            grantedRoots: draft.grantedRoots,
            project: proposal.project
        )
        let mutationService = ScheduledTaskMutationService(
            modelContext: fixture.modelContext,
            notificationCenter: fixture.notificationCenter
        )
        try mutationService.create(
            edit: edit,
            at: Date(timeIntervalSince1970: 1_000),
            consumingProposalID: firstProposalID
        )

        let retry = await fixture.service.handle(context: context, call: call)

        XCTAssertFalse(retry.isError)
        XCTAssertEqual(try proposalID(retry), firstProposalID)
        XCTAssertEqual(retry.text, first.text)
        XCTAssertEqual(try fixture.modelContext.fetchCount(FetchDescriptor<ScheduledTaskProposal>()), 0)
        XCTAssertEqual(try fixture.modelContext.fetchCount(FetchDescriptor<ScheduledTask>()), 1)
    }

    func testExactLegacyRetryAfterProposalConfirmationSurvivesMacTimeZoneChange() async throws {
        let fixture = try ScheduledTaskHostToolFixture.project()
        let timeZone = ScheduledTaskHostToolRetryTimeZoneBox("UTC")
        let service = fixture.makeService(
            requestParser: ScheduledTaskHostToolRequestParser(
                defaultTimeZoneIdentifierProvider: { timeZone.identifier }
            )
        )
        let call = AgentCLIKit.AgentHostToolCall(
            name: ScheduledTaskHostToolCatalog.proposeToolName,
            arguments: createArguments(legacyTimeZoneIdentifier: "UTC")
        )
        let context = fixture.agentContext(requestID: "string:confirmed-legacy-cross-zone-retry")
        let first = await service.handle(context: context, call: call)
        let firstProposalID = try proposalID(first)
        let proposal = try XCTUnwrap(fixture.modelContext.resolveScheduledTaskProposal(id: firstProposalID))
        let draft = try XCTUnwrap(proposal.definitionDraft)
        let edit = ScheduledTaskDefinitionEdit(
            title: draft.title,
            prompt: draft.prompt,
            destination: .newThreadPerRun,
            recurrence: draft.recurrence,
            timeZoneIdentifier: draft.timeZoneIdentifier,
            harnessID: draft.harnessID,
            model: draft.model,
            effort: draft.effort,
            permissionMode: draft.permissionMode,
            workspaceKind: draft.workspaceKind,
            workspaceStrategy: draft.workspaceStrategy,
            grantedRoots: draft.grantedRoots,
            project: proposal.project
        )
        let mutationService = ScheduledTaskMutationService(
            modelContext: fixture.modelContext,
            notificationCenter: fixture.notificationCenter
        )
        try mutationService.create(
            edit: edit,
            at: Date(timeIntervalSince1970: 1_000),
            consumingProposalID: firstProposalID
        )
        timeZone.identifier = "America/Chicago"

        let retry = await service.handle(context: context, call: call)

        XCTAssertFalse(retry.isError)
        XCTAssertEqual(try proposalID(retry), firstProposalID)
        XCTAssertEqual(retry.text, first.text)
        XCTAssertEqual(try fixture.modelContext.fetchCount(FetchDescriptor<ScheduledTaskProposal>()), 0)
        XCTAssertEqual(try fixture.modelContext.fetchCount(FetchDescriptor<ScheduledTask>()), 1)
    }

    func testExactRetryReceiptSurvivesStoreReopenAfterProposalRejection() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ScheduledTaskReceiptReopen-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let configuration = ModelConfiguration(url: directory.appendingPathComponent("Alveary.store"))
        let conversationID = "receipt-reopen-source"
        let processToken = UUID()
        let context = AgentCLIKit.AgentHostToolCallContext(
            conversationId: AgentCLIKit.AgentConversationID(rawValue: conversationID),
            harnessId: .codex,
            processToken: processToken,
            requestId: "string:receipt-reopen"
        )
        let call = AgentCLIKit.AgentHostToolCall(
            name: ScheduledTaskHostToolCatalog.proposeToolName,
            arguments: createArguments()
        )
        let firstResponse = try await persistRetryReceipt(
            configuration: configuration,
            conversationID: conversationID,
            context: context,
            call: call
        )

        do {
            let container = try makeReceiptPersistenceContainer(configuration: configuration)
            let modelContext = container.mainContext
            let service = ScheduledTaskHostToolService(
                modelContext: modelContext,
                mutationService: ScheduledTaskMutationService(modelContext: modelContext),
                requestParser: ScheduledTaskHostToolRequestParser(defaultTimeZoneIdentifier: "UTC"),
                now: { Date(timeIntervalSince1970: 1_001) }
            )

            let retry = await service.handle(context: context, call: call)

            XCTAssertFalse(retry.isError)
            XCTAssertEqual(try proposalID(retry), firstResponse.proposalID)
            XCTAssertEqual(retry.text, firstResponse.message)
            XCTAssertEqual(try modelContext.fetchCount(FetchDescriptor<ScheduledTaskProposal>()), 0)
        }
    }

    func testAppliedCallbackAndReceiptSurviveStoreReopeningWithOriginalTime() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let configuration = ModelConfiguration(url: directory.appendingPathComponent("Alveary.store"))
        let conversationID = "reopened-callback"
        let context = AgentHostToolCallContext(
            conversationId: AgentConversationID(rawValue: conversationID), harnessId: .codex,
            processToken: UUID(), requestId: "reopened-callback"
        )
        let call = AgentHostToolCall(name: ScheduledTaskHostToolCatalog.proposeToolName, arguments: callbackArguments())
        let original = try await persistRetryReceipt(
            configuration: configuration, conversationID: conversationID, context: context, call: call,
            rejectProposal: false, acceptanceDate: Date(timeIntervalSince1970: 1_000.123)
        )
        let container = try makeReceiptPersistenceContainer(configuration: configuration)
        let modelContext = container.mainContext
        let service = ScheduledTaskHostToolFixture.makeService(
            modelContext: modelContext, notificationCenter: NotificationCenter(),
            requestParser: ScheduledTaskHostToolRequestParser(defaultTimeZoneIdentifier: "UTC"),
            now: { Date(timeIntervalSince1970: 10_000) }
        )
        let retry = await service.handle(context: context, call: call)
        XCTAssertFalse(retry.isError, retry.text)
        XCTAssertEqual(retry.text, original.message)
        XCTAssertEqual(retry.structuredContent, original.structuredContent)
        let definitions = try modelContext.fetch(FetchDescriptor<ScheduledTask>())
        XCTAssertEqual(definitions.count, 1)
        let definition = try XCTUnwrap(definitions.first)
        XCTAssertEqual(definition.exactTargetConversationID, conversationID)
        XCTAssertEqual(definition.resolvedTargetConversation?.id, conversationID)
        XCTAssertEqual(definition.recurrence, .once(Date(timeIntervalSince1970: 2_800.123)))
        XCTAssertEqual(try object(retry.structuredContent)["task_id"], .string(definition.id))
        XCTAssertEqual(try object(retry.structuredContent)["scheduled_at"], .string("1970-01-01T00:46:40.123Z"))
    }

    private func persistRetryReceipt(
        configuration: ModelConfiguration,
        conversationID: String,
        context: AgentCLIKit.AgentHostToolCallContext,
        call: AgentCLIKit.AgentHostToolCall,
        rejectProposal: Bool = true,
        acceptanceDate: Date = Date(timeIntervalSince1970: 1_000)
    ) async throws -> ScheduledTaskHostToolStoredResponse {
        do {
            let container = try makeReceiptPersistenceContainer(configuration: configuration)
            let modelContext = container.mainContext
            let project = Project(path: "/tmp/receipt-reopen-project", name: "Receipt Reopen")
            let thread = AgentThread(name: "Receipt source", mode: .project, project: project)
            let conversation = Conversation(id: conversationID, harness: "codex", thread: thread)
            thread.conversations = [conversation]
            project.threads = [thread]
            modelContext.insert(project)
            try modelContext.save()
            let service = ScheduledTaskHostToolService(
                modelContext: modelContext,
                mutationService: ScheduledTaskMutationService(modelContext: modelContext),
                requestParser: ScheduledTaskHostToolRequestParser(defaultTimeZoneIdentifier: "UTC"),
                now: { acceptanceDate }
            )

            let result = await service.handle(context: context, call: call)
            XCTAssertFalse(result.isError, result.text)
            let values = try object(result.structuredContent)
            let proposalID = try XCTUnwrap(HostToolWidgetJSON.string(values["proposal_id"] ?? values["task_id"]))
            if rejectProposal {
                let proposal = try XCTUnwrap(modelContext.resolveScheduledTaskProposal(id: proposalID))
                modelContext.delete(proposal)
                try modelContext.save()
            }
            return ScheduledTaskHostToolStoredResponse(
                proposalID: proposalID, message: result.text, structuredContent: result.structuredContent
            )
        }
    }

    private func makeReceiptPersistenceContainer(
        configuration: ModelConfiguration
    ) throws -> ModelContainer {
        try ModelContainer(
            for: Project.self,
            AgentThread.self,
            Conversation.self,
            ConversationEventRecord.self,
            ScheduledTask.self,
            ScheduledTaskRun.self,
            ScheduledTaskProposal.self,
            configurations: configuration
        )
    }
}

private extension ScheduledTaskHostToolServiceTests {
    func createArgumentsOmittingTimeZone() -> [String: AgentCLIKit.JSONValue] {
        var arguments = createArguments()
        guard case .object(var schedule)? = arguments["schedule"] else {
            return arguments
        }
        schedule.removeValue(forKey: "time_zone")
        arguments["schedule"] = .object(schedule)
        return arguments
    }
}

private struct ScheduledTaskHostToolStoredResponse {
    let proposalID: String
    let message: String
    let structuredContent: AgentCLIKit.JSONValue?
}

private final class ScheduledTaskHostToolRetryTimeZoneBox: @unchecked Sendable {
    var identifier: String

    init(_ identifier: String) {
        self.identifier = identifier
    }
}
