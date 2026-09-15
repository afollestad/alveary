import AgentCLIKit
import Foundation
import SwiftData
import XCTest

@testable import Alveary

final class HarnessSessionActionServiceTests: XCTestCase {
    func testArchivesMatchingHarnessRecordsByConversationAndHarnessWithoutWorkingDirectoryFilter() async throws {
        let state = HarnessActionAdapterState()
        let matchingRecord = sessionRecord(
            conversationId: "main",
            harnessId: .codex,
            sessionId: "session-1",
            workingDirectory: "/tmp/renamed-project"
        )
        let store = AgentCLIKit.InMemoryAgentSessionStore(records: [
            matchingRecord,
            sessionRecord(conversationId: "side", harnessId: .codex, sessionId: "session-2", workingDirectory: "/tmp/project"),
            sessionRecord(conversationId: "other", harnessId: .codex, sessionId: "session-3", workingDirectory: "/tmp/other")
        ])
        let service = try await makeService(
            store: store,
            state: state
        )
        let records = try await store.records(
            harnessId: .codex,
            workingDirectory: URL(fileURLWithPath: "/tmp/project", isDirectory: true)
        )

        XCTAssertEqual(records.map(\.harnessSessionId), ["session-2"])

        let resolution = await service.resolveSessions(matching: HarnessSessionActionSnapshot(
            conversationIDs: ["main"],
            harnessIDs: ["codex"],
            workingDirectory: URL(fileURLWithPath: "/tmp/project", isDirectory: true)
        ))
        let diagnostics = await service.archiveSessions(resolution)

        let archivedSessionIDs = await state.archivedSessionIDs

        XCTAssertEqual(diagnostics, [])
        XCTAssertEqual(archivedSessionIDs, ["session-1"])
    }

    func testArchiveFallsBackToPersistedConversationBinding() async throws {
        let state = HarnessActionAdapterState()
        let service = try await makeService(records: [], state: state)

        let resolution = await service.resolveSessions(matching: HarnessSessionActionSnapshot(
            conversations: [
                HarnessSessionConversationSnapshot(
                    conversationID: "main",
                    harnessID: "codex",
                    harnessSessionID: "persisted-session",
                    harnessSessionHarnessID: "codex",
                    harnessSessionWorkingDirectory: "/tmp/project"
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
        let state = HarnessActionAdapterState()
        let service = try await makeService(
            records: [
                sessionRecord(conversationId: "main", harnessId: .codex, sessionId: "live-session", workingDirectory: "/tmp/live")
            ],
            state: state
        )

        let resolution = await service.resolveSessions(matching: HarnessSessionActionSnapshot(
            conversations: [
                HarnessSessionConversationSnapshot(
                    conversationID: "main",
                    harnessID: "codex",
                    harnessSessionID: "persisted-session",
                    harnessSessionHarnessID: "codex",
                    harnessSessionWorkingDirectory: "/tmp/project"
                )
            ],
            workingDirectory: URL(fileURLWithPath: "/tmp/project", isDirectory: true)
        ))
        let diagnostics = await service.archiveSessions(resolution)

        let archivedSessionIDs = await state.archivedSessionIDs

        XCTAssertEqual(diagnostics, [])
        XCTAssertEqual(archivedSessionIDs, ["live-session"])
    }

    func testDuplicateConversationHarnessSnapshotsRouteOnce() async throws {
        let state = HarnessActionAdapterState()
        let service = try await makeService(
            records: [
                sessionRecord(conversationId: "main", harnessId: .codex, sessionId: "session-1", workingDirectory: "/tmp/project")
            ],
            state: state
        )

        let resolution = await service.resolveSessions(matching: HarnessSessionActionSnapshot(
            conversations: [
                HarnessSessionConversationSnapshot(conversationID: "main", harnessID: "codex"),
                HarnessSessionConversationSnapshot(
                    conversationID: "main",
                    harnessID: "codex",
                    harnessSessionID: "persisted-session",
                    harnessSessionHarnessID: "codex",
                    harnessSessionWorkingDirectory: "/tmp/project"
                )
            ],
            workingDirectory: URL(fileURLWithPath: "/tmp/project", isDirectory: true)
        ))
        let diagnostics = await service.archiveSessions(resolution)

        let archivedSessionIDs = await state.archivedSessionIDs

        XCTAssertEqual(diagnostics, [])
        XCTAssertEqual(archivedSessionIDs, ["session-1"])
    }

    func testUnarchivesMatchingHarnessRecords() async throws {
        let state = HarnessActionAdapterState()
        let service = try await makeService(
            records: [
                sessionRecord(conversationId: "main", harnessId: .codex, sessionId: "session-1", workingDirectory: "/tmp/project")
            ],
            state: state
        )

        let resolution = await service.resolveSessions(matching: HarnessSessionActionSnapshot(
            conversationIDs: ["main"],
            harnessIDs: ["codex"],
            workingDirectory: URL(fileURLWithPath: "/tmp/project", isDirectory: true)
        ))
        let diagnostics = await service.unarchiveSessions(resolution)

        let unarchivedSessionIDs = await state.unarchivedSessionIDs

        XCTAssertEqual(diagnostics, [])
        XCTAssertEqual(unarchivedSessionIDs, ["session-1"])
    }

    func testHarnessActionFailureDoesNotStopOtherRecords() async throws {
        let state = HarnessActionAdapterState(failingArchiveSessionIDs: ["session-a"])
        let service = try await makeService(
            records: [
                sessionRecord(conversationId: "a", harnessId: .codex, sessionId: "session-a", workingDirectory: "/tmp/project"),
                sessionRecord(conversationId: "b", harnessId: .codex, sessionId: "session-b", workingDirectory: "/tmp/project")
            ],
            state: state
        )

        let resolution = await service.resolveSessions(matching: HarnessSessionActionSnapshot(
            conversationIDs: ["a", "b"],
            harnessIDs: ["codex"],
            workingDirectory: URL(fileURLWithPath: "/tmp/project", isDirectory: true)
        ))
        let diagnostics = await service.archiveSessions(resolution)

        let archivedSessionIDs = await state.archivedSessionIDs

        XCTAssertEqual(diagnostics.count, 1)
        XCTAssertEqual(diagnostics.first?.action, .archive)
        XCTAssertEqual(diagnostics.first?.harnessID, .codex)
        XCTAssertEqual(diagnostics.first?.harnessSessionID, "session-a")
        XCTAssertEqual(diagnostics.first?.harnessDisplayName, "Codex")
        XCTAssertEqual(diagnostics.first?.message.contains("archive failed"), true)
        XCTAssertEqual(archivedSessionIDs, ["session-b"])
    }

    func testUnsupportedHarnessCapabilitiesSkipActions() async throws {
        let state = HarnessActionAdapterState()
        let store = AgentCLIKit.InMemoryAgentSessionStore(records: [
            sessionRecord(conversationId: "main", harnessId: .claude, sessionId: "claude-session", workingDirectory: "/tmp/project")
        ])
        let service = AgentCLIKitHarnessSessionActionService(
            sessionStore: store,
            router: AgentCLIKit.AgentHarnessSessionActionRouter {
                AgentCLIKit.AgentHarnessAdapterSet(adapters: [
                    HarnessActionDefaultAdapter(harnessId: .claude, state: state)
                ])
            },
            harnessLookup: harnessRegistry(definitions: [harnessDefinition(id: .claude)])
        )

        let archiveResolution = await service.resolveSessions(matching: HarnessSessionActionSnapshot(
            conversationIDs: ["main"],
            harnessIDs: ["claude"],
            workingDirectory: URL(fileURLWithPath: "/tmp/project", isDirectory: true)
        ))
        let archiveDiagnostics = await service.archiveSessions(archiveResolution)
        let unarchiveResolution = await service.resolveSessions(matching: HarnessSessionActionSnapshot(
            conversationIDs: ["main"],
            harnessIDs: ["claude"],
            workingDirectory: URL(fileURLWithPath: "/tmp/project", isDirectory: true)
        ))
        let unarchiveDiagnostics = await service.unarchiveSessions(unarchiveResolution)

        let shutdownCount = await state.shutdownCount

        XCTAssertEqual(archiveDiagnostics, [])
        XCTAssertEqual(unarchiveDiagnostics, [])
        XCTAssertEqual(shutdownCount, 0)
    }

    func testMissingHarnessDefinitionReturnsDiagnostic() async throws {
        let state = HarnessActionAdapterState()
        let service = AgentCLIKitHarnessSessionActionService(
            sessionStore: AgentCLIKit.InMemoryAgentSessionStore(records: [
                sessionRecord(conversationId: "main", harnessId: .codex, sessionId: "session-1", workingDirectory: "/tmp/project")
            ]),
            router: AgentCLIKit.AgentHarnessSessionActionRouter {
                AgentCLIKit.AgentHarnessAdapterSet(adapters: [
                    HarnessActionRecordingAdapter(harnessId: .codex, state: state)
                ])
            },
            harnessLookup: harnessRegistry(definitions: [])
        )

        let resolution = await service.resolveSessions(matching: HarnessSessionActionSnapshot(
            conversationIDs: ["main"],
            harnessIDs: ["codex"],
            workingDirectory: URL(fileURLWithPath: "/tmp/project", isDirectory: true)
        ))
        let diagnostics = await service.archiveSessions(resolution)

        let archivedSessionIDs = await state.archivedSessionIDs
        let shutdownCount = await state.shutdownCount

        XCTAssertEqual(diagnostics, [
            HarnessSessionActionDiagnostic(
                action: .archive,
                harnessID: .codex,
                harnessDisplayName: "codex",
                harnessSessionID: "session-1",
                conversationID: "main",
                message: "Harness is not registered."
            )
        ])
        XCTAssertEqual(archivedSessionIDs, [])
        XCTAssertEqual(shutdownCount, 0)
    }

    func testMissingBindingReturnsDiagnosticForSupportedHarness() async throws {
        let state = HarnessActionAdapterState()
        let service = try await makeService(records: [], state: state)

        let resolution = await service.resolveSessions(matching: HarnessSessionActionSnapshot(
            conversations: [
                HarnessSessionConversationSnapshot(conversationID: "main", harnessID: "codex")
            ],
            workingDirectory: URL(fileURLWithPath: "/tmp/project", isDirectory: true)
        ))
        let diagnostics = await service.archiveSessions(resolution)

        let archivedSessionIDs = await state.archivedSessionIDs

        XCTAssertEqual(diagnostics, [
            HarnessSessionActionDiagnostic(
                action: .archive,
                harnessID: .codex,
                harnessDisplayName: "Codex",
                harnessSessionID: nil,
                conversationID: "main",
                message: "No harness session binding is available."
            )
        ])
        XCTAssertEqual(archivedSessionIDs, [])
    }

    @MainActor
    func testSwiftDataHarnessSessionBindingStoreRecordsConversationFields() async throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Project.self,
            AgentThread.self,
            Conversation.self,
            ConversationEventRecord.self,
            ScheduledTask.self,
            ScheduledTaskRun.self,
            ScheduledTaskProposal.self,
            configurations: configuration
        )
        let context = ModelContext(container)
        let conversation = Conversation(id: "main", title: "Main", harness: "codex")
        context.insert(conversation)
        try context.save()

        let existing = try requireConversation(id: "main", in: container)
        XCTAssertNil(existing.harnessSessionId)
        XCTAssertNil(existing.harnessSessionHarnessId)
        XCTAssertNil(existing.harnessSessionWorkingDirectory)

        let store = SwiftDataHarnessSessionBindingStore(modelContainer: container)
        await store.record(HarnessSessionBinding(
            conversationID: "main",
            harnessID: "codex",
            harnessSessionID: "codex-thread",
            workingDirectory: "/tmp/alveary-project"
        ))

        let updated = try requireConversation(id: "main", in: container)
        XCTAssertEqual(updated.harnessSessionId, "codex-thread")
        XCTAssertEqual(updated.harnessSessionHarnessId, "codex")
        XCTAssertEqual(updated.harnessSessionWorkingDirectory, "/tmp/alveary-project")
    }

    // Shared with the `+Deletion.swift` companion, so these stay internal.
    func makeService(
        records: [AgentCLIKit.AgentSessionRecord],
        state: HarnessActionAdapterState
    ) async throws -> AgentCLIKitHarnessSessionActionService {
        try await makeService(
            store: AgentCLIKit.InMemoryAgentSessionStore(records: records),
            state: state
        )
    }

    func makeService(
        store: AgentCLIKit.InMemoryAgentSessionStore,
        state: HarnessActionAdapterState,
        capabilities: AgentCLIKit.AgentHarnessCapabilities = AgentCLIKit.AgentHarnessCapabilities(
            supportsSessionArchiving: true,
            supportsSessionUnarchiving: true,
            supportsSessionDeletion: true
        )
    ) async throws -> AgentCLIKitHarnessSessionActionService {
        return AgentCLIKitHarnessSessionActionService(
            sessionStore: store,
            router: AgentCLIKit.AgentHarnessSessionActionRouter {
                AgentCLIKit.AgentHarnessAdapterSet(adapters: [
                    HarnessActionRecordingAdapter(harnessId: .codex, state: state)
                ])
            },
            harnessLookup: harnessRegistry(definitions: [
                harnessDefinition(id: .codex, displayName: "Codex", capabilities: capabilities)
            ])
        )
    }

    private func harnessRegistry(definitions: [AgentCLIKit.AgentHarnessDefinition]) -> AgentCLIKit.AgentHarnessRegistry {
        AgentCLIKit.AgentHarnessRegistry(definitions: definitions)
    }

    private func harnessDefinition(
        id: AgentCLIKit.AgentHarnessID,
        displayName: String = "Harness",
        capabilities: AgentCLIKit.AgentHarnessCapabilities = AgentCLIKit.AgentHarnessCapabilities()
    ) -> AgentCLIKit.AgentHarnessDefinition {
        AgentCLIKit.AgentHarnessDefinition(
            id: id,
            displayName: displayName,
            executableNames: [id.rawValue],
            capabilities: capabilities
        )
    }

    func sessionRecord(
        conversationId: AgentCLIKit.AgentConversationID,
        harnessId: AgentCLIKit.AgentHarnessID,
        sessionId: AgentCLIKit.AgentSessionID,
        workingDirectory: String
    ) -> AgentCLIKit.AgentSessionRecord {
        AgentCLIKit.AgentSessionRecord(
            conversationId: conversationId,
            harnessId: harnessId,
            harnessSessionId: sessionId,
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
            throw HarnessSessionActionServiceTestError.conversationMissing
        }
        return conversation
    }
}

private enum HarnessSessionActionServiceTestError: Error {
    case conversationMissing
}
