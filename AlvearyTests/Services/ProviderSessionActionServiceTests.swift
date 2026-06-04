import AgentCLIKit
import Foundation
import XCTest

@testable import Alveary

final class ProviderSessionActionServiceTests: XCTestCase {
    func testArchivesMatchingProviderRecordsForWorkingDirectory() async throws {
        let state = ProviderActionAdapterState()
        let matchingRecord = sessionRecord(
            conversationId: "main",
            providerId: .codex,
            sessionId: "session-1",
            workingDirectory: "/tmp/project"
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

        XCTAssertEqual(records.map(\.providerSessionId), [matchingRecord.providerSessionId, "session-2"])

        let resolution = await service.resolveSessions(matching: ProviderSessionActionSnapshot(
            conversationIDs: ["main"],
            providerIDs: ["codex"],
            workingDirectory: URL(fileURLWithPath: "/tmp/project", isDirectory: true)
        ))
        await service.archiveSessions(resolution)

        let archivedSessionIDs = await state.archivedSessionIDs

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
        await service.unarchiveSessions(resolution)

        let unarchivedSessionIDs = await state.unarchivedSessionIDs

        XCTAssertEqual(unarchivedSessionIDs, ["session-1"])
    }

    func testMissingSessionRecordsDoNothing() async throws {
        let state = ProviderActionAdapterState()
        let service = try await makeService(records: [], state: state)

        let resolution = await service.resolveSessions(matching: ProviderSessionActionSnapshot(
            conversationIDs: ["missing"],
            providerIDs: ["codex"],
            workingDirectory: URL(fileURLWithPath: "/tmp/project", isDirectory: true)
        ))
        await service.archiveSessions(resolution)

        let archivedSessionIDs = await state.archivedSessionIDs
        let shutdownCount = await state.shutdownCount

        XCTAssertEqual(archivedSessionIDs, [])
        XCTAssertEqual(shutdownCount, 0)
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
        await service.archiveSessions(resolution)

        let archivedSessionIDs = await state.archivedSessionIDs

        XCTAssertEqual(archivedSessionIDs, ["session-b"])
    }

    func testClaudeProviderSessionActionNoOps() async throws {
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
            }
        )

        let archiveResolution = await service.resolveSessions(matching: ProviderSessionActionSnapshot(
            conversationIDs: ["main"],
            providerIDs: ["claude"],
            workingDirectory: URL(fileURLWithPath: "/tmp/project", isDirectory: true)
        ))
        await service.archiveSessions(archiveResolution)
        let unarchiveResolution = await service.resolveSessions(matching: ProviderSessionActionSnapshot(
            conversationIDs: ["main"],
            providerIDs: ["claude"],
            workingDirectory: URL(fileURLWithPath: "/tmp/project", isDirectory: true)
        ))
        await service.unarchiveSessions(unarchiveResolution)

        let shutdownCount = await state.shutdownCount

        XCTAssertEqual(shutdownCount, 2)
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
            }
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
}

private struct ProviderActionDefaultAdapter: AgentCLIKit.AgentProviderAdapter {
    let providerId: AgentCLIKit.AgentProviderID
    let state: ProviderActionAdapterState

    var definition: AgentCLIKit.AgentProviderDefinition {
        AgentCLIKit.AgentProviderDefinition(id: providerId, displayName: "Provider", executableNames: ["provider"])
    }

    func makeLaunchConfiguration(
        spawnConfig: AgentCLIKit.AgentSpawnConfig,
        resumedSession: AgentCLIKit.AgentSessionRecord?
    ) async throws -> AgentCLIKit.AgentLaunchConfiguration {
        AgentCLIKit.AgentLaunchConfiguration(executable: "/usr/bin/true")
    }

    func decodeStdoutLine(_ line: String) async throws -> [AgentCLIKit.AgentEvent] {
        []
    }

    func encodeInput(_ input: AgentCLIKit.AgentInput) async throws -> Data {
        Data()
    }

    func shutdownProviderResources() async {
        await state.recordShutdown()
    }
}

private struct ProviderActionRecordingAdapter: AgentCLIKit.AgentProviderAdapter {
    let providerId: AgentCLIKit.AgentProviderID
    let state: ProviderActionAdapterState

    var definition: AgentCLIKit.AgentProviderDefinition {
        AgentCLIKit.AgentProviderDefinition(id: providerId, displayName: "Provider", executableNames: ["provider"])
    }

    func makeLaunchConfiguration(
        spawnConfig: AgentCLIKit.AgentSpawnConfig,
        resumedSession: AgentCLIKit.AgentSessionRecord?
    ) async throws -> AgentCLIKit.AgentLaunchConfiguration {
        AgentCLIKit.AgentLaunchConfiguration(executable: "/usr/bin/true")
    }

    func decodeStdoutLine(_ line: String) async throws -> [AgentCLIKit.AgentEvent] {
        []
    }

    func encodeInput(_ input: AgentCLIKit.AgentInput) async throws -> Data {
        Data()
    }

    func archiveSession(_ record: AgentCLIKit.AgentSessionRecord) async throws {
        try await state.recordArchive(record.providerSessionId)
    }

    func unarchiveSession(_ record: AgentCLIKit.AgentSessionRecord) async throws {
        await state.recordUnarchive(record.providerSessionId)
    }

    func shutdownProviderResources() async {
        await state.recordShutdown()
    }
}

private actor ProviderActionAdapterState {
    private let failingArchiveSessionIDs: Set<AgentCLIKit.AgentSessionID>
    private var archived: [AgentCLIKit.AgentSessionID] = []
    private var unarchived: [AgentCLIKit.AgentSessionID] = []
    private var shutdowns = 0

    init(failingArchiveSessionIDs: Set<AgentCLIKit.AgentSessionID> = []) {
        self.failingArchiveSessionIDs = failingArchiveSessionIDs
    }

    var archivedSessionIDs: [AgentCLIKit.AgentSessionID] {
        archived
    }

    var unarchivedSessionIDs: [AgentCLIKit.AgentSessionID] {
        unarchived
    }

    var shutdownCount: Int {
        shutdowns
    }

    func recordArchive(_ sessionID: AgentCLIKit.AgentSessionID) throws {
        if failingArchiveSessionIDs.contains(sessionID) {
            throw AgentCLIKit.AgentCLIError.invalidInput("archive failed")
        }
        archived.append(sessionID)
    }

    func recordUnarchive(_ sessionID: AgentCLIKit.AgentSessionID) {
        unarchived.append(sessionID)
    }

    func recordShutdown() {
        shutdowns += 1
    }
}
