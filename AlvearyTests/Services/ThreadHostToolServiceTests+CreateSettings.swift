import AgentCLIKit
import Foundation
import SwiftData
import XCTest

@testable import Alveary

/// How `create_thread` settles provider, model, and effort: omitted settings inherit the caller's
/// thread, requested ones validate against live host state.
@MainActor
extension ThreadHostToolServiceTests {
    /// Omitted settings inherit the caller's own thread — codex with "source-model" at high effort
    /// in this fixture — not the user's defaults, whose provider here is claude.
    func testCreateThreadAppliesImmediatelyWithTheCallersInheritedSettings() async throws {
        let fixture = try ThreadHostToolFixture()

        let result = await fixture.create(arguments: ["project_path": .string(fixture.project.path)])

        XCTAssertFalse(result.isError)
        let content = try object(result.structuredContent)
        XCTAssertEqual(content["status"], .string("created"))
        XCTAssertEqual(content["project_path"], .string("/tmp/source-project"))
        XCTAssertEqual(content["name"], .string("New thread"))
        XCTAssertEqual(content["provider"], .string("codex"))
        XCTAssertEqual(content["model"], .string("source-model"))
        XCTAssertEqual(content["effort"], .string("high"))
        XCTAssertEqual(content["is_pinned"], .bool(false))
        XCTAssertEqual(content["initial_prompt_dispatched"], .bool(false))

        let created = try fixture.createdThread(in: result)
        XCTAssertFalse(created.isDraft)
        XCTAssertFalse(created.hasCustomName)
        XCTAssertEqual(created.project?.path, "/tmp/source-project")
        XCTAssertEqual(created.model, "source-model")
        XCTAssertEqual(created.effort, "high")
        XCTAssertEqual(created.soleMainConversation?.provider, "codex")
        XCTAssertTrue(fixture.startedPrompts.prompts.isEmpty)
    }

    /// The caller's model belongs to its provider, so naming a different provider falls back to
    /// the user's defaults rather than dragging a foreign model string along. An unset default
    /// resolves against the static Claude catalog, so it materializes as the catalog's default
    /// model — the same value discovery-backed resolution produces.
    func testCreateThreadDoesNotInheritSettingsAcrossAnExplicitProviderChange() async throws {
        let fixture = try ThreadHostToolFixture()

        let result = await fixture.create(arguments: [
            "project_path": .string(fixture.project.path),
            "provider": .string("claude")
        ])

        XCTAssertFalse(result.isError, result.text)
        let content = try object(result.structuredContent)
        XCTAssertEqual(content["provider"], .string("claude"))
        XCTAssertEqual(content["model"], .string("claude-sonnet-5"))
    }

    /// A caller running its provider's default model passes that on as-is: the created thread
    /// stays on "default" rather than resolving to the settings model.
    func testCreateThreadInheritsACallersProviderDefaultModelAsDefault() async throws {
        let fixture = try ThreadHostToolFixture()
        fixture.thread.model = nil
        try fixture.modelContext.save()

        let result = await fixture.create(arguments: ["project_path": .string(fixture.project.path)])

        XCTAssertFalse(result.isError, result.text)
        let content = try object(result.structuredContent)
        XCTAssertEqual(content["provider"], .string("codex"))
        XCTAssertEqual(content["model"], .string("default"))
        XCTAssertNil(try fixture.createdThread(in: result).model)
    }

    /// A caller whose provider discovery no longer reports ready cannot be inherited, so an
    /// omitted provider degrades to the user's default instead of refusing.
    func testCreateThreadFallsBackToTheDefaultProviderWhenTheCallersIsNotReady() async throws {
        let fixture = try ThreadHostToolFixture(providerDiscovery: ClaudeOnlyProviderDiscoveryStub())

        let result = await fixture.create(arguments: ["project_path": .string(fixture.project.path)])

        XCTAssertFalse(result.isError, result.text)
        let content = try object(result.structuredContent)
        XCTAssertEqual(content["provider"], .string("claude"))
        // The codex caller's model cannot ride along with the fallback provider.
        XCTAssertNotEqual(content["model"], .string("source-model"))
    }

    /// Each rejection names what would have worked, so the model can correct itself.
    func testCreateThreadRejectsUnavailableSettingsAndNamesTheValidOnes() async throws {
        let fixture = try ThreadHostToolFixture()

        let unknownProvider = await fixture.create(arguments: [
            "project_path": .string(fixture.project.path),
            "provider": .string("gemini")
        ])
        XCTAssertTrue(unknownProvider.isError)
        XCTAssertTrue(unknownProvider.text.contains("claude, codex"), unknownProvider.text)

        let unknownModel = await fixture.create(arguments: [
            "project_path": .string(fixture.project.path),
            "model": .string("imaginary-model")
        ])
        XCTAssertTrue(unknownModel.isError)
        XCTAssertTrue(unknownModel.text.contains("imaginary-model"), unknownModel.text)

        // A Codex permission mode is not a Claude one.
        let wrongPermissionMode = await fixture.create(arguments: [
            "project_path": .string(fixture.project.path),
            "provider": .string("claude"),
            "permission_mode": .string("on-request")
        ])
        XCTAssertTrue(wrongPermissionMode.isError)
        XCTAssertTrue(wrongPermissionMode.text.contains("default, acceptEdits"), wrongPermissionMode.text)

        XCTAssertEqual(try fixture.threadCount(), 1)
    }

    /// The defaults resolution only carries the default provider's model options, so a request
    /// naming a different ready provider has to validate against that provider's own list — a
    /// valid model on the non-default provider must not be falsely rejected.
    func testCreateThreadValidatesModelsAgainstTheRequestedProvidersOwnOptions() async throws {
        let fixture = try ThreadHostToolFixture(providerDiscovery: CreateThreadProviderDiscoveryStub())

        // Default provider resolves to claude; gpt-5.5 is a codex model.
        let crossProvider = await fixture.create(arguments: [
            "project_path": .string(fixture.project.path),
            "provider": .string("codex"),
            "model": .string("gpt-5.5"),
            "effort": .string("xhigh")
        ])

        XCTAssertFalse(crossProvider.isError, crossProvider.text)
        let content = try object(crossProvider.structuredContent)
        XCTAssertEqual(content["provider"], .string("codex"))
        XCTAssertEqual(content["model"], .string("gpt-5.5"))
        XCTAssertEqual(content["effort"], .string("xhigh"))

        // A claude model on codex still rejects.
        let wrongProvider = await fixture.create(arguments: [
            "project_path": .string(fixture.project.path),
            "provider": .string("codex"),
            "model": .string("sonnet")
        ])
        XCTAssertTrue(wrongProvider.isError)

        // An effort the requested model does not support rejects and names the supported set.
        let wrongEffort = await fixture.create(arguments: [
            "project_path": .string(fixture.project.path),
            "provider": .string("codex"),
            "model": .string("gpt-5.4-mini"),
            "effort": .string("xhigh")
        ])
        XCTAssertTrue(wrongEffort.isError)
        XCTAssertTrue(wrongEffort.text.contains("low, medium"), wrongEffort.text)
    }
}

/// Both providers installed and ready, with distinct model lists, so cross-provider validation
/// has a real second list to check against.
private actor CreateThreadProviderDiscoveryStub: AgentCLIKit.AgentProviderDiscoveryService {
    private let statuses: [AgentCLIKit.AgentProviderID: AgentCLIKit.AgentProviderStatus] = [
        .claude: AgentCLIKit.AgentProviderStatus(
            providerId: .claude,
            installation: .installed,
            setup: .ready,
            modelOptions: AgentModelOptionTestFixtures.claudeModelOptions
        ),
        .codex: AgentCLIKit.AgentProviderStatus(
            providerId: .codex,
            installation: .installed,
            setup: .ready,
            modelOptions: AgentModelOptionTestFixtures.codexModelOptions
        )
    ]

    func providerStatuses(projectURL: URL?) async -> [AgentCLIKit.AgentProviderID: AgentCLIKit.AgentProviderStatus] {
        statuses
    }

    func installedProviderStatuses(projectURL: URL?) async -> [AgentCLIKit.AgentProviderID: AgentCLIKit.AgentProviderStatus] {
        statuses
    }

    func availableProviderStatuses(projectURL: URL?) async -> [AgentCLIKit.AgentProviderID: AgentCLIKit.AgentProviderStatus] {
        statuses
    }

    func modelOptions(for providerId: AgentCLIKit.AgentProviderID) async -> [AgentCLIKit.AgentModelOption] {
        statuses[providerId]?.modelOptions ?? []
    }

    func stableProviderOrdering() async -> [AgentCLIKit.AgentProviderID] {
        [.claude, .codex]
    }
}

/// Only claude reports ready, so the fixture's codex caller has no inheritable provider.
private actor ClaudeOnlyProviderDiscoveryStub: AgentCLIKit.AgentProviderDiscoveryService {
    private let statuses: [AgentCLIKit.AgentProviderID: AgentCLIKit.AgentProviderStatus] = [
        .claude: AgentCLIKit.AgentProviderStatus(
            providerId: .claude,
            installation: .installed,
            setup: .ready,
            modelOptions: AgentModelOptionTestFixtures.claudeModelOptions
        )
    ]

    func providerStatuses(projectURL: URL?) async -> [AgentCLIKit.AgentProviderID: AgentCLIKit.AgentProviderStatus] {
        statuses
    }

    func installedProviderStatuses(projectURL: URL?) async -> [AgentCLIKit.AgentProviderID: AgentCLIKit.AgentProviderStatus] {
        statuses
    }

    func availableProviderStatuses(projectURL: URL?) async -> [AgentCLIKit.AgentProviderID: AgentCLIKit.AgentProviderStatus] {
        statuses
    }

    func modelOptions(for providerId: AgentCLIKit.AgentProviderID) async -> [AgentCLIKit.AgentModelOption] {
        statuses[providerId]?.modelOptions ?? []
    }

    func stableProviderOrdering() async -> [AgentCLIKit.AgentProviderID] {
        [.claude, .codex]
    }
}
