import AgentCLIKit
import XCTest

@testable import Alveary

@MainActor
extension ScheduledTasksViewModelTests {
    func testOpenCodeScheduleUsesProjectModelsWithoutChangingSavedSelections() async throws {
        let discovery = ScheduledOpenCodeDiscoveryStub()
        let fixture = try ScheduledTasksViewModelFixture(harnessDiscovery: discovery)
        var draft = fixture.viewModel.makeNewDraft()
        draft.workspaceKind = .project
        draft.projectPath = "/tmp/project-models"
        draft.modelSelection = "project/model"
        draft.effort = "project-variant"
        let original = draft
        XCTAssertTrue(fixture.viewModel.isOpenCodeEditorCatalogPending(for: draft))
        XCTAssertFalse(fixture.viewModel.editorHarnessIDs(for: draft).contains("opencode"))

        let refresh = Task { await fixture.viewModel.refreshOpenCodeEditorCatalog(directory: draft.projectPath) }
        await discovery.waitForRequests(1)
        await discovery.finish(0, model: "project/model")
        await refresh.value

        XCTAssertTrue(fixture.viewModel.editorHarnessIDs(for: draft).contains("opencode"))
        let openCodeGroup = fixture.viewModel.agentPresentation(for: draft).modelGroups.first { $0.harnessID == "opencode" }
        XCTAssertEqual(openCodeGroup?.options.map(\.value), ["default", "project/model"])
        XCTAssertEqual(fixture.viewModel.effortOptions(
            for: "opencode", modelSelection: draft.modelSelection, draft: draft
        ).map(\.value), [AppSettings.openCodeDefaultEffort, "project-variant"])
        XCTAssertFalse(fixture.viewModel.isOpenCodeEditorCatalogPending(for: draft))
        XCTAssertEqual(draft, original)
        XCTAssertEqual(fixture.viewModel.modelOptions(for: "opencode").map(\.id), ["default"])
    }

    func testOpenCodeScheduleCatalogResponsesCannotReplaceAnotherDirectoryOrNewerRefresh() async throws {
        let discovery = ScheduledOpenCodeDiscoveryStub()
        let fixture = try ScheduledTasksViewModelFixture(harnessDiscovery: discovery)
        var firstDraft = fixture.viewModel.makeNewDraft()
        firstDraft.workspaceKind = .project
        firstDraft.projectPath = "/tmp/first"
        var secondDraft = firstDraft
        secondDraft.projectPath = "/tmp/second"
        let first = Task { await fixture.viewModel.refreshOpenCodeEditorCatalog(directory: firstDraft.projectPath) }
        await discovery.waitForRequests(1)
        let newer = Task { await fixture.viewModel.refreshOpenCodeEditorCatalog(directory: firstDraft.projectPath) }
        await discovery.waitForRequests(2)
        let second = Task { await fixture.viewModel.refreshOpenCodeEditorCatalog(directory: secondDraft.projectPath) }
        await discovery.waitForRequests(3)
        await discovery.finish(2, model: "second/model")
        await second.value
        await discovery.finish(1, model: "newer/model")
        await newer.value
        await discovery.finish(0, model: "stale/model")
        await first.value

        XCTAssertEqual(fixture.viewModel.modelOptions(for: "opencode", draft: secondDraft).last?.id, "second/model")
        XCTAssertEqual(fixture.viewModel.modelOptions(for: "opencode", draft: firstDraft).last?.id, "newer/model")
        XCTAssertEqual(fixture.viewModel.modelOptions(for: "claude", draft: secondDraft), fixture.viewModel.modelOptions(for: "claude"))
    }

    func testOpenCodeScheduleDiscoveryUsesReusedWorkspaceUntilWorkspaceChanges() throws {
        let fixture = try ScheduledTasksViewModelFixture()
        let thread = try fixture.insertReusedThreadDefinition(id: "reuse-native")
        let definition = try XCTUnwrap(fixture.fetchDefinitions().first)
        definition.harnessID = "opencode"
        definition.workspaceKind = .project
        definition.workspaceSnapshot = WorkspaceSnapshot(primarySource: SourceFolderSnapshot(path: "/tmp/source"))
        try fixture.context.save()
        var draft = try XCTUnwrap(fixture.viewModel.makeEditDraft(definitionID: definition.id))

        XCTAssertEqual(fixture.viewModel.openCodeDiscoveryDirectory(for: draft), thread.primaryWorkingDirectory)
        draft.projectPath = "/tmp/changed-source"
        draft.workspaceSnapshot = WorkspaceSnapshot(primarySource: SourceFolderSnapshot(path: "/tmp/changed-source"))
        XCTAssertEqual(fixture.viewModel.openCodeDiscoveryDirectory(for: draft), "/tmp/changed-source")
        draft.destination = .existingThread
        draft.targetConversationID = thread.soleMainConversation?.id
        XCTAssertEqual(fixture.viewModel.openCodeDiscoveryDirectory(for: draft), thread.primaryWorkingDirectory)
    }

    func testOpenCodeInheritedSchedulePreservesUnavailableEncodedVariantUntilExplicitSelection() throws {
        let nativeVariant = AppSettings.openCodeDefaultEffort
        let storedVariant = AppSettings.openCodeStoredEffort(nativeVariant: nativeVariant)
        let fixture = try ScheduledTasksViewModelFixture(configureSettings: {
            $0.defaultHarness = "opencode"
            $0.defaultModel = "provider/model"
            $0.effort = storedVariant
        })
        fixture.viewModel.harnessStatuses["opencode"] = AgentHarnessStatus(
            harnessId: .opencode, definition: OpenCodeHarnessDefinition.definition,
            modelOptions: [AgentModelOption(harnessId: .opencode, id: "provider/model", model: "provider/model", label: "Model")]
        )
        var draft = fixture.viewModel.makeNewDraft()
        XCTAssertEqual(draft.effort, storedVariant)
        draft.title = "Keep my variant"
        draft.prompt = "Perform the scheduled work."

        fixture.viewModel.normalizeHarnessDependentFields(&draft)
        XCTAssertEqual(draft.effort, storedVariant)
        let edit = try fixture.viewModel.makeDefinitionEdit(from: draft, preservesTrustedGrantSnapshot: false)
        XCTAssertEqual(edit.effort, storedVariant)
        XCTAssertEqual(AppSettings.openCodeNativeEffort(stored: edit.effort), nativeVariant)

        fixture.viewModel.normalizeHarnessDependentFields(&draft, explicitSelectionChange: true)
        XCTAssertEqual(draft.effort, AppSettings.openCodeDefaultEffort)
        XCTAssertNil(AppSettings.openCodeNativeEffort(stored: draft.effort))
    }

    func testOpenCodeScheduleUnrelatedEditDoesNotReplaceUnavailableVariant() throws {
        let fixture = try ScheduledTasksViewModelFixture()
        try fixture.insertDefinition(id: "native-variant", state: .active)
        let definition = try XCTUnwrap(fixture.fetchDefinitions().first)
        definition.harnessID = "opencode"
        definition.model = "provider/model"
        definition.effort = "removed-variant"
        try fixture.context.save()
        fixture.viewModel.harnessStatuses["opencode"] = AgentHarnessStatus(
            harnessId: .opencode, definition: OpenCodeHarnessDefinition.definition,
            modelOptions: [AgentModelOption(harnessId: .opencode, id: "provider/model", model: "provider/model", label: "Model")]
        )

        var draft = try XCTUnwrap(fixture.viewModel.makeEditDraft(definitionID: definition.id))
        draft.title = "Only the title changes"
        XCTAssertTrue(fixture.viewModel.save(draft))
        XCTAssertEqual(definition.title, "Only the title changes")
        XCTAssertEqual(definition.effort, "removed-variant")
    }

}

private actor ScheduledOpenCodeDiscoveryStub: AgentHarnessDiscoveryService {
    private var requests: [CheckedContinuation<[AgentHarnessID: AgentHarnessStatus], Never>] = []
    private var waiters: [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []

    func harnessStatuses(projectURL: URL?) async -> [AgentHarnessID: AgentHarnessStatus] {
        guard projectURL != nil else { return [:] }
        return await withCheckedContinuation { continuation in
            requests.append(continuation)
            let ready = waiters.filter { $0.count <= requests.count }
            waiters.removeAll { $0.count <= requests.count }
            for waiter in ready { waiter.continuation.resume() }
        }
    }

    func waitForRequests(_ count: Int) async {
        guard requests.count < count else { return }
        await withCheckedContinuation { waiters.append((count, $0)) }
    }

    func finish(_ index: Int, model: String) {
        let option = AgentModelOption(
            harnessId: .opencode, id: model, model: model, label: model,
            supportedEffortOptions: [AgentHarnessOption(value: "project-variant", label: "Project variant", description: "Project configuration")]
        )
        requests[index].resume(returning: [.opencode: AgentHarnessStatus(
            harnessId: .opencode, definition: OpenCodeHarnessDefinition.definition, installation: .installed, setup: .ready,
            modelOptions: AgentDefaultModelOptions.staticOptions(for: .opencode) + [option]
        )])
    }

    func installedHarnessStatuses(projectURL: URL?) async -> [AgentHarnessID: AgentHarnessStatus] { [:] }
    func availableHarnessStatuses(projectURL: URL?) async -> [AgentHarnessID: AgentHarnessStatus] { [:] }
    func modelOptions(for harnessId: AgentHarnessID) async -> [AgentModelOption] { [] }
    func stableHarnessOrdering() async -> [AgentHarnessID] { [.claude, .codex, .opencode] }
}
