import AgentCLIKit
import SwiftData
import XCTest

@testable import Alveary

@MainActor
extension PullRequestAgenticThreadServiceTests {
    func testOpenCodeFeedbackUsesKnownCheckoutCatalogInsteadOfGlobalSetup() async throws {
        let path = "/tmp/opencode-project-only-feedback"
        let discovery = ProjectOnlyOpenCodeDiscoveryStub()
        let start = try makeStartFixture(existingDirectories: [path], harnessDiscovery: discovery)
        start.fixture.context.insert(Project(path: path, name: "alpha", githubRepository: start.identifier.nameWithOwner))
        try start.fixture.context.save()
        start.fixture.settingsService.update {
            $0.pullRequestAddressFeedbackAgent = PullRequestAgentSettings(
                harness: "opencode", model: "project/model", effort: AppSettings.openCodeDefaultEffort
            )
        }

        let launch = try await start.service.start(kind: .addressFeedback, identifier: start.identifier, url: start.url)
        _ = try await launch.dispatch.value

        let thread = start.fixture.context.resolveConversation(conversationID: launch.conversationID)?.thread
        XCTAssertEqual(thread?.model, "project/model")
        XCTAssertEqual(thread?.soleMainConversation?.harness, "opencode")
        let paths = await discovery.paths
        XCTAssertEqual(paths, [path])
    }

    func testUnavailableOpenCodeReviewChoiceNeverFallsBackToReadyClaude() async throws {
        for pinned in [false, true] {
            let start = try openCodeReviewFixture(ready: false)
            start.fixture.settingsService.update { settings in
                if pinned {
                    settings.pullRequestReviewHarness = "opencode"
                } else {
                    settings.defaultHarness = "opencode"
                }
            }
            try await assertOpenCodeReviewRejectedBeforeInsertion(start)
        }
    }

    func testUnavailableOpenCodeReviewModelIsRejectedInsteadOfReplaced() async throws {
        for pinned in [false, true] {
            let start = try openCodeReviewFixture()
            start.fixture.settingsService.update { settings in
                settings.defaultHarness = "opencode"
                settings.defaultModel = pinned ? "provider/model" : "provider/removed"
                settings.effort = AppSettings.openCodeDefaultEffort
                if pinned { settings.pullRequestReviewModel = "provider/removed" }
            }
            try await assertOpenCodeReviewRejectedBeforeInsertion(start, errorContains: "selected OpenCode model is unavailable")
        }
    }

    func testUnavailableOpenCodeReviewVariantIsRejectedInsteadOfNormalized() async throws {
        for pinned in [false, true] {
            let start = try openCodeReviewFixture()
            start.fixture.settingsService.update { settings in
                settings.defaultHarness = "opencode"
                settings.defaultModel = "provider/model"
                settings.effort = pinned ? AppSettings.openCodeDefaultEffort : "removed-variant"
                if pinned { settings.pullRequestReviewEffort = "removed-variant" }
            }
            try await assertOpenCodeReviewRejectedBeforeInsertion(start, errorContains: "removed-variant")
        }
    }

    func testSupportedOpenCodeReviewKeepsConfiguredDefaultAndEscapedVariantSelections() async throws {
        for effort in [AppSettings.openCodeDefaultEffort, AppSettings.openCodeStoredEffort(nativeVariant: "alveary.opencode.variant:custom")] {
            let start = try openCodeReviewFixture()
            start.fixture.settingsService.update { settings in
                settings.pullRequestReviewAgent = PullRequestAgentSettings(
                    harness: "opencode", model: "provider/model", effort: effort, permissionMode: "ask"
                )
            }
            let launch = try await start.service.start(kind: .review, identifier: start.identifier, url: start.url)
            _ = try await launch.dispatch.value
            let conversation = try XCTUnwrap(start.fixture.context.resolveConversation(conversationID: launch.conversationID))
            XCTAssertEqual(conversation.harness, "opencode")
            XCTAssertEqual(conversation.thread?.model, "provider/model")
            XCTAssertEqual(conversation.thread?.effort, effort)
            XCTAssertEqual(start.prompts.prompts.count, 1)
        }
    }

    private func openCodeReviewFixture(ready: Bool = true) throws -> StartFixture {
        let model = AgentModelOption(
            harnessId: .opencode, id: "provider/model", model: "provider/model", label: "Native model",
            supportedEffortOptions: [AgentHarnessOption(value: "alveary.opencode.variant:custom", label: "Custom", description: "Native variant")]
        )
        return try makeStartFixture(harnessDiscovery: RecordingHarnessDiscoveryService(statuses: [
            .claude: SettingsViewModelTests.harnessStatus(for: .claude, modelOptions: AgentModelOptionTestFixtures.claudeModelOptions),
            .opencode: AgentHarnessStatus(
                harnessId: .opencode, definition: OpenCodeHarnessDefinition.definition,
                installation: .installed, setup: ready ? .ready : .failed, modelOptions: ready ? [model] : []
            )
        ]))
    }

    private func assertOpenCodeReviewRejectedBeforeInsertion(_ start: StartFixture, errorContains: String? = nil) async throws {
        do {
            _ = try await start.service.start(kind: .review, identifier: start.identifier, url: start.url)
            XCTFail("Unavailable OpenCode selections must refuse launch")
        } catch {
            XCTAssertFalse(error.localizedDescription.isEmpty)
            if let errorContains { XCTAssertTrue(error.localizedDescription.contains(errorContains), error.localizedDescription) }
        }
        XCTAssertEqual(try start.fixture.context.fetchCount(FetchDescriptor<AgentThread>()), 0)
        XCTAssertTrue(start.prompts.prompts.isEmpty)
        XCTAssertEqual(start.pullRequests.detailCallCount, 0)
    }
}

/// Global credentials are deliberately absent; only a known working directory can supply this provider.
actor ProjectOnlyOpenCodeDiscoveryStub: AgentHarnessDiscoveryService {
    private(set) var paths: [String?] = []

    func harnessStatuses(projectURL: URL?) async -> [AgentHarnessID: AgentHarnessStatus] {
        paths.append(projectURL?.path)
        let ready = projectURL != nil
        return [.opencode: AgentHarnessStatus(
            harnessId: .opencode, definition: OpenCodeHarnessDefinition.definition,
            installation: .installed, setup: ready ? .ready : .needsSetup,
            modelOptions: ready ? [AgentModelOption(harnessId: .opencode, id: "project/model", model: "project/model", label: "Project")] : []
        )]
    }

    func installedHarnessStatuses(projectURL: URL?) async -> [AgentHarnessID: AgentHarnessStatus] {
        await harnessStatuses(projectURL: projectURL)
    }

    func availableHarnessStatuses(projectURL: URL?) async -> [AgentHarnessID: AgentHarnessStatus] {
        await harnessStatuses(projectURL: projectURL)
    }

    func modelOptions(for harnessId: AgentHarnessID) async -> [AgentModelOption] { [] }
    func stableHarnessOrdering() async -> [AgentHarnessID] { [.claude, .codex, .opencode] }
}
