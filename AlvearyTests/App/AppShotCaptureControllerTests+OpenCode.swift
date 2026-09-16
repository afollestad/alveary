import AgentCLIKit
import XCTest

@testable import Alveary

@MainActor
extension AppShotCaptureControllerTests {
    func testOpenCodeCaptureDiscoversTheResolvedLastActiveProject() async throws {
        var settings = AppSettings()
        settings.defaultHarness = "opencode"
        settings.defaultModel = "provider/project-only"
        let discovery = RecordingHarnessDiscoveryService(statuses: [:])
        let fixture = try AppShotCaptureControllerFixture(settings: settings, harnessDiscovery: discovery)
        let project = try fixture.insertProject(name: "Project", path: "/tmp/opencode-last-active")
        fixture.settingsService.update { $0.lastActiveProjectID = project.id }
        await fixture.runCapture()
        let directories = await discovery.requestedProjectURLs
        XCTAssertEqual(directories, [URL(fileURLWithPath: project.path, isDirectory: true)])
    }

    func testOpenCodeGlobalShortcutRejectsUnconfirmedOrTextOnlyModelsBeforeCapture() async throws {
        for model in [nil, "provider/text", "provider/missing"] as [String?] {
            let fixture = try makeOpenCodeCaptureFixture()
            let project = try fixture.insertProject(name: "Project", path: "/tmp/opencode-capture")
            let seeded = try fixture.insertThread(name: "Task", project: project)
            seeded.conversations.first?.harness = nil
            seeded.conversations.first?.harnessSessionHarnessId = "opencode"
            seeded.thread.model = model
            fixture.appState.selectedSidebarItem = .thread(seeded.thread)

            await fixture.runCapture()

            let prepared = await fixture.prepareGate.count()
            let stored = await fixture.attachmentStore.storedConversationIDs
            XCTAssertEqual(prepared, 0)
            XCTAssertTrue(stored.isEmpty)
            XCTAssertEqual(fixture.feedback.successSoundCount, 0)
            XCTAssertEqual(fixture.appState.unexpectedErrorToasts.count, 1)
        }
    }

    func testOpenCodeGlobalDefaultRequiresImageDiscoveryBeforeCreatingDraft() async throws {
        var settings = AppSettings()
        settings.defaultHarness = "opencode"
        settings.defaultModel = "provider/vision"
        let fixture = try AppShotCaptureControllerFixture(settings: settings)

        await fixture.runCapture()

        let prepared = await fixture.prepareGate.count()
        XCTAssertEqual(prepared, 0)
        XCTAssertEqual(fixture.draftOpener.openCount, 0)
        XCTAssertEqual(fixture.appState.unexpectedErrorToasts.count, 1)
    }

    func testOpenCodeVisionCaptureStagesStructuredAppShot() async throws {
        let fixture = try makeOpenCodeCaptureFixture()
        let project = try fixture.insertProject(name: "Project", path: "/tmp/opencode-capture-vision")
        let seeded = try fixture.insertThread(name: "Task", project: project)
        seeded.conversations.first?.harness = "opencode"
        seeded.thread.model = "provider/vision"
        fixture.appState.selectedSidebarItem = .thread(seeded.thread)

        await fixture.runCapture()

        let state = fixture.runtimeStore.conversationState(for: "main")
        XCTAssertEqual(state.stagedAppShots.count, 1)
        XCTAssertEqual(state.stagedAppShots.first?.axTreeText, "standard window Document")
        XCTAssertEqual(fixture.feedback.successSoundCount, 1)
    }

    func testOpenCodeModelChangeDuringCaptureRejectsBeforeStorage() async throws {
        let fixture = try makeOpenCodeCaptureFixture(pausesPreparation: true)
        let project = try fixture.insertProject(name: "Project", path: "/tmp/opencode-capture-change")
        let seeded = try fixture.insertThread(name: "Task", project: project)
        seeded.conversations.first?.harness = "opencode"
        seeded.thread.model = "provider/vision"
        fixture.appState.selectedSidebarItem = .thread(seeded.thread)

        let capture = try XCTUnwrap(fixture.controller.captureIfIdle())
        await fixture.prepareGate.waitUntilPreparationBegins()
        seeded.thread.model = "provider/text"
        await fixture.prepareGate.resumePreparation()
        await capture.value

        let stored = await fixture.attachmentStore.storedConversationIDs
        XCTAssertTrue(stored.isEmpty)
        XCTAssertTrue(fixture.runtimeStore.conversationState(for: "main").stagedAppShots.isEmpty)
        XCTAssertEqual(fixture.feedback.successSoundCount, 0)
    }

    func testOpenCodeModelChangeDuringStorageRemovesUnstagedFile() async throws {
        let fixture = try makeOpenCodeCaptureFixture(pausesStorage: true)
        let project = try fixture.insertProject(name: "Project", path: "/tmp/opencode-capture-storage")
        let seeded = try fixture.insertThread(name: "Task", project: project)
        seeded.conversations.first?.harness = "opencode"
        seeded.thread.model = "provider/vision"
        fixture.appState.selectedSidebarItem = .thread(seeded.thread)

        let capture = try XCTUnwrap(fixture.controller.captureIfIdle())
        try await waitUntil("OpenCode app-shot storage", timeout: .seconds(1), pollInterval: .milliseconds(10)) {
            await fixture.attachmentStore.hasBegunStorage()
        }
        seeded.thread.model = "provider/text"
        await fixture.attachmentStore.resumeStorage()
        await capture.value

        let removed = await fixture.attachmentStore.removedAttachmentURLs
        XCTAssertEqual(removed.count, 1)
        XCTAssertTrue(fixture.runtimeStore.conversationState(for: "main").stagedAppShots.isEmpty)
        XCTAssertEqual(fixture.feedback.successSoundCount, 0)
    }

    func testOpenCodeCaptureUsesReplacementStateAfterFinalDiscovery() async throws {
        let discovery = PausingAppShotHarnessDiscovery(status: openCodeCaptureStatus())
        let fixture = try AppShotCaptureControllerFixture(harnessDiscovery: discovery, pausesStorage: true)
        let project = try fixture.insertProject(name: "Project", path: "/tmp/opencode-capture-replacement")
        let seeded = try fixture.insertThread(name: "Task", project: project)
        let conversation = try XCTUnwrap(seeded.conversations.first)
        conversation.harness = "opencode"
        seeded.thread.model = "provider/vision"
        fixture.appState.selectedSidebarItem = .thread(seeded.thread)
        let originalState = fixture.runtimeStore.conversationState(for: conversation.id)

        let capture = try XCTUnwrap(fixture.controller.captureIfIdle())
        try await waitUntil("OpenCode app-shot storage", timeout: .seconds(1), pollInterval: .milliseconds(10)) {
            await fixture.attachmentStore.hasBegunStorage()
        }
        await discovery.pauseNextRead()
        await fixture.attachmentStore.resumeStorage()
        try await waitUntil("OpenCode app-shot final discovery", timeout: .seconds(1), pollInterval: .milliseconds(10)) {
            await discovery.isReadPaused
        }
        // Initial-setup cancellation retains this conversation but replaces its canonical composer state.
        let replacementState = ConversationState()
        fixture.runtimeStore.bindConversationState(replacementState, for: conversation.id)
        await discovery.resumeRead()
        await capture.value

        XCTAssertTrue(originalState.stagedAppShots.isEmpty)
        let appShot = try XCTUnwrap(replacementState.stagedAppShots.first)
        XCTAssertEqual(replacementState.stagedAppShots.count, 1)
        XCTAssertTrue(fixture.runtimeStore.conversationState(for: conversation.id) === replacementState)
        XCTAssertTrue(FileManager.default.fileExists(atPath: appShot.screenshot.fileURL.path))
        let removedURLs = await fixture.attachmentStore.removedAttachmentURLs
        XCTAssertTrue(removedURLs.isEmpty)
        XCTAssertEqual(fixture.feedback.successSoundCount, 1)
    }

    private func makeOpenCodeCaptureFixture(
        pausesPreparation: Bool = false, pausesStorage: Bool = false
    ) throws -> AppShotCaptureControllerFixture {
        try AppShotCaptureControllerFixture(
            harnessDiscovery: RecordingHarnessDiscoveryService(statuses: [.opencode: openCodeCaptureStatus()]),
            pausesPreparation: pausesPreparation,
            pausesStorage: pausesStorage
        )
    }

    private func openCodeCaptureStatus() -> AgentHarnessStatus {
        AgentHarnessStatus(
            harnessId: .opencode,
            definition: OpenCodeHarnessDefinition.definition,
            modelOptions: [
                .init(harnessId: .opencode, id: "provider/text", model: "provider/text", label: "Text"),
                .init(
                    harnessId: .opencode, id: "provider/vision", model: "provider/vision", label: "Vision",
                    metadata: [OpenCodeModelMetadata.supportsImageInput: .bool(true)]
                )
            ]
        )
    }
}

private actor PausingAppShotHarnessDiscovery: AgentHarnessDiscoveryService {
    private let status: AgentHarnessStatus
    private var shouldPauseNextRead = false
    private var pendingRead: CheckedContinuation<Void, Never>?
    var isReadPaused: Bool { pendingRead != nil }

    init(status: AgentHarnessStatus) {
        self.status = status
    }

    func pauseNextRead() {
        shouldPauseNextRead = true
    }

    func resumeRead() {
        pendingRead?.resume()
        pendingRead = nil
    }

    func harnessStatuses(projectURL: URL?) async -> [AgentHarnessID: AgentHarnessStatus] {
        if shouldPauseNextRead {
            shouldPauseNextRead = false
            await withCheckedContinuation { pendingRead = $0 }
        }
        return [.opencode: status]
    }

    func installedHarnessStatuses(projectURL: URL?) async -> [AgentHarnessID: AgentHarnessStatus] { [.opencode: status] }
    func availableHarnessStatuses(projectURL: URL?) async -> [AgentHarnessID: AgentHarnessStatus] { [.opencode: status] }
    func modelOptions(for harnessId: AgentHarnessID) async -> [AgentModelOption] { status.modelOptions }
    func stableHarnessOrdering() async -> [AgentHarnessID] { [.opencode] }
}
