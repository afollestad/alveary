import AgentCLIKit
import Foundation
import SwiftData
import XCTest

@testable import Alveary

@MainActor
extension ScheduledTaskHostToolServiceTests {
    func testExactRetryReturnsSameProposalAndDifferentPendingRequestDoesNotReplaceIt() throws {
        let fixture = try ScheduledTaskHostToolFixture.project()
        let call = AgentCLIKit.AgentHostToolCall(
            name: ScheduledTaskHostToolCatalog.proposeToolName,
            arguments: createArguments()
        )
        let context = fixture.agentContext(requestID: "string:retry")

        let first = fixture.service.handle(context: context, call: call)
        let retry = fixture.service.handle(context: context, call: call)
        let different = fixture.service.handle(
            context: fixture.agentContext(requestID: "string:different"),
            call: AgentCLIKit.AgentHostToolCall(
                name: ScheduledTaskHostToolCatalog.proposeToolName,
                arguments: createArguments(title: "Different title")
            )
        )

        XCTAssertEqual(try proposalID(first), try proposalID(retry))
        XCTAssertEqual(try proposalID(first), try proposalID(different))
        XCTAssertTrue(different.text.contains("No second proposal was opened"))
        XCTAssertEqual(try fixture.modelContext.fetchCount(FetchDescriptor<ScheduledTaskProposal>()), 1)
    }

    func testExactRetryAfterProposalRejectionReturnsReceiptWithoutReopeningProposal() throws {
        let fixture = try ScheduledTaskHostToolFixture.project()
        let call = AgentCLIKit.AgentHostToolCall(
            name: ScheduledTaskHostToolCatalog.proposeToolName,
            arguments: createArguments()
        )
        let context = fixture.agentContext(requestID: "string:rejected-retry")

        let first = fixture.service.handle(context: context, call: call)
        let firstProposalID = try proposalID(first)
        let proposal = try XCTUnwrap(fixture.modelContext.resolveScheduledTaskProposal(id: firstProposalID))
        fixture.modelContext.delete(proposal)
        try fixture.modelContext.save()

        let retry = fixture.service.handle(context: context, call: call)

        XCTAssertFalse(retry.isError)
        XCTAssertEqual(try proposalID(retry), firstProposalID)
        XCTAssertEqual(retry.text, first.text)
        XCTAssertEqual(try fixture.modelContext.fetchCount(FetchDescriptor<ScheduledTaskProposal>()), 0)
        XCTAssertNotNil(fixture.conversation.scheduledTaskProposalReceiptsJSON)
    }

    func testExactRetryAfterProposalConfirmationDoesNotCreateDuplicateDefinitionOrProposal() throws {
        let fixture = try ScheduledTaskHostToolFixture.project()
        let call = AgentCLIKit.AgentHostToolCall(
            name: ScheduledTaskHostToolCatalog.proposeToolName,
            arguments: createArguments()
        )
        let context = fixture.agentContext(requestID: "string:confirmed-retry")

        let first = fixture.service.handle(context: context, call: call)
        let firstProposalID = try proposalID(first)
        let proposal = try XCTUnwrap(fixture.modelContext.resolveScheduledTaskProposal(id: firstProposalID))
        let draft = try XCTUnwrap(proposal.definitionDraft)
        let edit = ScheduledTaskDefinitionEdit(
            title: draft.title,
            prompt: draft.prompt,
            recurrence: draft.recurrence,
            timeZoneIdentifier: draft.timeZoneIdentifier,
            providerID: draft.providerID,
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

        let retry = fixture.service.handle(context: context, call: call)

        XCTAssertFalse(retry.isError)
        XCTAssertEqual(try proposalID(retry), firstProposalID)
        XCTAssertEqual(retry.text, first.text)
        XCTAssertEqual(try fixture.modelContext.fetchCount(FetchDescriptor<ScheduledTaskProposal>()), 0)
        XCTAssertEqual(try fixture.modelContext.fetchCount(FetchDescriptor<ScheduledTask>()), 1)
    }

    func testExactRetryReceiptSurvivesStoreReopenAfterProposalRejection() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ScheduledTaskReceiptReopen-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let configuration = ModelConfiguration(url: directory.appendingPathComponent("Alveary.store"))
        let conversationID = "receipt-reopen-source"
        let processToken = UUID()
        let context = AgentCLIKit.AgentHostToolCallContext(
            conversationId: AgentCLIKit.AgentConversationID(rawValue: conversationID),
            providerId: .codex,
            processToken: processToken,
            requestId: "string:receipt-reopen"
        )
        let call = AgentCLIKit.AgentHostToolCall(
            name: ScheduledTaskHostToolCatalog.proposeToolName,
            arguments: createArguments()
        )
        let firstResponse = try persistRejectedProposalReceipt(
            configuration: configuration,
            conversationID: conversationID,
            context: context,
            call: call
        )

        try autoreleasepool {
            let container = try makeReceiptPersistenceContainer(configuration: configuration)
            let modelContext = container.mainContext
            let service = ScheduledTaskHostToolService(
                modelContext: modelContext,
                now: { Date(timeIntervalSince1970: 1_001) }
            )

            let retry = service.handle(context: context, call: call)

            XCTAssertFalse(retry.isError)
            XCTAssertEqual(try proposalID(retry), firstResponse.proposalID)
            XCTAssertEqual(retry.text, firstResponse.message)
            XCTAssertEqual(try modelContext.fetchCount(FetchDescriptor<ScheduledTaskProposal>()), 0)
        }
    }

    private func persistRejectedProposalReceipt(
        configuration: ModelConfiguration,
        conversationID: String,
        context: AgentCLIKit.AgentHostToolCallContext,
        call: AgentCLIKit.AgentHostToolCall
    ) throws -> ScheduledTaskHostToolStoredResponse {
        try autoreleasepool {
            let container = try makeReceiptPersistenceContainer(configuration: configuration)
            let modelContext = container.mainContext
            let project = Project(path: "/tmp/receipt-reopen-project", name: "Receipt Reopen")
            let thread = AgentThread(name: "Receipt source", mode: .project, project: project)
            let conversation = Conversation(id: conversationID, provider: "codex", thread: thread)
            thread.conversations = [conversation]
            project.threads = [thread]
            modelContext.insert(project)
            try modelContext.save()
            let service = ScheduledTaskHostToolService(
                modelContext: modelContext,
                now: { Date(timeIntervalSince1970: 1_000) }
            )

            let result = service.handle(context: context, call: call)
            let proposalID = try proposalID(result)
            let proposal = try XCTUnwrap(modelContext.resolveScheduledTaskProposal(id: proposalID))
            modelContext.delete(proposal)
            try modelContext.save()
            return ScheduledTaskHostToolStoredResponse(proposalID: proposalID, message: result.text)
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

private struct ScheduledTaskHostToolStoredResponse {
    let proposalID: String
    let message: String
}
