import Foundation
import SwiftData
import XCTest

@testable import Alveary

/// Literal column names pin the pre-rename storage contract independently of the app's source properties.
@MainActor
final class HarnessPersistenceCompatibilityTests: XCTestCase {
    func testHarnessTerminologyKeepsExistingDatabaseColumns() throws {
        let schema = Schema(versionedSchema: AlvearySchema.self)
        XCTAssertEqual(schema.version, Schema.Version(3, 0, 0))
        let expected: [String: Set<String>] = [
            "Conversation": ["provider", "providerSessionId", "providerSessionProviderId", "providerSessionWorkingDirectory"],
            "ConversationEventRecord": ["providerModelId"],
            "ScheduledTask": ["providerID"],
            "ScheduledTaskRun": ["providerIDSnapshot"],
            "ScheduledTaskProposal": ["sourceProviderID"]
        ]
        for (name, columns) in expected {
            let entity = try XCTUnwrap(schema.entitiesByName[name])
            XCTAssertEqual(identityColumns(in: entity), columns, name)
        }

        let approvals = Schema([AgentSessionApprovalRule.self, AgentSessionApprovalSelection.self])
        for name in ["AgentSessionApprovalRule", "AgentSessionApprovalSelection"] {
            let entity = try XCTUnwrap(approvals.entitiesByName[name])
            XCTAssertEqual(identityColumns(in: entity), ["providerId"], name)
        }
    }

    func testSavedSessionAndScheduledHistorySurviveDatabaseReopen() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("Alveary.store")
        try autoreleasepool {
            let container = try DataComponent.openModelContainer(isStoredInMemoryOnly: false, persistentStoreURL: url)
            try populateHistory(in: container.mainContext)
        }

        try autoreleasepool {
            let container = try DataComponent.openModelContainer(isStoredInMemoryOnly: false, persistentStoreURL: url)
            let context = container.mainContext
            let conversation = try XCTUnwrap(context.fetch(FetchDescriptor<Conversation>()).first)
            XCTAssertEqual(conversation.harness, "claude")
            XCTAssertEqual(conversation.harnessSessionHarnessId, "codex")
            XCTAssertEqual(conversation.harnessSessionId, "saved-session")
            XCTAssertEqual(conversation.harnessSessionWorkingDirectory, "/tmp/saved-session")
            let event = try XCTUnwrap(conversation.events.first)
            XCTAssertEqual(event.harnessModelId, "saved-model")
            XCTAssertEqual(event.tokenInput, 731)
            XCTAssertEqual(event.contextWindowSize, 200_000)
            let definition = try XCTUnwrap(context.fetch(FetchDescriptor<ScheduledTask>()).first)
            let run = try XCTUnwrap(context.fetch(FetchDescriptor<ScheduledTaskRun>()).first)
            XCTAssertEqual(definition.harnessID, "claude")
            XCTAssertEqual(run.harnessIDSnapshot, "codex")
            XCTAssertEqual(run.scheduledTask?.id, definition.id)
            let proposal = try XCTUnwrap(context.fetch(FetchDescriptor<ScheduledTaskProposal>()).first)
            XCTAssertEqual(proposal.sourceHarnessID, "codex")
            XCTAssertEqual(proposal.sourceConversation?.id, conversation.id)
            conversation.harnessSessionId = "resumed-session"
            try context.save()
        }

        let reopened = try DataComponent.openModelContainer(isStoredInMemoryOnly: false, persistentStoreURL: url)
        let conversation = try XCTUnwrap(reopened.mainContext.fetch(FetchDescriptor<Conversation>()).first)
        XCTAssertEqual(conversation.harnessSessionId, "resumed-session")
        XCTAssertEqual(conversation.events.first?.harnessModelId, "saved-model")
    }

    func testStoredApprovalLookupAndRemovalRemainHarnessScoped() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try autoreleasepool {
            let container = try ModelContainer(
                for: AgentSessionApprovalRule.self, AgentSessionApprovalSelection.self,
                configurations: .init(url: directory.appendingPathComponent("session-approvals.store"))
            )
            for identifier in ["claude", "codex"] {
                container.mainContext.insert(AgentSessionApprovalRule(
                    harnessId: identifier, conversationId: "conversation", sessionId: "session",
                    matchKind: "bashExact", matchValue: "git status"
                ))
                container.mainContext.insert(AgentSessionApprovalSelection(
                    harnessId: identifier, conversationId: "conversation", sessionId: "session", selection: "sessionExact"
                ))
            }
            try container.mainContext.save()
        }

        let store = DefaultClaudeApprovalPersistenceStore(supportDirectory: directory)
        let claude = AgentSessionApprovalGrant(
            harnessId: "claude", conversationId: "conversation", sessionId: "session", matchKind: .bashExact, matchValue: "git status"
        )
        let codex = AgentSessionApprovalGrant(
            harnessId: "codex", conversationId: "conversation", sessionId: "session", matchKind: .bashExact, matchValue: "git status"
        )
        let allowsClaude = await store.allowsSessionApproval(matching: [claude])
        let selection = await store.toolApprovalSelection(harnessId: "claude", conversationId: "conversation", sessionId: "session")
        XCTAssertTrue(allowsClaude)
        XCTAssertEqual(selection, .sessionExact)

        await store.removeSessionApprovals(harnessId: "claude", conversationId: "conversation", sessionId: "session")
        let removed = await store.allowsSessionApproval(matching: [claude])
        let retained = await store.allowsSessionApproval(matching: [codex])
        let retainedSelection = await store.toolApprovalSelection(harnessId: "codex", conversationId: "conversation", sessionId: "session")
        XCTAssertFalse(removed)
        XCTAssertTrue(retained)
        XCTAssertEqual(retainedSelection, .sessionExact)
    }

    func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func identityColumns(in entity: Schema.Entity) -> Set<String> {
        Set(entity.properties.map(\.name).filter {
            $0.localizedCaseInsensitiveContains("provider") || $0.localizedCaseInsensitiveContains("harness")
        })
    }

    private func populateHistory(in context: ModelContext) throws {
        let conversation = Conversation(
            id: "saved-conversation", harness: "claude", harnessSessionId: "saved-session",
            harnessSessionHarnessId: "codex", harnessSessionWorkingDirectory: "/tmp/saved-session"
        )
        let event = ConversationEventRecord(
            conversationId: conversation.id, type: "tokens", tokenInput: 731,
            harnessModelId: "saved-model", contextWindowSize: 200_000, conversation: conversation
        )
        conversation.events = [event]
        let definition = ScheduledTask(
            title: "Saved schedule", prompt: "Keep the snapshot.", destination: .newThreadPerRun,
            recurrence: .daily(hour: 9, minute: 0), timeZoneIdentifier: "UTC", harnessID: "codex"
        )
        let run = ScheduledTaskRun(
            snapshotting: definition, occurrenceID: "saved-occurrence",
            occurrenceAt: Date(timeIntervalSince1970: 1_800_000_000), triggerKind: .scheduled
        )
        definition.harnessID = "claude"
        let proposal = ScheduledTaskProposal(
            deduplicationKey: "saved-proposal", action: .create,
            canonicalPayloadJSON: #"{"action":"create"}"#, canonicalPayloadHash: "saved-hash",
            sourceHarnessID: "codex", sourceProcessToken: UUID(), sourceRequestID: "string:saved-request",
            sourceConversation: conversation
        )
        context.insert(conversation)
        context.insert(definition)
        context.insert(run)
        context.insert(proposal)
        try context.save()
    }
}
