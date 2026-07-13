import AgentCLIKit
import Foundation
import SwiftData
import XCTest

@testable import Alveary

final class ProviderSessionActionServiceTests: XCTestCase {
    func testArchivesMatchingProviderRecordsByConversationAndProviderWithoutWorkingDirectoryFilter() async throws {
        let state = ProviderActionAdapterState()
        let matchingRecord = sessionRecord(
            conversationId: "main",
            providerId: .codex,
            sessionId: "session-1",
            workingDirectory: "/tmp/renamed-project"
        )
        let store = AgentCLIKit.InMemoryAgentSessionStore(records: [
            matchingRecord,
            sessionRecord(conversationId: "side", providerId: .codex, sessionId: "session-2", workingDirectory: "/tmp/project"),
            sessionRecord(conversationId: "other", providerId: .codex, sessionId: "session-3", workingDirectory: "/tmp/other")
        ])
        let service = try await makeService(
            store: store,
            state: state
        )
        let records = try await store.records(
            providerId: .codex,
            workingDirectory: URL(fileURLWithPath: "/tmp/project", isDirectory: true)
        )

        XCTAssertEqual(records.map(\.providerSessionId), ["session-2"])

        let resolution = await service.resolveSessions(matching: ProviderSessionActionSnapshot(
            conversationIDs: ["main"],
            providerIDs: ["codex"],
            workingDirectory: URL(fileURLWithPath: "/tmp/project", isDirectory: true)
        ))
        let diagnostics = await service.archiveSessions(resolution)

        let archivedSessionIDs = await state.archivedSessionIDs

        XCTAssertEqual(diagnostics, [])
        XCTAssertEqual(archivedSessionIDs, ["session-1"])
    }

    func testArchiveFallsBackToPersistedConversationBinding() async throws {
        let state = ProviderActionAdapterState()
        let service = try await makeService(records: [], state: state)

        let resolution = await service.resolveSessions(matching: ProviderSessionActionSnapshot(
            conversations: [
                ProviderSessionConversationSnapshot(
                    conversationID: "main",
                    providerID: "codex",
                    providerSessionID: "persisted-session",
                    providerSessionProviderID: "codex",
                    providerSessionWorkingDirectory: "/tmp/project"
                )
            ],
            workingDirectory: URL(fileURLWithPath: "/tmp/project", isDirectory: true)
        ))
        let diagnostics = await service.archiveSessions(resolution)

        let archivedSessionIDs = await state.archivedSessionIDs

        XCTAssertEqual(diagnostics, [])
        XCTAssertEqual(archivedSessionIDs, ["persisted-session"])
    }

    func testLiveRecordWinsOverPersistedConversationBinding() async throws {
        let state = ProviderActionAdapterState()
        let service = try await makeService(
            records: [
                sessionRecord(conversationId: "main", providerId: .codex, sessionId: "live-session", workingDirectory: "/tmp/live")
            ],
            state: state
        )

        let resolution = await service.resolveSessions(matching: ProviderSessionActionSnapshot(
            conversations: [
                ProviderSessionConversationSnapshot(
                    conversationID: "main",
                    providerID: "codex",
                    providerSessionID: "persisted-session",
                    providerSessionProviderID: "codex",
                    providerSessionWorkingDirectory: "/tmp/project"
                )
            ],
            workingDirectory: URL(fileURLWithPath: "/tmp/project", isDirectory: true)
        ))
        let diagnostics = await service.archiveSessions(resolution)

        let archivedSessionIDs = await state.archivedSessionIDs

        XCTAssertEqual(diagnostics, [])
        XCTAssertEqual(archivedSessionIDs, ["live-session"])
    }

    func testDuplicateConversationProviderSnapshotsRouteOnce() async throws {
        let state = ProviderActionAdapterState()
        let service = try await makeService(
            records: [
                sessionRecord(conversationId: "main", providerId: .codex, sessionId: "session-1", workingDirectory: "/tmp/project")
            ],
            state: state
        )

        let resolution = await service.resolveSessions(matching: ProviderSessionActionSnapshot(
            conversations: [
                ProviderSessionConversationSnapshot(conversationID: "main", providerID: "codex"),
                ProviderSessionConversationSnapshot(
                    conversationID: "main",
                    providerID: "codex",
                    providerSessionID: "persisted-session",
                    providerSessionProviderID: "codex",
                    providerSessionWorkingDirectory: "/tmp/project"
                )
            ],
            workingDirectory: URL(fileURLWithPath: "/tmp/project", isDirectory: true)
        ))
        let diagnostics = await service.archiveSessions(resolution)

        let archivedSessionIDs = await state.archivedSessionIDs

        XCTAssertEqual(diagnostics, [])
        XCTAssertEqual(archivedSessionIDs, ["session-1"])
    }

    func testUnarchivesMatchingProviderRecords() async throws {
        let state = ProviderActionAdapterState()
        let service = try await makeService(
            records: [
                sessionRecord(conversationId: "main", providerId: .codex, sessionId: "session-1", workingDirectory: "/tmp/project")
            ],
            state: state
        )

        let resolution = await service.resolveSessions(matching: ProviderSessionActionSnapshot(
            conversationIDs: ["main"],
            providerIDs: ["codex"],
            workingDirectory: URL(fileURLWithPath: "/tmp/project", isDirectory: true)
        ))
        let diagnostics = await service.unarchiveSessions(resolution)

        let unarchivedSessionIDs = await state.unarchivedSessionIDs

        XCTAssertEqual(diagnostics, [])
        XCTAssertEqual(unarchivedSessionIDs, ["session-1"])
    }

    func testDeletesMatchingProviderRecords() async throws {
        let state = ProviderActionAdapterState()
        let service = try await makeService(
            records: [
                sessionRecord(conversationId: "main", providerId: .codex, sessionId: "session-1", workingDirectory: "/tmp/project")
            ],
            state: state
        )

        let resolution = await service.resolveSessions(matching: ProviderSessionActionSnapshot(
            conversationIDs: ["main"],
            providerIDs: ["codex"],
            workingDirectory: URL(fileURLWithPath: "/tmp/project", isDirectory: true)
        ))
        let diagnostics = await service.deleteSessions(resolution)

        let deletedSessionIDs = await state.deletedSessionIDs

        XCTAssertEqual(diagnostics, [])
        XCTAssertEqual(deletedSessionIDs, ["session-1"])
    }

    func testDeleteFallsBackToArchiveWhenProviderDeleteFails() async throws {
        let state = ProviderActionAdapterState(failingDeleteSessionIDs: ["session-1"])
        let service = try await makeService(
            records: [
                sessionRecord(conversationId: "main", providerId: .codex, sessionId: "session-1", workingDirectory: "/tmp/project")
            ],
            state: state
        )

        let resolution = await service.resolveSessions(matching: ProviderSessionActionSnapshot(
            conversationIDs: ["main"],
            providerIDs: ["codex"],
            workingDirectory: URL(fileURLWithPath: "/tmp/project", isDirectory: true)
        ))
        let diagnostics = await service.deleteSessions(resolution)

        let archivedSessionIDs = await state.archivedSessionIDs
        let deletedSessionIDs = await state.deletedSessionIDs

        XCTAssertEqual(diagnostics, [])
        XCTAssertEqual(deletedSessionIDs, [])
        XCTAssertEqual(archivedSessionIDs, ["session-1"])
    }

    func testProviderActionFailureDoesNotStopOtherRecords() async throws {
        let state = ProviderActionAdapterState(failingArchiveSessionIDs: ["session-a"])
        let service = try await makeService(
            records: [
                sessionRecord(conversationId: "a", providerId: .codex, sessionId: "session-a", workingDirectory: "/tmp/project"),
                sessionRecord(conversationId: "b", providerId: .codex, sessionId: "session-b", workingDirectory: "/tmp/project")
            ],
            state: state
        )

        let resolution = await service.resolveSessions(matching: ProviderSessionActionSnapshot(
            conversationIDs: ["a", "b"],
            providerIDs: ["codex"],
            workingDirectory: URL(fileURLWithPath: "/tmp/project", isDirectory: true)
        ))
        let diagnostics = await service.archiveSessions(resolution)

        let archivedSessionIDs = await state.archivedSessionIDs

        XCTAssertEqual(diagnostics.count, 1)
        XCTAssertEqual(diagnostics.first?.action, .archive)
        XCTAssertEqual(diagnostics.first?.providerID, .codex)
        XCTAssertEqual(diagnostics.first?.providerSessionID, "session-a")
        XCTAssertEqual(diagnostics.first?.providerDisplayName, "Codex")
        XCTAssertEqual(diagnostics.first?.message.contains("archive failed"), true)
        XCTAssertEqual(archivedSessionIDs, ["session-b"])
    }

    func testUnsupportedProviderCapabilitiesSkipActions() async throws {
        let state = ProviderActionAdapterState()
        let store = AgentCLIKit.InMemoryAgentSessionStore(records: [
            sessionRecord(conversationId: "main", providerId: .claude, sessionId: "claude-session", workingDirectory: "/tmp/project")
        ])
        let service = AgentCLIKitProviderSessionActionService(
            sessionStore: store,
            router: AgentCLIKit.AgentProviderSessionActionRouter {
                AgentCLIKit.AgentProviderAdapterSet(adapters: [
                    ProviderActionDefaultAdapter(providerId: .claude, state: state)
                ])
            },
            providerLookup: providerRegistry(definitions: [providerDefinition(id: .claude)])
        )

        let archiveResolution = await service.resolveSessions(matching: ProviderSessionActionSnapshot(
            conversationIDs: ["main"],
            providerIDs: ["claude"],
            workingDirectory: URL(fileURLWithPath: "/tmp/project", isDirectory: true)
        ))
        let archiveDiagnostics = await service.archiveSessions(archiveResolution)
        let unarchiveResolution = await service.resolveSessions(matching: ProviderSessionActionSnapshot(
            conversationIDs: ["main"],
            providerIDs: ["claude"],
            workingDirectory: URL(fileURLWithPath: "/tmp/project", isDirectory: true)
        ))
        let unarchiveDiagnostics = await service.unarchiveSessions(unarchiveResolution)

        let shutdownCount = await state.shutdownCount

        XCTAssertEqual(archiveDiagnostics, [])
        XCTAssertEqual(unarchiveDiagnostics, [])
        XCTAssertEqual(shutdownCount, 0)
    }

    func testMissingProviderDefinitionReturnsDiagnostic() async throws {
        let state = ProviderActionAdapterState()
        let service = AgentCLIKitProviderSessionActionService(
            sessionStore: AgentCLIKit.InMemoryAgentSessionStore(records: [
                sessionRecord(conversationId: "main", providerId: .codex, sessionId: "session-1", workingDirectory: "/tmp/project")
            ]),
            router: AgentCLIKit.AgentProviderSessionActionRouter {
                AgentCLIKit.AgentProviderAdapterSet(adapters: [
                    ProviderActionRecordingAdapter(providerId: .codex, state: state)
                ])
            },
            providerLookup: providerRegistry(definitions: [])
        )

        let resolution = await service.resolveSessions(matching: ProviderSessionActionSnapshot(
            conversationIDs: ["main"],
            providerIDs: ["codex"],
            workingDirectory: URL(fileURLWithPath: "/tmp/project", isDirectory: true)
        ))
        let diagnostics = await service.archiveSessions(resolution)

        let archivedSessionIDs = await state.archivedSessionIDs
        let shutdownCount = await state.shutdownCount

        XCTAssertEqual(diagnostics, [
            ProviderSessionActionDiagnostic(
                action: .archive,
                providerID: .codex,
                providerDisplayName: "codex",
                providerSessionID: "session-1",
                conversationID: "main",
                message: "Provider is not registered."
            )
        ])
        XCTAssertEqual(archivedSessionIDs, [])
        XCTAssertEqual(shutdownCount, 0)
    }

    func testMissingBindingReturnsDiagnosticForSupportedProvider() async throws {
        let state = ProviderActionAdapterState()
        let service = try await makeService(records: [], state: state)

        let resolution = await service.resolveSessions(matching: ProviderSessionActionSnapshot(
            conversations: [
                ProviderSessionConversationSnapshot(conversationID: "main", providerID: "codex")
            ],
            workingDirectory: URL(fileURLWithPath: "/tmp/project", isDirectory: true)
        ))
        let diagnostics = await service.archiveSessions(resolution)

        let archivedSessionIDs = await state.archivedSessionIDs

        XCTAssertEqual(diagnostics, [
            ProviderSessionActionDiagnostic(
                action: .archive,
                providerID: .codex,
                providerDisplayName: "Codex",
                providerSessionID: nil,
                conversationID: "main",
                message: "No provider session binding is available."
            )
        ])
        XCTAssertEqual(archivedSessionIDs, [])
    }

    @MainActor
    func testSwiftDataProviderSessionBindingStoreRecordsConversationFields() async throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Project.self,
            AgentThread.self,
            Conversation.self,
            ConversationEventRecord.self,
            ScheduledTask.self,
            ScheduledTaskRun.self,
            configurations: configuration
        )
        let context = ModelContext(container)
        let conversation = Conversation(id: "main", title: "Main", provider: "codex")
        context.insert(conversation)
        try context.save()

        let existing = try requireConversation(id: "main", in: container)
        XCTAssertNil(existing.providerSessionId)
        XCTAssertNil(existing.providerSessionProviderId)
        XCTAssertNil(existing.providerSessionWorkingDirectory)

        let store = SwiftDataProviderSessionBindingStore(modelContainer: container)
        await store.record(ProviderSessionBinding(
            conversationID: "main",
            providerID: "codex",
            providerSessionID: "codex-thread",
            workingDirectory: "/tmp/alveary-project"
        ))

        let updated = try requireConversation(id: "main", in: container)
        XCTAssertEqual(updated.providerSessionId, "codex-thread")
        XCTAssertEqual(updated.providerSessionProviderId, "codex")
        XCTAssertEqual(updated.providerSessionWorkingDirectory, "/tmp/alveary-project")
    }

    private func makeService(
        records: [AgentCLIKit.AgentSessionRecord],
        state: ProviderActionAdapterState
    ) async throws -> AgentCLIKitProviderSessionActionService {
        try await makeService(
            store: AgentCLIKit.InMemoryAgentSessionStore(records: records),
            state: state
        )
    }

    private func makeService(
        store: AgentCLIKit.InMemoryAgentSessionStore,
        state: ProviderActionAdapterState
    ) async throws -> AgentCLIKitProviderSessionActionService {
        return AgentCLIKitProviderSessionActionService(
            sessionStore: store,
            router: AgentCLIKit.AgentProviderSessionActionRouter {
                AgentCLIKit.AgentProviderAdapterSet(adapters: [
                    ProviderActionRecordingAdapter(providerId: .codex, state: state)
                ])
            },
            providerLookup: providerRegistry(definitions: [
                providerDefinition(
                    id: .codex,
                    displayName: "Codex",
                    capabilities: AgentCLIKit.AgentProviderCapabilities(
                        supportsSessionArchiving: true,
                        supportsSessionUnarchiving: true
                    )
                )
            ])
        )
    }

    private func providerRegistry(definitions: [AgentCLIKit.AgentProviderDefinition]) -> AgentCLIKit.AgentProviderRegistry {
        AgentCLIKit.AgentProviderRegistry(definitions: definitions)
    }

    private func providerDefinition(
        id: AgentCLIKit.AgentProviderID,
        displayName: String = "Provider",
        capabilities: AgentCLIKit.AgentProviderCapabilities = AgentCLIKit.AgentProviderCapabilities()
    ) -> AgentCLIKit.AgentProviderDefinition {
        AgentCLIKit.AgentProviderDefinition(
            id: id,
            displayName: displayName,
            executableNames: [id.rawValue],
            capabilities: capabilities
        )
    }

    private func sessionRecord(
        conversationId: AgentCLIKit.AgentConversationID,
        providerId: AgentCLIKit.AgentProviderID,
        sessionId: AgentCLIKit.AgentSessionID,
        workingDirectory: String
    ) -> AgentCLIKit.AgentSessionRecord {
        AgentCLIKit.AgentSessionRecord(
            conversationId: conversationId,
            providerId: providerId,
            providerSessionId: sessionId,
            workingDirectory: URL(fileURLWithPath: workingDirectory, isDirectory: true),
            generation: 0,
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 0)
        )
    }

    @MainActor
    private func requireConversation(id: String, in container: ModelContainer) throws -> Conversation {
        let context = ModelContext(container)
        guard let conversation = context.resolveConversation(conversationID: id) else {
            throw ProviderSessionActionServiceTestError.conversationMissing
        }
        return conversation
    }
}

private enum ProviderSessionActionServiceTestError: Error {
    case conversationMissing
}
