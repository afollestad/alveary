import AgentCLIKit
import Foundation
import SwiftData
import XCTest

@testable import Alveary

extension SidebarViewModelTests {
    func testOpenDraftThreadCreatesHiddenReusableThread() async throws {
        let fixture = try SidebarTestFixture()
        let project = try fixture.insertProject(name: "Alpha", path: "/tmp/draft-alpha")

        let draft = try await fixture.viewModel.openDraftThread(project: project)
        let reusedDraft = try await fixture.viewModel.openDraftThread(project: project)

        let savedDraft = try fixture.requireThread(draft)
        XCTAssertTrue(savedDraft.isDraft)
        XCTAssertEqual(reusedDraft.persistentModelID, savedDraft.persistentModelID)
        XCTAssertEqual(savedDraft.project?.path, project.path)
        XCTAssertEqual(savedDraft.conversations.count, 1)
        XCTAssertTrue(fixture.viewModel.activeThreads(for: project).isEmpty)
        XCTAssertFalse(fixture.viewModel.hasAnyActiveThreads(for: project))
    }

    func testOpenDraftThreadReusesIdentityAndMovesProjectWithoutClearingSelections() async throws {
        let fixture = try SidebarTestFixture()
        let alpha = try fixture.insertProject(name: "Alpha", path: "/tmp/draft-move-alpha")
        let beta = try fixture.insertProject(name: "Beta", path: "/tmp/draft-move-beta")
        let draft = try await fixture.viewModel.openDraftThread(project: alpha)
        let conversationID = try XCTUnwrap(draft.conversations.first?.id)
        let conversation = try fixture.requireConversation(id: conversationID)
        conversation.provider = "codex"
        draft.permissionMode = "acceptEdits"
        draft.model = "opus"
        draft.effort = "high"
        draft.planModeEnabled = true
        draft.speedMode = Alveary.AgentSpeedMode.fast.rawValue
        draft.useWorktree = true
        let preservedRuntime = makePreservedDraftRuntime(conversationID: conversationID)
        try fixture.context.save()

        let moved = try await fixture.viewModel.openDraftThread(project: beta)

        XCTAssertEqual(moved.persistentModelID, draft.persistentModelID)
        XCTAssertEqual(moved.conversations.first?.id, conversationID)
        XCTAssertEqual(try fixture.requireConversation(id: conversationID).provider, "codex")
        XCTAssertEqual(moved.project?.path, beta.path)
        XCTAssertEqual(moved.permissionMode, "acceptEdits")
        XCTAssertEqual(moved.model, "opus")
        XCTAssertEqual(moved.effort, "high")
        XCTAssertEqual(moved.planModeEnabled, true)
        XCTAssertEqual(moved.speedMode, Alveary.AgentSpeedMode.fast.rawValue)
        XCTAssertTrue(moved.useWorktree)
        assertPreservedDraftRuntime(preservedRuntime, conversationID: conversationID)
        XCTAssertEqual(fixture.settingsService.current.lastActiveProjectPath, beta.path)
    }

    func testDraftProjectReassignmentSaveFailureRestoresProjectAndRuntimeState() async throws {
        let fixture = try SidebarTestFixture(saveDraftProjectMove: { _ in
            throw DraftProjectMoveSaveError.forced
        })
        let alpha = try fixture.insertProject(name: "Alpha", path: "/tmp/draft-rollback-alpha")
        let beta = try fixture.insertProject(name: "Beta", path: "/tmp/draft-rollback-beta")
        let draft = try await fixture.viewModel.openDraftThread(project: alpha)
        let draftID = draft.persistentModelID
        let conversationID = try XCTUnwrap(draft.conversations.first?.id)
        let runtimeStore = MockConversationRuntimeStore()
        let state = runtimeStore.conversationState(for: conversationID)
        state.inputDraft = "Keep this failed move draft"
        state.stagedContext = "Keep this failed move context"
        let notificationRecorder = DraftProjectChangeNotificationRecorder(expectedThreadID: draftID)
        let observer = NotificationCenter.default.addObserver(
            forName: .threadDraftProjectChanged,
            object: nil,
            queue: nil
        ) { notification in
            notificationRecorder.recordIfMatching(notification.userInfo)
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        do {
            _ = try await fixture.viewModel.openDraftThread(project: beta)
            XCTFail("Expected draft project reassignment to fail")
        } catch DraftProjectMoveSaveError.forced {
            // expected
        }

        let restoredDraft = try fixture.requireThread(draft)
        XCTAssertEqual(restoredDraft.persistentModelID, draftID)
        XCTAssertEqual(restoredDraft.project?.persistentModelID, alpha.persistentModelID)
        XCTAssertEqual(restoredDraft.conversations.first?.id, conversationID)
        XCTAssertEqual(fixture.settingsService.current.lastActiveProjectPath, alpha.path)
        XCTAssertEqual(fixture.viewModel.pendingDraftProjectPath, alpha.path)
        let restoredState = runtimeStore.conversationState(for: conversationID)
        XCTAssertTrue(restoredState === state)
        XCTAssertEqual(restoredState.inputDraft, "Keep this failed move draft")
        XCTAssertEqual(restoredState.stagedContext, "Keep this failed move context")
        XCTAssertEqual(notificationRecorder.count, 0)
    }

    func testConcurrentOpenDraftThreadSharesOneRowAndLatestProjectWins() async throws {
        let discovery = PausingDraftProviderDiscoveryService(statuses: [
            .claude: SettingsViewModelTests.providerStatus(
                for: .claude,
                modelOptions: AgentModelOptionTestFixtures.claudeModelOptions
            )
        ])
        let fixture = try SidebarTestFixture(providerDiscovery: discovery)
        let alpha = try fixture.insertProject(name: "Alpha", path: "/tmp/draft-race-alpha")
        let beta = try fixture.insertProject(name: "Beta", path: "/tmp/draft-race-beta")

        let firstOpen = Task { @MainActor in
            try await fixture.viewModel.openDraftThread(project: alpha).persistentModelID
        }
        await discovery.waitUntilProviderStatusesRequested()
        let latestOpen = Task { @MainActor in
            try await fixture.viewModel.openDraftThread(project: beta).persistentModelID
        }
        for _ in 0..<100 where fixture.viewModel.pendingDraftProjectPath != beta.path {
            await Task.yield()
        }
        XCTAssertEqual(fixture.viewModel.pendingDraftProjectPath, beta.path)
        await discovery.resumeProviderStatuses()

        let firstDraftID = try await firstOpen.value
        let latestDraftID = try await latestOpen.value
        let latestDraft = try XCTUnwrap(fixture.context.resolveThread(id: latestDraftID))
        let drafts = try fixture.context.fetch(
            FetchDescriptor<AgentThread>(predicate: #Predicate { thread in
                thread.isDraft == true
            })
        )
        XCTAssertEqual(drafts.count, 1)
        XCTAssertEqual(firstDraftID, latestDraftID)
        XCTAssertEqual(latestDraft.conversations.count, 1)
        XCTAssertEqual(latestDraft.project?.persistentModelID, beta.persistentModelID)
        XCTAssertEqual(fixture.settingsService.current.lastActiveProjectPath, beta.path)
    }

    func testCreateThreadSeedsDefaultsAndInitialConversationForGitProjects() async throws {
        let fixture = try SidebarTestFixture(defaultEffort: "max", createWorktreeByDefault: true)
        let project = Project(
            path: "/tmp/alveary-project",
            name: "Alveary",
            gitBranch: "feature/auth",
            baseRef: "main"
        )
        fixture.context.insert(project)
        try fixture.context.save()

        let readContext = ModelContext(fixture.container)
        let externalProject = try XCTUnwrap(
            try readContext.fetch(FetchDescriptor<Project>()).first
        )

        let thread = try await fixture.viewModel.createThread(
            project: externalProject,
            provider: "claude",
            permissionMode: "acceptEdits"
        )

        let savedThread = try fixture.requireThread(thread)
        XCTAssertEqual(savedThread.name, "New thread")
        XCTAssertEqual(savedThread.permissionMode, "acceptEdits")
        XCTAssertEqual(savedThread.effort, "max")
        XCTAssertTrue(savedThread.useWorktree)
        XCTAssertFalse(savedThread.isPinned)
        XCTAssertEqual(savedThread.project?.path, project.path)
        XCTAssertEqual(savedThread.conversations.count, 1)
        XCTAssertEqual(savedThread.conversations.first?.provider, "claude")
        XCTAssertTrue(savedThread.conversations.first?.isMain ?? false)
        XCTAssertEqual(savedThread.conversations.first?.displayOrder, 0)
    }

    func testCreateThreadSeedsNilModelWhenDefaultModelSettingIsDefault() async throws {
        let fixture = try SidebarTestFixture(defaultModel: AppSettings.defaultModelValue)
        let project = try fixture.insertProject(name: "Plain", path: "/tmp/plain-default-model")

        let thread = try await fixture.viewModel.createThread(
            project: project,
            provider: "claude",
            permissionMode: "default"
        )

        XCTAssertNil(try fixture.requireThread(thread).model)
    }

    func testCreateThreadSeedsModelFromAppDefaultWhenOverridden() async throws {
        let fixture = try SidebarTestFixture(defaultModel: "opus")
        let project = try fixture.insertProject(name: "Plain", path: "/tmp/plain-opus-default")

        let thread = try await fixture.viewModel.createThread(
            project: project,
            provider: "claude",
            permissionMode: "default"
        )

        XCTAssertEqual(try fixture.requireThread(thread).model, "opus")
    }

    func testCreateThreadUsesMediumEffortByDefault() async throws {
        let fixture = try SidebarTestFixture()
        let project = try fixture.insertProject(name: "Plain Folder", path: "/tmp/plain-folder")

        let readContext = ModelContext(fixture.container)
        let externalProject = try XCTUnwrap(
            try readContext.fetch(FetchDescriptor<Project>()).first
        )

        let thread = try await fixture.viewModel.createThread(
            project: externalProject,
            provider: "claude",
            permissionMode: "default"
        )

        let savedThread = try fixture.requireThread(thread)
        XCTAssertEqual(savedThread.project?.path, project.path)
        XCTAssertEqual(savedThread.effort, AppSettings.defaultEffortLevel)
    }

    // Thread creation uses the already-normalized settings value. Settings UI
    // owns applying model-scoped defaults when the user changes the model.
    func testCreateThreadSeedsNormalizedSettingsEffortForSelectedModel() async throws {
        let fixture = try SidebarTestFixture(defaultEffort: "xhigh", defaultModel: "opus")
        let project = try fixture.insertProject(name: "Opus Project", path: "/tmp/opus-default")

        let thread = try await fixture.viewModel.createThread(
            project: project,
            provider: "claude",
            permissionMode: "default"
        )

        let savedThread = try fixture.requireThread(thread)
        XCTAssertEqual(savedThread.model, "opus")
        XCTAssertEqual(savedThread.effort, "xhigh")
    }

    // A user who explicitly picked a non-default effort in Settings (e.g. "high")
    // expects that choice to win over the per-model default, as long as the
    // value is valid for the new thread's model.
    func testCreateThreadPrefersCustomizedSettingsEffortOverPerModelDefault() async throws {
        let fixture = try SidebarTestFixture(defaultEffort: "high", defaultModel: "opus")
        let project = try fixture.insertProject(name: "Opus Project", path: "/tmp/opus-high")

        let thread = try await fixture.viewModel.createThread(
            project: project,
            provider: "claude",
            permissionMode: "default"
        )

        XCTAssertEqual(try fixture.requireThread(thread).effort, "high")
    }

    func testCreateThreadDefaultPathUsesReadyProviderFallback() async throws {
        let fixture = try SidebarTestFixture(
            providerDiscovery: RecordingProviderDiscoveryService(statuses: [
                .claude: SettingsViewModelTests.providerStatus(
                    for: .claude,
                    modelOptions: AgentModelOptionTestFixtures.claudeModelOptions
                ),
                .codex: SettingsViewModelTests.providerStatus(
                    for: .codex,
                    installation: .missing,
                    modelOptions: AgentModelOptionTestFixtures.codexModelOptions
                )
            ])
        )
        fixture.settingsService.update {
            $0.defaultProvider = "codex"
            $0.defaultModel = "gpt-5.4-mini"
            $0.permissionMode = "never"
        }
        let project = try fixture.insertProject(name: "Fallback Project", path: "/tmp/provider-fallback")

        let thread = try await fixture.viewModel.createThread(project: project)

        let savedThread = try fixture.requireThread(thread)
        XCTAssertEqual(savedThread.model, nil)
        XCTAssertEqual(savedThread.permissionMode, "default")
        XCTAssertEqual(savedThread.conversations.first?.provider, "claude")
    }

    func testCreateThreadDefaultPathFailsWhenNoProviderIsReady() async throws {
        let fixture = try SidebarTestFixture(
            providerDiscovery: RecordingProviderDiscoveryService(statuses: [
                .claude: SettingsViewModelTests.providerStatus(
                    for: .claude,
                    installation: .missing,
                    modelOptions: AgentModelOptionTestFixtures.claudeModelOptions
                ),
                .codex: SettingsViewModelTests.providerStatus(
                    for: .codex,
                    setup: .needsSetup,
                    modelOptions: AgentModelOptionTestFixtures.codexModelOptions
                )
            ])
        )
        let project = try fixture.insertProject(name: "No Providers", path: "/tmp/no-ready-providers")

        do {
            _ = try await fixture.viewModel.createThread(project: project)
            XCTFail("Expected no-ready-provider failure")
        } catch SidebarViewModelError.noReadyThreadDefaultProvider {
            XCTAssertTrue(fixture.context.hasChanges == false)
        }
    }

    func testCreateThreadDisablesWorktreeDefaultForNonGitProjects() async throws {
        let fixture = try SidebarTestFixture(defaultEffort: "max", createWorktreeByDefault: true)
        let project = try fixture.insertProject(name: "Plain Folder", path: "/tmp/plain-folder")

        let readContext = ModelContext(fixture.container)
        let externalProject = try XCTUnwrap(
            try readContext.fetch(FetchDescriptor<Project>()).first
        )

        let thread = try await fixture.viewModel.createThread(
            project: externalProject,
            provider: "claude",
            permissionMode: "acceptEdits"
        )

        let savedThread = try fixture.requireThread(thread)
        XCTAssertEqual(savedThread.project?.path, project.path)
        XCTAssertFalse(savedThread.useWorktree)
        XCTAssertEqual(savedThread.effort, "max")
        XCTAssertEqual(savedThread.conversations.count, 1)
    }
}

@MainActor
private func makePreservedDraftRuntime(conversationID: String) -> PreservedDraftRuntime {
    let store = MockConversationRuntimeStore()
    let state = store.conversationState(for: conversationID)
    let attachmentDate = Date(timeIntervalSince1970: 123)
    let image = LocalImageAttachment(
        id: "image",
        fileURL: URL(fileURLWithPath: "/tmp/draft-image.png"),
        label: "draft-image.png",
        createdAt: attachmentDate
    )
    let file = LocalFileAttachment(
        id: "file",
        fileURL: URL(fileURLWithPath: "/tmp/draft-notes.txt"),
        createdAt: attachmentDate
    )
    let appShot = AppShotAttachment(
        id: "app-shot",
        appName: "Preview",
        bundleIdentifier: "com.apple.Preview",
        windowTitle: "Draft window",
        screenshot: image,
        axTreeText: "Draft accessibility text",
        focusedElementSummary: "Focused text field",
        attachmentStoreRoot: URL(fileURLWithPath: "/tmp/draft-app-shots", isDirectory: true)
    )
    let goal = AgentGoalSnapshot(
        objective: "Preserve the draft",
        status: .active,
        availableActions: [.pause, .delete],
        elapsedSeconds: 10
    )
    state.inputDraft = "Keep this composer text"
    state.inputDraftIsEffectivelyEmpty = false
    state.stagedContext = "Keep this staged context"
    state.stagedImageAttachments = [image]
    state.stagedFileAttachments = [file]
    state.stagedAppShots = [appShot]
    state.isGoalModeArmed = true
    state.goalSnapshot = goal
    return PreservedDraftRuntime(store: store, state: state, image: image, file: file, appShot: appShot, goal: goal)
}

@MainActor
private func assertPreservedDraftRuntime(_ preserved: PreservedDraftRuntime, conversationID: String) {
    let movedState = preserved.store.conversationState(for: conversationID)
    XCTAssertTrue(movedState === preserved.state)
    XCTAssertEqual(movedState.inputDraft, "Keep this composer text")
    XCTAssertFalse(movedState.inputDraftIsEffectivelyEmpty)
    XCTAssertEqual(movedState.stagedContext, "Keep this staged context")
    XCTAssertEqual(movedState.stagedImageAttachments, [preserved.image])
    XCTAssertEqual(movedState.stagedFileAttachments, [preserved.file])
    XCTAssertEqual(movedState.stagedAppShots, [preserved.appShot])
    XCTAssertTrue(movedState.isGoalModeArmed)
    XCTAssertEqual(movedState.goalSnapshot, preserved.goal)
}

private struct PreservedDraftRuntime {
    let store: MockConversationRuntimeStore
    let state: ConversationState
    let image: LocalImageAttachment
    let file: LocalFileAttachment
    let appShot: AppShotAttachment
    let goal: AgentGoalSnapshot
}

private actor PausingDraftProviderDiscoveryService: AgentCLIKit.AgentProviderDiscoveryService {
    private let statuses: [AgentCLIKit.AgentProviderID: AgentCLIKit.AgentProviderStatus]
    private var didRequestProviderStatuses = false
    private var requestWaiters: [CheckedContinuation<Void, Never>] = []
    private var providerStatusesContinuation: CheckedContinuation<Void, Never>?

    init(statuses: [AgentCLIKit.AgentProviderID: AgentCLIKit.AgentProviderStatus]) {
        self.statuses = statuses
    }

    func providerStatuses(projectURL: URL?) async -> [AgentCLIKit.AgentProviderID: AgentCLIKit.AgentProviderStatus] {
        didRequestProviderStatuses = true
        requestWaiters.forEach { $0.resume() }
        requestWaiters.removeAll()
        await withCheckedContinuation { providerStatusesContinuation = $0 }
        return statuses
    }

    func installedProviderStatuses(projectURL: URL?) async -> [AgentCLIKit.AgentProviderID: AgentCLIKit.AgentProviderStatus] {
        statuses.filter { $0.value.isInstalled }
    }

    func availableProviderStatuses(projectURL: URL?) async -> [AgentCLIKit.AgentProviderID: AgentCLIKit.AgentProviderStatus] {
        statuses.filter { $0.value.isEnabled && $0.value.installation != .missing }
    }

    func modelOptions(for providerId: AgentCLIKit.AgentProviderID) async -> [AgentCLIKit.AgentModelOption] {
        statuses[providerId]?.modelOptions ?? []
    }

    func stableProviderOrdering() async -> [AgentCLIKit.AgentProviderID] {
        [.claude, .codex]
    }

    func waitUntilProviderStatusesRequested() async {
        guard !didRequestProviderStatuses else {
            return
        }
        await withCheckedContinuation { requestWaiters.append($0) }
    }

    func resumeProviderStatuses() {
        providerStatusesContinuation?.resume()
        providerStatusesContinuation = nil
    }
}

private enum DraftProjectMoveSaveError: Error {
    case forced
}

private final class DraftProjectChangeNotificationRecorder: @unchecked Sendable {
    private let expectedThreadID: PersistentIdentifier
    private let lock = NSLock()
    private var recordedCount = 0

    init(expectedThreadID: PersistentIdentifier) {
        self.expectedThreadID = expectedThreadID
    }

    var count: Int {
        lock.withLock { recordedCount }
    }

    func recordIfMatching(_ payload: [AnyHashable: Any]?) {
        guard payload?[ThreadDraftNotificationKey.threadID] as? PersistentIdentifier == expectedThreadID else {
            return
        }
        lock.withLock { recordedCount += 1 }
    }
}
