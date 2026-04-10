import Foundation
import XCTest

@testable import Skep

final class SessionManagerTests: XCTestCase {
    func testCreateEntryPreservesIdentityOnlyWhenBindingMatches() async {
        let manager = InMemorySessionManager()

        let firstCreate = await manager.createEntry(conversationId: "c1", cwd: "/tmp/project", providerId: "claude")
        let original = await manager.sessionId(for: "c1")

        let preservedCreate = await manager.createEntry(conversationId: "c1", cwd: "/tmp/project", providerId: "claude")
        let preservedSessionID = await manager.sessionId(for: "c1")

        let rotatedCreate = await manager.createEntry(conversationId: "c1", cwd: "/tmp/project-2", providerId: "claude")
        let rotated = await manager.sessionId(for: "c1")

        XCTAssertFalse(firstCreate)
        XCTAssertTrue(preservedCreate)
        XCTAssertEqual(preservedSessionID, original)
        XCTAssertFalse(rotatedCreate)
        XCTAssertNotEqual(rotated, original)
    }

    func testUpdateSessionIdKeepsLaunchLookupOnOldIdentifier() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let manager = DefaultSessionManager(supportDirectory: tempDirectory)

        let created = await manager.createEntry(conversationId: "c1", cwd: "/tmp/project", providerId: "claude")
        let original = await manager.sessionId(for: "c1")

        try await manager.updateSessionId(for: "c1", newSessionId: "forked-session")

        let sessionID = await manager.sessionId(for: "c1")
        let originalLookup = await manager.conversationId(forSessionId: original, cwd: "/tmp/project", providerId: "claude")
        let forkedLookup = await manager.conversationId(forSessionId: "forked-session", cwd: "/tmp/project", providerId: "claude")

        XCTAssertFalse(created)
        XCTAssertEqual(sessionID, "forked-session")
        XCTAssertEqual(originalLookup, "c1")
        XCTAssertEqual(forkedLookup, "c1")

        let persistedEntries = try loadPersistedEntries(from: tempDirectory)
        XCTAssertEqual(persistedEntries["c1"]?.appSessionId, "forked-session")
        XCTAssertEqual(persistedEntries["c1"]?.launchSessionId, original)
    }

    private func loadPersistedEntries(from directory: URL) throws -> [String: SessionEntry] {
        let fileURL = directory.appendingPathComponent("session-map.json")
        let data = try Data(contentsOf: fileURL)
        return try JSONDecoder().decode([String: SessionEntry].self, from: data)
    }
}
