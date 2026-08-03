import AgentCLIKit
import Foundation
import SwiftData
import XCTest

@testable import Alveary

@MainActor
extension ThreadHostToolServiceTests {
    func testCreateThreadAppliesImmediatelyWithInheritedDefaults() async throws {
        let fixture = try ThreadHostToolFixture()

        let result = await fixture.create(arguments: ["project_path": .string(fixture.project.path)])

        XCTAssertFalse(result.isError)
        let content = try object(result.structuredContent)
        XCTAssertEqual(content["status"], .string("created"))
        XCTAssertEqual(content["project_path"], .string("/tmp/source-project"))
        XCTAssertEqual(content["name"], .string("New thread"))
        XCTAssertEqual(content["provider"], .string("claude"))
        XCTAssertEqual(content["model"], .string("default"))
        XCTAssertEqual(content["is_pinned"], .bool(false))
        XCTAssertEqual(content["initial_prompt_dispatched"], .bool(false))

        let created = try fixture.createdThread(in: result)
        XCTAssertFalse(created.isDraft)
        XCTAssertFalse(created.hasCustomName)
        XCTAssertEqual(created.project?.path, "/tmp/source-project")
        XCTAssertTrue(fixture.startedPrompts.prompts.isEmpty)
    }

    func testCreateThreadAppliesEverySupportedSetting() async throws {
        let fixture = try ThreadHostToolFixture()

        let result = await fixture.create(arguments: [
            "project_path": .string(fixture.project.path),
            "name": .string("Release checklist"),
            "provider": .string("codex"),
            "permission_mode": .string("never"),
            "effort": .string("low"),
            "pinned": .bool(true)
        ])

        let content = try object(result.structuredContent)
        XCTAssertEqual(content["name"], .string("Release checklist"))
        XCTAssertEqual(content["provider"], .string("codex"))
        XCTAssertEqual(content["permission_mode"], .string("never"))
        XCTAssertEqual(content["effort"], .string("low"))
        XCTAssertEqual(content["is_pinned"], .bool(true))

        let created = try fixture.createdThread(in: result)
        XCTAssertTrue(created.hasCustomName)
        XCTAssertTrue(created.isPinned)
        XCTAssertEqual(created.soleMainConversation?.provider, "codex")
    }

    /// A pinned project absorbs its children, so the promised pin would silently do nothing.
    func testCreateThreadSkipsThePinInsideAPinnedProject() async throws {
        let fixture = try ThreadHostToolFixture()
        fixture.project.isPinned = true
        try fixture.modelContext.save()

        let result = await fixture.create(arguments: [
            "project_path": .string(fixture.project.path),
            "pinned": .bool(true)
        ])

        XCTAssertEqual(try object(result.structuredContent)["is_pinned"], .bool(false))
        XCTAssertFalse(try fixture.createdThread(in: result).isPinned)
    }

    func testCreateThreadDispatchesItsInitialPromptWithoutWaiting() async throws {
        let fixture = try ThreadHostToolFixture()

        let result = await fixture.create(arguments: [
            "project_path": .string(fixture.project.path),
            "initial_prompt": .string("Audit the release notes.")
        ])

        let content = try object(result.structuredContent)
        XCTAssertEqual(content["initial_prompt_dispatched"], .bool(true))
        XCTAssertEqual(fixture.startedPrompts.prompts, ["Audit the release notes."])
        XCTAssertEqual(
            fixture.startedPrompts.dispatched.first?.conversationID,
            try fixture.threadID(in: result)
        )
        XCTAssertTrue(result.text.contains("running in the background"), result.text)
    }

    func testCreateThreadRejectsAnUnregisteredProject() async throws {
        let fixture = try ThreadHostToolFixture()

        let result = await fixture.create(arguments: ["project_path": .string("/tmp/not-a-project")])

        XCTAssertTrue(result.isError)
        XCTAssertEqual(
            result.text,
            ThreadHostToolServiceError.projectNotRegistered(path: "/tmp/not-a-project").localizedDescription
        )
        XCTAssertEqual(try fixture.threadCount(), 1)
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

    func testCreateThreadRejectsUnknownArgumentsAndBadTypes() async throws {
        let fixture = try ThreadHostToolFixture()

        let unknownKey = await fixture.create(arguments: [
            "project_path": .string(fixture.project.path),
            "workspace": .string("private")
        ])
        XCTAssertTrue(unknownKey.isError)
        XCTAssertTrue(unknownKey.text.contains("unsupported field(s): workspace"), unknownKey.text)

        let badType = await fixture.create(arguments: [
            "project_path": .string(fixture.project.path),
            "pinned": .string("yes")
        ])
        XCTAssertTrue(badType.isError)
        XCTAssertTrue(badType.text.contains("arguments.pinned must be a boolean."), badType.text)
    }

    /// Creating a thread beside the one you are in is the common case, so a request that names no
    /// placement lands in the caller's own Project.
    func testCreateThreadInheritsTheCallersProject() async throws {
        let fixture = try ThreadHostToolFixture()

        let result = await fixture.create(arguments: ["name": .string("Beside me")])

        XCTAssertFalse(result.isError, result.text)
        let content = try object(result.structuredContent)
        XCTAssertEqual(content["workspace_kind"], .string("project"))
        XCTAssertEqual(content["project_path"], .string(fixture.project.path))
        XCTAssertEqual(try fixture.createdThread(in: result).project?.path, fixture.project.path)
    }

    func testCreateThreadInheritsATaskCallersPrivateWorkspace() async throws {
        let fixture = try ThreadHostToolFixture()
        try fixture.makeSourceThreadATask()
        let granted = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: granted) }

        let result = await fixture.create(arguments: [
            "granted_roots": .array([.string(granted.path)])
        ])

        XCTAssertFalse(result.isError, result.text)
        let content = try object(result.structuredContent)
        XCTAssertEqual(content["workspace_kind"], .string("task"))
        XCTAssertNil(content["project_path"])

        let created = try fixture.createdThread(in: result)
        XCTAssertEqual(created.effectiveMode, .task)
        XCTAssertNil(created.project)
        XCTAssertEqual(
            created.taskWorkspaceDescriptor?.grantedRoots,
            [CanonicalPath.normalize(granted.path)]
        )
    }

    /// A project-mode caller whose Project is gone has no placement to inherit, so the request has
    /// to name one instead of guessing.
    func testCreateThreadRequiresAPlacementWhenTheCallersCannotBeInherited() async throws {
        let fixture = try ThreadHostToolFixture()
        try fixture.insertThread(name: "Detached", conversationID: "detached-main", mode: .project)

        let result = await fixture.service.handle(
            context: fixture.agentContext(conversationID: "detached-main"),
            call: AgentCLIKit.AgentHostToolCall(name: ThreadHostToolCatalog.createThreadToolName)
        )

        XCTAssertTrue(result.isError)
        XCTAssertEqual(result.text, ThreadHostToolServiceError.sourcePlacementUnavailable.localizedDescription)
        XCTAssertEqual(try fixture.threadCount(), 2)
    }

    /// A Project thread already works inside its Project, so grants that came along with an
    /// inherited placement are refused rather than dropped.
    func testCreateThreadRefusesGrantsWhenItInheritsAProject() async throws {
        let fixture = try ThreadHostToolFixture()
        let granted = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: granted) }

        let result = await fixture.create(arguments: [
            "granted_roots": .array([.string(granted.path)])
        ])

        XCTAssertTrue(result.isError)
        XCTAssertEqual(result.text, ThreadHostToolServiceError.grantsRequireTaskThread.localizedDescription)
        XCTAssertEqual(try fixture.threadCount(), 1)
    }

    func testCreateThreadMakesAProjectlessTaskThread() async throws {
        let fixture = try ThreadHostToolFixture()

        let result = await fixture.create(arguments: [
            "mode": .string("task"),
            "name": .string("Scratch"),
            "pinned": .bool(true)
        ])

        XCTAssertFalse(result.isError, result.text)
        let content = try object(result.structuredContent)
        XCTAssertEqual(content["workspace_kind"], .string("task"))
        XCTAssertEqual(content["granted_roots"], .array([]))
        XCTAssertNil(content["project_path"])
        XCTAssertTrue(result.text.contains("in its own private workspace"), result.text)

        let created = try fixture.createdThread(in: result)
        XCTAssertEqual(created.effectiveMode, .task)
        XCTAssertNil(created.project)
        XCTAssertTrue(created.isPinned)
        let workspace = try XCTUnwrap(created.taskWorkspaceDescriptor)
        XCTAssertEqual(workspace.ownershipStrategy, .privateOwned)
        XCTAssertTrue(workspace.grantedRoots.isEmpty)
    }

    /// Grants are stored canonically resolved, so a symlink spelling cannot show the user one
    /// folder while granting another.
    func testCreateThreadGrantsFoldersToATaskThreadCanonically() async throws {
        let fixture = try ThreadHostToolFixture()
        let folder = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let link = FileManager.default.temporaryDirectory
            .appendingPathComponent("alveary-grant-link-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: folder)
        defer { try? FileManager.default.removeItem(at: link) }
        let canonical = CanonicalPath.normalize(folder.path)

        let result = await fixture.create(arguments: [
            "mode": .string("task"),
            "granted_roots": .array([.string(link.path)])
        ])

        XCTAssertFalse(result.isError, result.text)
        XCTAssertEqual(
            try object(result.structuredContent)["granted_roots"],
            .array([.string(canonical)])
        )
        XCTAssertEqual(try fixture.createdThread(in: result).taskWorkspaceDescriptor?.grantedRoots, [canonical])
        XCTAssertTrue(result.text.contains(canonical), result.text)
    }

    /// Two spellings of one folder are one grant; the parser only sees literal duplicates.
    func testCreateThreadCollapsesGrantsThatResolveToTheSameFolder() async throws {
        let fixture = try ThreadHostToolFixture()
        let folder = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let canonical = CanonicalPath.normalize(folder.path)

        let result = await fixture.create(arguments: [
            "mode": .string("task"),
            "granted_roots": .array([
                .string(folder.path),
                .string(folder.appendingPathComponent("..", isDirectory: true).path + "/" + folder.lastPathComponent)
            ])
        ])

        XCTAssertFalse(result.isError, result.text)
        XCTAssertEqual(try fixture.createdThread(in: result).taskWorkspaceDescriptor?.grantedRoots, [canonical])
    }

    func testCreateThreadRejectsGrantsThatAreNotExistingAbsoluteFolders() async throws {
        let fixture = try ThreadHostToolFixture()
        let folder = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("notes.txt", isDirectory: false)
        try Data().write(to: file)

        for path in ["relative/folder", folder.appendingPathComponent("missing").path, file.path] {
            let result = await fixture.create(arguments: [
                "mode": .string("task"),
                "granted_roots": .array([.string(path)])
            ])

            XCTAssertTrue(result.isError, path)
            XCTAssertEqual(
                result.text,
                ThreadHostToolServiceError.grantedRootUnavailable(path: path).localizedDescription,
                path
            )
        }
        XCTAssertEqual(try fixture.threadCount(), 1)
    }

    func testCreateThreadRequiresARequestIdentity() async throws {
        let fixture = try ThreadHostToolFixture()

        let result = await fixture.service.handle(
            context: fixture.agentContext(requestID: nil),
            call: AgentCLIKit.AgentHostToolCall(
                name: ThreadHostToolCatalog.createThreadToolName,
                arguments: ["project_path": .string(fixture.project.path)]
            )
        )

        XCTAssertTrue(result.isError)
        XCTAssertEqual(result.text, ThreadHostToolServiceError.missingRequestIdentity.localizedDescription)
        XCTAssertEqual(try fixture.threadCount(), 1)
    }

    /// The receipt ledger is what stops a replayed call from making a second thread — and, just as
    /// visibly, from starting its initial prompt twice.
    func testAnExactRetryReplaysItsReceiptWithoutCreatingOrDispatchingAgain() async throws {
        let fixture = try ThreadHostToolFixture()
        let arguments: [String: AgentCLIKit.JSONValue] = [
            "project_path": .string(fixture.project.path),
            "name": .string("Release checklist"),
            "initial_prompt": .string("Audit the release notes.")
        ]

        let first = await fixture.create(arguments: arguments)
        let retry = await fixture.create(arguments: arguments)

        XCTAssertEqual(try object(retry.structuredContent)["status"], .string("created"))
        XCTAssertEqual(try fixture.threadID(in: retry), try fixture.threadID(in: first))
        XCTAssertEqual(retry.text, first.text)
        XCTAssertEqual(try fixture.threadCount(), 2)
        XCTAssertEqual(fixture.startedPrompts.prompts, ["Audit the release notes."])
    }

    func testADifferentRequestCreatesASecondThread() async throws {
        let fixture = try ThreadHostToolFixture()

        let first = await fixture.create(arguments: ["project_path": .string(fixture.project.path)])
        // Same request ID, different payload: a genuinely new call, not a retry.
        let second = await fixture.create(arguments: [
            "project_path": .string(fixture.project.path),
            "name": .string("Second")
        ])

        XCTAssertNotEqual(try fixture.threadID(in: second), try fixture.threadID(in: first))
        XCTAssertEqual(try fixture.threadCount(), 3)
    }

    func testCreateThreadRollsBackWhenPersistenceFails() async throws {
        let fixture = try ThreadHostToolFixture(
            saveThreadCreation: { _ in throw ThreadLifecycleTestError.saveFailed }
        )

        let result = await fixture.create(arguments: ["project_path": .string(fixture.project.path)])

        XCTAssertTrue(result.isError)
        XCTAssertEqual(try fixture.threadCount(), 1)
    }
}

extension ThreadHostToolServiceTests {
    /// Grant validation reads the file system, so these tests need real folders rather than the
    /// in-memory fixture's paths.
    func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("alveary-thread-grants-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
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

extension ThreadHostToolFixture {
    func create(arguments: [String: AgentCLIKit.JSONValue]) async -> AgentCLIKit.AgentHostToolResult {
        await service.handle(
            context: agentContext(),
            call: AgentCLIKit.AgentHostToolCall(
                name: ThreadHostToolCatalog.createThreadToolName,
                arguments: arguments
            )
        )
    }

    func threadID(in result: AgentCLIKit.AgentHostToolResult) throws -> String {
        guard case .object(let content)? = result.structuredContent,
              case .string(let threadID)? = content["thread_id"] else {
            throw ThreadHostToolFixtureError.unexpectedShape
        }
        return threadID
    }

    func createdThread(in result: AgentCLIKit.AgentHostToolResult) throws -> AgentThread {
        guard let conversation = modelContext.resolveConversation(conversationID: try threadID(in: result)),
              let thread = conversation.thread else {
            throw ThreadHostToolFixtureError.unexpectedShape
        }
        return thread
    }

    func threadCount() throws -> Int {
        try modelContext.fetch(FetchDescriptor<AgentThread>()).count
    }
}
