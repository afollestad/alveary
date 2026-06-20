import AgentCLIKit
import Foundation

@testable import Alveary

struct ProviderActionDefaultAdapter: AgentCLIKit.AgentProviderAdapter {
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

struct ProviderActionRecordingAdapter: AgentCLIKit.AgentProviderAdapter {
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

    func deleteSession(_ record: AgentCLIKit.AgentSessionRecord) async throws {
        try await state.recordDelete(record.providerSessionId)
    }

    func shutdownProviderResources() async {
        await state.recordShutdown()
    }
}

actor ProviderActionAdapterState {
    private let failingArchiveSessionIDs: Set<AgentCLIKit.AgentSessionID>
    private let failingDeleteSessionIDs: Set<AgentCLIKit.AgentSessionID>
    private var archived: [AgentCLIKit.AgentSessionID] = []
    private var unarchived: [AgentCLIKit.AgentSessionID] = []
    private var deleted: [AgentCLIKit.AgentSessionID] = []
    private var shutdowns = 0

    init(
        failingArchiveSessionIDs: Set<AgentCLIKit.AgentSessionID> = [],
        failingDeleteSessionIDs: Set<AgentCLIKit.AgentSessionID> = []
    ) {
        self.failingArchiveSessionIDs = failingArchiveSessionIDs
        self.failingDeleteSessionIDs = failingDeleteSessionIDs
    }

    var archivedSessionIDs: [AgentCLIKit.AgentSessionID] {
        archived
    }

    var unarchivedSessionIDs: [AgentCLIKit.AgentSessionID] {
        unarchived
    }

    var deletedSessionIDs: [AgentCLIKit.AgentSessionID] {
        deleted
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

    func recordDelete(_ sessionID: AgentCLIKit.AgentSessionID) throws {
        if failingDeleteSessionIDs.contains(sessionID) {
            throw AgentCLIKit.AgentCLIError.invalidInput("delete failed")
        }
        deleted.append(sessionID)
    }

    func recordShutdown() {
        shutdowns += 1
    }
}
