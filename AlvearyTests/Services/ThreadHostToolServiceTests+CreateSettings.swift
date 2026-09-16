import AgentCLIKit
import Foundation
import SwiftData
import XCTest

@testable import Alveary

/// How `create_thread` settles harness, model, and effort: omitted settings inherit the caller's
/// thread, requested ones validate against live host state.
@MainActor
extension ThreadHostToolServiceTests {
    func testCreateOpenCodeThreadUsesTargetWorkspaceCatalogBeforeInsertion() async throws {
        let discovery = ProjectOnlyOpenCodeDiscoveryStub()
        let fixture = try ThreadHostToolFixture(harnessDiscovery: discovery)
        let result = await fixture.create(arguments: [
            "project_path": .string(fixture.project.path), "harness": .string("opencode"), "model": .string("project/model")
        ])

        XCTAssertFalse(result.isError, result.text)
        let thread = try fixture.createdThread(in: result)
        XCTAssertEqual(thread.model, "project/model")
        XCTAssertEqual(thread.soleMainConversation?.harness, "opencode")
        XCTAssertEqual(thread.effort, AppSettings.openCodeDefaultEffort)
        let paths = await discovery.paths
        XCTAssertEqual(paths, [fixture.project.path])
    }

    func testExplicitOpenCodeSwitchRejectsUnavailableInheritedGlobalModel() throws {
        let fixture = try ThreadHostToolFixture()
        let defaults = ThreadSettingDefaults(
            source: .init(harness: "claude", model: nil, effort: "medium"),
            resolution: .init(
                harnessID: "opencode", storedThreadModel: "removed/model", permissionMode: "ask",
                effort: AppSettings.openCodeDefaultEffort, readyHarnessIDs: ["opencode"], modelOptions: []
            ),
            harness: "opencode", options: []
        )
        XCTAssertThrowsError(try fixture.service.validatedModel(nil, defaults: defaults)) { error in
            XCTAssertTrue(error.localizedDescription.contains("removed/model"))
        }
    }

    func testCreateThreadDoesNotSilentlyReplaceUnavailableOpenCode() async throws {
        let fixture = try ThreadHostToolFixture(harnessDiscovery: ClaudeOnlyHarnessDiscoveryStub())
        fixture.thread.soleMainConversation?.harness = "opencode"
        try fixture.modelContext.save()
        let result = await fixture.service.handle(
            context: fixture.agentContext(harnessID: .opencode),
            call: .init(
                name: ThreadHostToolCatalog.createThreadToolName,
                arguments: ["project_path": .string(fixture.project.path)]
            )
        )
        XCTAssertTrue(result.isError, result.text)
        XCTAssertTrue(result.text.contains("opencode"), result.text)
        XCTAssertEqual(try fixture.threadCount(), 1)
    }

    /// Omitted settings inherit the caller's own thread — codex with "source-model" at high effort
    /// in this fixture — not the user's defaults, whose harness here is claude.
    func testCreateThreadAppliesImmediatelyWithTheCallersInheritedSettings() async throws {
        let fixture = try ThreadHostToolFixture()

        let result = await fixture.create(arguments: ["project_path": .string(fixture.project.path)])

        XCTAssertFalse(result.isError)
        let content = try object(result.structuredContent)
        XCTAssertEqual(content["status"], .string("created"))
        XCTAssertEqual(content["project_path"], .string(fixture.project.path))
        XCTAssertEqual(content["name"], .string("New thread"))
        XCTAssertEqual(content["harness"], .string("codex"))
        XCTAssertEqual(content["model"], .string("source-model"))
        XCTAssertEqual(content["effort"], .string("high"))
        XCTAssertEqual(content["is_pinned"], .bool(false))
        XCTAssertEqual(content["initial_prompt_dispatched"], .bool(false))

        let created = try fixture.createdThread(in: result)
        XCTAssertFalse(created.isDraft)
        XCTAssertFalse(created.hasCustomName)
        XCTAssertEqual(created.project?.path, fixture.project.path)
        XCTAssertEqual(created.model, "source-model")
        XCTAssertEqual(created.effort, "high")
        XCTAssertEqual(created.soleMainConversation?.harness, "codex")
        XCTAssertTrue(fixture.startedPrompts.prompts.isEmpty)
    }

    /// The caller's model belongs to its harness, so naming a different harness falls back to
    /// the user's defaults rather than dragging a foreign model string along. An unset default
    /// resolves against the static Claude catalog, so it materializes as the catalog's default
    /// model — the same value discovery-backed resolution produces.
    func testCreateThreadDoesNotInheritSettingsAcrossAnExplicitHarnessChange() async throws {
        let fixture = try ThreadHostToolFixture()

        let result = await fixture.create(arguments: [
            "project_path": .string(fixture.project.path),
            "harness": .string("claude")
        ])

        XCTAssertFalse(result.isError, result.text)
        let content = try object(result.structuredContent)
        XCTAssertEqual(content["harness"], .string("claude"))
        XCTAssertEqual(content["model"], .string("claude-sonnet-5"))
    }

    /// A caller running its harness's default model passes that on as-is: the created thread
    /// stays on "default" rather than resolving to the settings model.
    func testCreateThreadInheritsACallersHarnessDefaultModelAsDefault() async throws {
        let fixture = try ThreadHostToolFixture()
        fixture.thread.model = nil
        try fixture.modelContext.save()

        let result = await fixture.create(arguments: ["project_path": .string(fixture.project.path)])

        XCTAssertFalse(result.isError, result.text)
        let content = try object(result.structuredContent)
        XCTAssertEqual(content["harness"], .string("codex"))
        XCTAssertEqual(content["model"], .string("default"))
        XCTAssertNil(try fixture.createdThread(in: result).model)
    }

    /// A caller whose harness discovery no longer reports ready cannot be inherited, so an
    /// omitted harness degrades to the user's default instead of refusing.
    func testCreateThreadFallsBackToTheDefaultHarnessWhenTheCallersIsNotReady() async throws {
        let fixture = try ThreadHostToolFixture(harnessDiscovery: ClaudeOnlyHarnessDiscoveryStub())

        let result = await fixture.create(arguments: ["project_path": .string(fixture.project.path)])

        XCTAssertFalse(result.isError, result.text)
        let content = try object(result.structuredContent)
        XCTAssertEqual(content["harness"], .string("claude"))
        // The codex caller's model cannot ride along with the fallback harness.
        XCTAssertNotEqual(content["model"], .string("source-model"))
    }

    /// Each rejection names what would have worked, so the model can correct itself.
    func testCreateThreadRejectsUnavailableSettingsAndNamesTheValidOnes() async throws {
        let fixture = try ThreadHostToolFixture()

        let unknownHarness = await fixture.create(arguments: [
            "project_path": .string(fixture.project.path),
            "harness": .string("gemini")
        ])
        XCTAssertTrue(unknownHarness.isError)
        XCTAssertTrue(unknownHarness.text.contains("claude, codex"), unknownHarness.text)

        let unknownModel = await fixture.create(arguments: [
            "project_path": .string(fixture.project.path),
            "model": .string("imaginary-model")
        ])
        XCTAssertTrue(unknownModel.isError)
        XCTAssertTrue(unknownModel.text.contains("imaginary-model"), unknownModel.text)

        // A Codex permission mode is not a Claude one.
        let wrongPermissionMode = await fixture.create(arguments: [
            "project_path": .string(fixture.project.path),
            "harness": .string("claude"),
            "permission_mode": .string("on-request")
        ])
        XCTAssertTrue(wrongPermissionMode.isError)
        XCTAssertTrue(wrongPermissionMode.text.contains("default, acceptEdits"), wrongPermissionMode.text)

        XCTAssertEqual(try fixture.threadCount(), 1)
    }

    /// The defaults resolution only carries the default harness's model options, so a request
    /// naming a different ready harness has to validate against that harness's own list — a
    /// valid model on the non-default harness must not be falsely rejected.
    func testCreateThreadValidatesModelsAgainstTheRequestedHarnessesOwnOptions() async throws {
        let fixture = try ThreadHostToolFixture(harnessDiscovery: CreateThreadHarnessDiscoveryStub())

        // Default harness resolves to claude; gpt-5.5 is a codex model.
        let crossHarness = await fixture.create(arguments: [
            "project_path": .string(fixture.project.path),
            "harness": .string("codex"),
            "model": .string("gpt-5.5"),
            "effort": .string("xhigh")
        ])

        XCTAssertFalse(crossHarness.isError, crossHarness.text)
        let content = try object(crossHarness.structuredContent)
        XCTAssertEqual(content["harness"], .string("codex"))
        XCTAssertEqual(content["model"], .string("gpt-5.5"))
        XCTAssertEqual(content["effort"], .string("xhigh"))

        // A claude model on codex still rejects.
        let wrongHarness = await fixture.create(arguments: [
            "project_path": .string(fixture.project.path),
            "harness": .string("codex"),
            "model": .string("sonnet")
        ])
        XCTAssertTrue(wrongHarness.isError)

        // An effort the requested model does not support rejects and names the supported set.
        let wrongEffort = await fixture.create(arguments: [
            "project_path": .string(fixture.project.path),
            "harness": .string("codex"),
            "model": .string("gpt-5.4-mini"),
            "effort": .string("xhigh")
        ])
        XCTAssertTrue(wrongEffort.isError)
        XCTAssertTrue(wrongEffort.text.contains("low, medium"), wrongEffort.text)
    }
}

/// Both harnesses installed and ready, with distinct model lists, so cross-harness validation
/// has a real second list to check against.
private actor CreateThreadHarnessDiscoveryStub: AgentCLIKit.AgentHarnessDiscoveryService {
    private let statuses: [AgentCLIKit.AgentHarnessID: AgentCLIKit.AgentHarnessStatus] = [
        .claude: AgentCLIKit.AgentHarnessStatus(
            harnessId: .claude,
            installation: .installed,
            setup: .ready,
            modelOptions: AgentModelOptionTestFixtures.claudeModelOptions
        ),
        .codex: AgentCLIKit.AgentHarnessStatus(
            harnessId: .codex,
            installation: .installed,
            setup: .ready,
            modelOptions: AgentModelOptionTestFixtures.codexModelOptions
        )
    ]

    func harnessStatuses(projectURL: URL?) async -> [AgentCLIKit.AgentHarnessID: AgentCLIKit.AgentHarnessStatus] {
        statuses
    }

    func installedHarnessStatuses(projectURL: URL?) async -> [AgentCLIKit.AgentHarnessID: AgentCLIKit.AgentHarnessStatus] {
        statuses
    }

    func availableHarnessStatuses(projectURL: URL?) async -> [AgentCLIKit.AgentHarnessID: AgentCLIKit.AgentHarnessStatus] {
        statuses
    }

    func modelOptions(for harnessId: AgentCLIKit.AgentHarnessID) async -> [AgentCLIKit.AgentModelOption] {
        statuses[harnessId]?.modelOptions ?? []
    }

    func stableHarnessOrdering() async -> [AgentCLIKit.AgentHarnessID] {
        [.claude, .codex]
    }
}

/// Only claude reports ready, so the fixture's codex caller has no inheritable harness.
private actor ClaudeOnlyHarnessDiscoveryStub: AgentCLIKit.AgentHarnessDiscoveryService {
    private let statuses: [AgentCLIKit.AgentHarnessID: AgentCLIKit.AgentHarnessStatus] = [
        .claude: AgentCLIKit.AgentHarnessStatus(
            harnessId: .claude,
            installation: .installed,
            setup: .ready,
            modelOptions: AgentModelOptionTestFixtures.claudeModelOptions
        )
    ]

    func harnessStatuses(projectURL: URL?) async -> [AgentCLIKit.AgentHarnessID: AgentCLIKit.AgentHarnessStatus] {
        statuses
    }

    func installedHarnessStatuses(projectURL: URL?) async -> [AgentCLIKit.AgentHarnessID: AgentCLIKit.AgentHarnessStatus] {
        statuses
    }

    func availableHarnessStatuses(projectURL: URL?) async -> [AgentCLIKit.AgentHarnessID: AgentCLIKit.AgentHarnessStatus] {
        statuses
    }

    func modelOptions(for harnessId: AgentCLIKit.AgentHarnessID) async -> [AgentCLIKit.AgentModelOption] {
        statuses[harnessId]?.modelOptions ?? []
    }

    func stableHarnessOrdering() async -> [AgentCLIKit.AgentHarnessID] {
        [.claude, .codex]
    }
}
