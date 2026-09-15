import AgentCLIKit
import Foundation

@testable import Alveary

struct HarnessActionDefaultAdapter: AgentCLIKit.AgentHarnessAdapter {
    let harnessId: AgentCLIKit.AgentHarnessID
    let state: HarnessActionAdapterState

    var definition: AgentCLIKit.AgentHarnessDefinition {
        AgentCLIKit.AgentHarnessDefinition(id: harnessId, displayName: "Harness", executableNames: ["provider"])
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

    func shutdownHarnessResources() async {
        await state.recordShutdown()
    }
}

struct HarnessActionRecordingAdapter: AgentCLIKit.AgentHarnessAdapter {
    let harnessId: AgentCLIKit.AgentHarnessID
    let state: HarnessActionAdapterState

    var definition: AgentCLIKit.AgentHarnessDefinition {
        AgentCLIKit.AgentHarnessDefinition(id: harnessId, displayName: "Harness", executableNames: ["provider"])
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
        try await state.recordArchive(record.harnessSessionId)
    }

    func unarchiveSession(_ record: AgentCLIKit.AgentSessionRecord) async throws {
        await state.recordUnarchive(record.harnessSessionId)
    }

    func deleteSession(_ record: AgentCLIKit.AgentSessionRecord) async throws {
        try await state.recordDelete(record.harnessSessionId)
    }

    func shutdownHarnessResources() async {
        await state.recordShutdown()
    }
}

actor HarnessActionAdapterState {
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
