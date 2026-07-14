import Foundation
import SwiftData
import XCTest

@testable import Alveary

@MainActor
final class ScheduledTaskProposalModelTests: XCTestCase {
    func testProposalPersistsTrustedDraftAndSourceRelationships() throws {
        let context = ModelContext(try makeContainer())
        let project = Project(path: "/tmp/proposal-project", name: "Proposal Project")
        let thread = AgentThread(name: "Source", mode: .project, project: project)
        let conversation = Conversation(id: "conversation-1", provider: "codex", thread: thread)
        thread.conversations = [conversation]
        project.threads = [thread]
        context.insert(project)

        let draft = makeDraft(projectPath: project.path)
        let processToken = UUID()
        let proposal = ScheduledTaskProposal(
            id: "proposal-1",
            deduplicationKey: "dedupe-1",
            action: .create,
            canonicalPayloadJSON: #"{"action":"create"}"#,
            canonicalPayloadHash: "payload-hash",
            sourceProviderID: "codex",
            sourceProcessToken: processToken,
            sourceRequestID: "string:request-1",
            definitionDraft: draft,
            createdAt: Date(timeIntervalSince1970: 100),
            sourceConversation: conversation,
            project: project
        )
        context.insert(proposal)
        try context.save()

        let fetched = try XCTUnwrap(try context.fetch(FetchDescriptor<ScheduledTaskProposal>()).first)
        XCTAssertEqual(fetched.id, "proposal-1")
        XCTAssertEqual(fetched.sourceConversationID, "conversation-1")
        XCTAssertEqual(fetched.action, .create)
        XCTAssertEqual(fetched.definitionDraft, draft)
        XCTAssertEqual(fetched.sourceProcessToken, processToken.uuidString.lowercased())
        XCTAssertEqual(fetched.sourceConversation?.id, "conversation-1")
        XCTAssertEqual(fetched.project?.path, CanonicalPath.normalize("/tmp/proposal-project"))
    }

    func testDeletingSourceConversationCascadesProposal() throws {
        let context = ModelContext(try makeContainer())
        let thread = AgentThread(name: "Task", mode: .task)
        let conversation = Conversation(id: "conversation-2", provider: "codex", thread: thread)
        thread.conversations = [conversation]
        context.insert(thread)
        context.insert(ScheduledTaskProposal(
            deduplicationKey: "dedupe-2",
            action: .pause,
            canonicalPayloadJSON: #"{"action":"pause"}"#,
            canonicalPayloadHash: "hash-2",
            sourceProviderID: "codex",
            sourceProcessToken: UUID(),
            sourceRequestID: "string:request-2",
            sourceConversation: conversation
        ))
        try context.save()

        context.delete(conversation)
        try context.save()

        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ScheduledTaskProposal>()), 0)
    }

    func testDeletingProposalProjectNullifiesRelationshipWithoutDeletingProposal() throws {
        let context = ModelContext(try makeContainer())
        let sourceThread = AgentThread(name: "Task", mode: .task)
        let conversation = Conversation(id: "conversation-3", provider: "codex", thread: sourceThread)
        sourceThread.conversations = [conversation]
        let project = Project(path: "/tmp/detached-proposal-project", name: "Detached")
        context.insert(sourceThread)
        context.insert(project)
        context.insert(ScheduledTaskProposal(
            deduplicationKey: "dedupe-3",
            action: .create,
            canonicalPayloadJSON: #"{"action":"create"}"#,
            canonicalPayloadHash: "hash-3",
            sourceProviderID: "codex",
            sourceProcessToken: UUID(),
            sourceRequestID: "string:request-3",
            definitionDraft: makeDraft(projectPath: project.path),
            sourceConversation: conversation,
            project: project
        ))
        try context.save()

        context.delete(project)
        try context.save()

        let fetched = try XCTUnwrap(try context.fetch(FetchDescriptor<ScheduledTaskProposal>()).first)
        XCTAssertNil(fetched.project)
        XCTAssertEqual(fetched.sourceConversation?.id, conversation.id)
    }

    func testDraftDecodingFailsClosedForUnsupportedVersionAndMalformedPayload() {
        let conversation = Conversation(id: "conversation-4")
        let proposal = ScheduledTaskProposal(
            deduplicationKey: "dedupe-4",
            action: .edit,
            canonicalPayloadJSON: #"{"action":"edit"}"#,
            canonicalPayloadHash: "hash-4",
            sourceProviderID: "codex",
            sourceProcessToken: UUID(),
            sourceRequestID: "string:request-4",
            definitionDraft: makeDraft(projectPath: nil),
            sourceConversation: conversation
        )

        proposal.payloadVersion = ScheduledTaskProposal.currentPayloadVersion + 1
        XCTAssertNil(proposal.definitionDraft)
        XCTAssertNil(proposal.action)

        proposal.payloadVersion = ScheduledTaskProposal.currentPayloadVersion
        proposal.definitionDraftJSON = "not-json"
        XCTAssertNil(proposal.definitionDraft)
        proposal.actionRawValue = "unknown"
        XCTAssertNil(proposal.action)
    }

    func testActionShapeRejectsPrivateWorkspaceWithProjectPath() {
        let conversation = Conversation(id: "conversation-invalid-workspace")
        let proposal = ScheduledTaskProposal(
            deduplicationKey: "dedupe-invalid-workspace",
            action: .create,
            canonicalPayloadJSON: #"{"action":"create"}"#,
            canonicalPayloadHash: "hash-invalid-workspace",
            sourceProviderID: "codex",
            sourceProcessToken: UUID(),
            sourceRequestID: "string:request-invalid-workspace",
            definitionDraft: ScheduledTaskProposalDefinitionDraft(
                title: "Invalid workspace",
                prompt: "Run checks.",
                recurrence: .daily(hour: 8, minute: 0),
                timeZoneIdentifier: "UTC",
                providerID: "codex",
                model: nil,
                effort: "medium",
                permissionMode: "default",
                workspaceKind: .privateWorkspace,
                workspaceStrategy: .worktree,
                grantedRoots: [],
                projectPath: "/tmp/unexpected-project"
            ),
            sourceConversation: conversation
        )

        XCTAssertFalse(proposal.hasValidActionShape)
    }

    func testReceiptMaintenanceIsGenerationScopedExpiringAndBounded() throws {
        let conversation = Conversation(id: "receipt-maintenance")
        let firstProcessToken = UUID()
        let secondProcessToken = UUID()
        let start = Date(timeIntervalSince1970: 1_000)

        try conversation.recordScheduledTaskProposalReceipt(makeReceipt(
            key: "old-generation",
            processToken: firstProcessToken,
            createdAt: start
        ))
        try conversation.recordScheduledTaskProposalReceipt(makeReceipt(
            key: "current-generation",
            processToken: secondProcessToken,
            createdAt: start.addingTimeInterval(1)
        ))

        XCTAssertNil(try conversation.scheduledTaskProposalReceipt(
            matching: "old-generation",
            currentProcessToken: secondProcessToken,
            at: start.addingTimeInterval(1)
        ))
        XCTAssertNotNil(try conversation.scheduledTaskProposalReceipt(
            matching: "current-generation",
            currentProcessToken: secondProcessToken,
            at: start.addingTimeInterval(1)
        ))

        let expiredAt = start.addingTimeInterval(Conversation.scheduledTaskProposalReceiptRetention + 2)
        XCTAssertNil(try conversation.scheduledTaskProposalReceipt(
            matching: "current-generation",
            currentProcessToken: secondProcessToken,
            at: expiredAt
        ))

        for index in 0 ... Conversation.maximumScheduledTaskProposalReceiptCount {
            try conversation.recordScheduledTaskProposalReceipt(makeReceipt(
                key: "bounded-\(index)",
                processToken: secondProcessToken,
                createdAt: expiredAt.addingTimeInterval(Double(index))
            ))
        }

        XCTAssertNil(try conversation.scheduledTaskProposalReceipt(
            matching: "bounded-0",
            currentProcessToken: secondProcessToken,
            at: expiredAt.addingTimeInterval(Double(Conversation.maximumScheduledTaskProposalReceiptCount))
        ))
        XCTAssertNotNil(try conversation.scheduledTaskProposalReceipt(
            matching: "bounded-\(Conversation.maximumScheduledTaskProposalReceiptCount)",
            currentProcessToken: secondProcessToken,
            at: expiredAt.addingTimeInterval(Double(Conversation.maximumScheduledTaskProposalReceiptCount))
        ))
        XCTAssertEqual(try decodedReceipts(conversation).count, Conversation.maximumScheduledTaskProposalReceiptCount)
    }

    func testPendingProposalsPersistAcrossStoreReopenInFIFOOrder() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ScheduledTaskProposalReopen-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let configuration = ModelConfiguration(url: directory.appendingPathComponent("Alveary.store"))
        let firstDraft = makeDraft(projectPath: "/tmp/proposal-reopen-project")
        let secondDraft = makeDraft(projectPath: "/tmp/proposal-reopen-project")

        try persistReopenFixture(
            configuration: configuration,
            firstDraft: firstDraft,
            secondDraft: secondDraft
        )
        try assertReopenedFixture(
            configuration: configuration,
            firstDraft: firstDraft,
            secondDraft: secondDraft
        )
    }
}

private extension ScheduledTaskProposalModelTests {
    func makeContainer(
        configuration: ModelConfiguration = ModelConfiguration(isStoredInMemoryOnly: true)
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

    func makeDraft(projectPath: String?) -> ScheduledTaskProposalDefinitionDraft {
        ScheduledTaskProposalDefinitionDraft(
            title: "Review changes",
            prompt: "Review the latest changes.",
            recurrence: .weekdays(hour: 9, minute: 30),
            timeZoneIdentifier: "America/Chicago",
            providerID: "codex",
            model: "gpt-5",
            effort: "high",
            permissionMode: "default",
            workspaceKind: projectPath == nil ? .privateWorkspace : .project,
            workspaceStrategy: .worktree,
            grantedRoots: ["/tmp/grant", "/tmp/../tmp/grant"],
            projectPath: projectPath
        )
    }

    func makeReceipt(
        key: String,
        processToken: UUID,
        createdAt: Date
    ) -> ScheduledTaskProposalReceipt {
        ScheduledTaskProposalReceipt(
            deduplicationKey: key,
            proposalID: "proposal-\(key)",
            action: .create,
            message: "Pending confirmation.",
            sourceProcessToken: processToken.uuidString.lowercased(),
            createdAt: createdAt
        )
    }

    func decodedReceipts(_ conversation: Conversation) throws -> [ScheduledTaskProposalReceipt] {
        let data = try XCTUnwrap(conversation.scheduledTaskProposalReceiptsJSON?.data(using: .utf8))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([ScheduledTaskProposalReceipt].self, from: data)
    }

    func persistReopenFixture(
        configuration: ModelConfiguration,
        firstDraft: ScheduledTaskProposalDefinitionDraft,
        secondDraft: ScheduledTaskProposalDefinitionDraft
    ) throws {
        try autoreleasepool {
            let container = try makeContainer(configuration: configuration)
            let context = container.mainContext
            let sources = makeReopenSources()
            context.insert(sources.project)
            context.insert(makeFirstReopenProposal(
                draft: firstDraft,
                conversation: sources.firstConversation,
                project: sources.project
            ))
            context.insert(makeSecondReopenProposal(
                draft: secondDraft,
                conversation: sources.secondConversation,
                project: sources.project
            ))
            try context.save()
        }
    }

    func assertReopenedFixture(
        configuration: ModelConfiguration,
        firstDraft: ScheduledTaskProposalDefinitionDraft,
        secondDraft: ScheduledTaskProposalDefinitionDraft
    ) throws {
        try autoreleasepool {
            let container = try makeContainer(configuration: configuration)
            let proposals = try container.mainContext.fetch(FetchDescriptor<ScheduledTaskProposal>(
                sortBy: [
                    SortDescriptor(\ScheduledTaskProposal.enqueueOrdinal),
                    SortDescriptor(\ScheduledTaskProposal.createdAt),
                    SortDescriptor(\ScheduledTaskProposal.id)
                ]
            ))

            XCTAssertEqual(proposals.map(\.id), ["proposal-reopen-first", "proposal-reopen-a-second"])
            let first = try XCTUnwrap(proposals.first)
            XCTAssertEqual(first.enqueueOrdinal, 1)
            XCTAssertEqual(first.action, .create)
            XCTAssertEqual(first.sourceConversationID, "proposal-reopen-source-1")
            XCTAssertEqual(first.sourceConversation?.id, "proposal-reopen-source-1")
            XCTAssertEqual(first.project?.path, CanonicalPath.normalize("/tmp/proposal-reopen-project"))
            XCTAssertEqual(first.definitionDraft, firstDraft)
            let second = try XCTUnwrap(proposals.last)
            XCTAssertEqual(second.enqueueOrdinal, 2)
            XCTAssertEqual(second.action, .edit)
            XCTAssertEqual(second.targetDefinitionID, "proposal-reopen-definition")
            XCTAssertEqual(second.expectedDefinitionRevision, 7)
            XCTAssertEqual(second.targetTitleSnapshot, "Existing scheduled task")
            XCTAssertEqual(second.definitionDraft, secondDraft)
            XCTAssertEqual(second.sourceConversation?.thread?.project?.path, first.project?.path)
        }
    }

    func makeReopenSources() -> ScheduledTaskProposalReopenSources {
        let project = Project(path: "/tmp/proposal-reopen-project", name: "Proposal Project")
        let firstThread = AgentThread(name: "First source", mode: .project, project: project)
        let firstConversation = Conversation(id: "proposal-reopen-source-1", provider: "codex", thread: firstThread)
        firstThread.conversations = [firstConversation]
        let secondThread = AgentThread(name: "Second source", mode: .project, project: project)
        let secondConversation = Conversation(id: "proposal-reopen-source-2", provider: "codex", thread: secondThread)
        secondThread.conversations = [secondConversation]
        project.threads = [firstThread, secondThread]
        return ScheduledTaskProposalReopenSources(
            project: project,
            firstConversation: firstConversation,
            secondConversation: secondConversation
        )
    }

    func makeFirstReopenProposal(
        draft: ScheduledTaskProposalDefinitionDraft,
        conversation: Conversation,
        project: Project
    ) -> ScheduledTaskProposal {
        ScheduledTaskProposal(
            id: "proposal-reopen-first",
            deduplicationKey: "proposal-reopen-dedupe-1",
            action: .create,
            canonicalPayloadJSON: #"{"action":"create"}"#,
            canonicalPayloadHash: "proposal-reopen-hash-1",
            sourceProviderID: "codex",
            sourceProcessToken: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE") ?? UUID(),
            sourceRequestID: "string:proposal-reopen-1",
            definitionDraft: draft,
            enqueueOrdinal: 1,
            createdAt: Date(timeIntervalSince1970: 100),
            sourceConversation: conversation,
            project: project
        )
    }

    func makeSecondReopenProposal(
        draft: ScheduledTaskProposalDefinitionDraft,
        conversation: Conversation,
        project: Project
    ) -> ScheduledTaskProposal {
        ScheduledTaskProposal(
            id: "proposal-reopen-a-second",
            deduplicationKey: "proposal-reopen-dedupe-2",
            action: .edit,
            canonicalPayloadJSON: #"{"action":"edit"}"#,
            canonicalPayloadHash: "proposal-reopen-hash-2",
            sourceProviderID: "codex",
            sourceProcessToken: UUID(uuidString: "FFFFFFFF-BBBB-CCCC-DDDD-EEEEEEEEEEEE") ?? UUID(),
            sourceRequestID: "string:proposal-reopen-2",
            targetDefinitionID: "proposal-reopen-definition",
            expectedDefinitionRevision: 7,
            targetTitleSnapshot: "Existing scheduled task",
            targetScheduleSummarySnapshot: "Weekdays at 9:30 AM [America/Chicago]",
            definitionDraft: draft,
            enqueueOrdinal: 2,
            createdAt: Date(timeIntervalSince1970: 100),
            sourceConversation: conversation,
            project: project
        )
    }
}

private struct ScheduledTaskProposalReopenSources {
    let project: Project
    let firstConversation: Conversation
    let secondConversation: Conversation
}
