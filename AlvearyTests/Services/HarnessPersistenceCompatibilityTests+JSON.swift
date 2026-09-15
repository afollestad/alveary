import Foundation
import XCTest

@testable import Alveary

/// Keep legacy JSON keys literal: renaming both the fixture and implementation would hide a storage break.
@MainActor
extension HarnessPersistenceCompatibilityTests {
    func testLegacySettingsKeepHarnessSelectionsAndHistoricalKeys() throws {
        let data = Data(#"""
        {
            "defaultProvider": "codex",
            "disabledProviderIDs": ["claude"],
            "providerConfigs": {"codex": {"extraArgs": "--verbose"}},
            "pullRequestReviewProvider": "claude",
            "pullRequestAddressFeedbackProvider": "codex",
            "pullRequestAgentSettingsVersion": 1,
            "pullRequestReviewPeers": [{"id":"peer", "providerID":"claude", "model":"opus", "effort":"high"}]
        }
        """#.utf8)
        let settings = try JSONDecoder().decode(AppSettings.self, from: data)
        XCTAssertEqual(settings.defaultHarness, "codex")
        XCTAssertEqual(settings.disabledHarnessIDs, ["claude"])
        XCTAssertEqual(settings.harnessConfigs["codex"]?.extraArgs, "--verbose")
        XCTAssertEqual(settings.pullRequestReviewHarness, "claude")
        XCTAssertEqual(settings.pullRequestAddressFeedbackHarness, "codex")
        XCTAssertEqual(settings.pullRequestReviewPeers.first?.harnessID, "claude")

        let encoded = try encodedObject(settings)
        XCTAssertEqual(encoded["defaultProvider"] as? String, "codex")
        XCTAssertEqual(encoded["disabledProviderIDs"] as? [String], ["claude"])
        XCTAssertNotNil(encoded["providerConfigs"])
        XCTAssertEqual(encoded["pullRequestReviewProvider"] as? String, "claude")
        XCTAssertEqual(encoded["pullRequestAddressFeedbackProvider"] as? String, "codex")
        let peers = try XCTUnwrap(encoded["pullRequestReviewPeers"] as? [[String: Any]])
        XCTAssertEqual(peers.first?["providerID"] as? String, "claude")
        XCTAssertFalse(encoded.keys.contains { $0.localizedCaseInsensitiveContains("harness") })
    }

    func testLegacySessionMapRetainsNativeAndLaunchSessionIdentity() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("session-map.json")
        try Data(#"""
        {"conversation": {
            "cwd":"/tmp/saved-workspace", "providerId":"codex",
            "appSessionId":"native-session", "launchSessionId":"launch-session"
        }}
        """#.utf8).write(to: url)
        let manager = DefaultSessionManager(supportDirectory: directory)
        let native = await manager.conversationId(forSessionId: "native-session", cwd: "/tmp/saved-workspace", harnessId: "codex")
        let launch = await manager.conversationId(forSessionId: "launch-session", cwd: "/tmp/saved-workspace", harnessId: "codex")
        let otherHarness = await manager.conversationId(forSessionId: "native-session", cwd: "/tmp/saved-workspace", harnessId: "claude")
        XCTAssertEqual(native, "conversation")
        XCTAssertEqual(launch, "conversation")
        XCTAssertNil(otherHarness)
        try await manager.persist()

        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: [String: Any]])
        XCTAssertEqual(object["conversation"]?["providerId"] as? String, "codex")
        XCTAssertEqual(object["conversation"]?["appSessionId"] as? String, "native-session")
        XCTAssertEqual(object["conversation"]?["launchSessionId"] as? String, "launch-session")
    }

    func testLegacyReviewProvenanceKeepsWorkerAndProposalIdentities() throws {
        let workerData = Data(#"""
        {"id":"worker", "providerID":"codex", "modelOptionID":"saved-model", "launchModel":"saved-model",
         "effort":"high", "executablePath":"/saved/codex"}
        """#.utf8)
        let worker = try JSONDecoder().decode(ReviewWorkerConfiguration.self, from: workerData)
        XCTAssertEqual(worker.harnessID, "codex")
        XCTAssertEqual(try encodedObject(worker)["providerID"] as? String, "codex")

        let proposalData = Data(#"""
        {"payloadVersion":4, "id":"proposal", "deduplicationKey":"dedupe", "repositoryNameWithOwner":"owner/repo",
         "number":42, "event":"comment", "titleSnapshot":"Saved review", "pendingCommentCountSnapshot":0,
         "sourceProviderID":"claude", "createdAt":100,
         "reviewers":[{"id":"worker", "providerID":"codex", "modelOptionID":"saved-model"}]}
        """#.utf8)
        let proposal = try JSONDecoder().decode(PullRequestReviewProposalRecord.self, from: proposalData)
        XCTAssertEqual(proposal.sourceHarnessID, "claude")
        XCTAssertEqual(proposal.reviewers?.first?.harnessID, "codex")
        let encoded = try encodedObject(proposal)
        XCTAssertEqual(encoded["sourceProviderID"] as? String, "claude")
        let reviewers = try XCTUnwrap(encoded["reviewers"] as? [[String: Any]])
        XCTAssertEqual(reviewers.first?["providerID"] as? String, "codex")
    }

    func testLegacyScheduleDraftRetainsHarnessSelectionAndKey() throws {
        let data = Data(#"""
        {"title":"Saved schedule", "prompt":"Run checks", "destination":"newThread",
         "recurrence":{"daily":{"hour":9,"minute":0}}, "timeZoneIdentifier":"UTC", "providerID":"codex",
         "effort":"high", "permissionMode":"never", "workspaceKind":"privateWorkspace",
         "workspaceStrategy":"worktree", "grantedRoots":[]}
        """#.utf8)
        let draft = try JSONDecoder().decode(ScheduledTaskProposalDefinitionDraft.self, from: data)
        XCTAssertEqual(draft.harnessID, "codex")
        XCTAssertEqual(draft.recurrence, .daily(hour: 9, minute: 0))
        XCTAssertEqual(try encodedObject(draft)["providerID"] as? String, "codex")
    }

    private func encodedObject(_ value: some Encodable) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as? [String: Any])
    }
}
