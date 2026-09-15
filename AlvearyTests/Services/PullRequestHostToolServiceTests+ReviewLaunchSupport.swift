import AgentCLIKit
import Foundation
import SwiftData
import XCTest

@testable import Alveary

/// Real launch and host services share storage, while harness work stays behind a controllable gate.
@MainActor
final class PullRequestHostReviewLaunchFixture {
    let sidebar: SidebarTestFixture
    let host: PullRequestHostToolFixture
    let launcher: PullRequestAgenticThreadService
    let coordinator: PullRequestReviewTeamCoordinator
    let worker: ReviewCoordinatorWorker
    let prompts: ThreadHostToolPromptRecorder
    let packetRoot: URL

    init(
        harnessDiscovery: (any AgentHarnessDiscoveryService)? = nil,
        receiptSave: @escaping (ModelContext) throws -> Void = { try $0.save() },
        coordinatorSave: @escaping (ModelContext) throws -> Void = { try $0.save() }
    ) throws {
        let sidebar = try SidebarTestFixture()
        self.sidebar = sidebar
        let host = try PullRequestHostToolFixture(sidebar: sidebar)
        self.host = host
        let discovery = harnessDiscovery ?? RecordingHarnessDiscoveryService(statuses: [
            .claude: SettingsViewModelTests.harnessStatus(for: .claude, modelOptions: AgentModelOptionTestFixtures.claudeModelOptions),
            .codex: SettingsViewModelTests.harnessStatus(for: .codex, modelOptions: AgentModelOptionTestFixtures.codexModelOptions)
        ])
        let worker = ReviewCoordinatorWorker()
        self.worker = worker
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("host-review-tests-\(UUID().uuidString)")
        packetRoot = root
        let activity = PullRequestAgenticThreadActivity(currentSignal: { _ in .neutral })
        let coordinator = PullRequestReviewTeamCoordinator(
            modelContext: sidebar.context,
            service: host.pullRequests,
            worker: worker,
            packets: ReviewPacketStore(rootDirectory: root),
            staging: PullRequestCollectiveReviewStagingService(modelContext: sidebar.context, service: host.pullRequests),
            activity: activity,
            resolver: PullRequestReviewTeamResolver(harnessDiscovery: discovery),
            cancellationStore: ReviewTeamCancellationStore(rootDirectory: root.appendingPathComponent("cancellations")),
            notificationManager: RecordingNotificationManager(),
            commitSave: coordinatorSave
        )
        self.coordinator = coordinator
        let prompts = ThreadHostToolPromptRecorder()
        self.prompts = prompts
        let launcher = Self.makeLauncher(
            sidebar: sidebar, host: host, coordinator: coordinator, discovery: discovery, prompts: prompts
        )
        self.launcher = launcher
        host.service = Self.makeHostService(host: host, launcher: launcher, receiptSave: receiptSave)
        try seedPullRequestAndSettings()
    }

    deinit { try? FileManager.default.removeItem(at: packetRoot) }

    func replaceHostService() {
        host.service = Self.makeHostService(host: host, launcher: launcher)
    }

    func reviewThread() throws -> AgentThread {
        try XCTUnwrap(sidebar.context.fetch(FetchDescriptor<AgentThread>()).first { $0.name == "Review octo/alpha#7" })
    }

    func wait(_ condition: @MainActor () async -> Bool) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(8))
        while !(await condition()) {
            guard clock.now < deadline else { throw ReviewTeamError.invalidOutput("Timed out waiting for review launch.") }
            await Task.yield()
        }
    }

    private func seedPullRequestAndSettings() throws {
        var detail = makePullRequestDetail(id: try XCTUnwrap(PullRequestHostToolFixture.identifier))
        detail.viewerLogin = "reviewer"
        detail.baseRefOid = "base"
        detail.headRefOid = "head"
        host.pullRequests.detailResult = .success(detail)
        host.pullRequests.diffSnapshotResult = .success(try PullRequestDiffSnapshot.make(
            text: makeUnifiedDiffFixture(fileCount: 1), baseOID: "base", headOID: "head"
        ))
        host.settingsService.update {
            $0.pullRequestReviewMode = .singleAgent
            $0.pullRequestReviewHarness = "claude"
            $0.pullRequestReviewModel = "sonnet"
            $0.pullRequestReviewEffort = "high"
            $0.pullRequestReviewPeers = [
                PullRequestReviewPeer(id: "peer", harnessID: "codex", model: "gpt-5.5", effort: "medium")
            ]
        }
    }

    private static func makeHostService(
        host: PullRequestHostToolFixture,
        launcher: PullRequestAgenticThreadService,
        receiptSave: @escaping (ModelContext) throws -> Void = { try $0.save() }
    ) -> PullRequestHostToolService {
        PullRequestHostToolService(
            modelContext: host.modelContext,
            pullRequestsService: host.pullRequests,
            settingsService: host.settingsService,
            summaryHandoff: host.summaryHandoff,
            notificationCenter: host.notificationCenter,
            reviewLauncher: launcher,
            reviewReceiptSave: receiptSave
        )
    }

    private static func makeLauncher(
        sidebar: SidebarTestFixture,
        host: PullRequestHostToolFixture,
        coordinator: PullRequestReviewTeamCoordinator,
        discovery: any AgentHarnessDiscoveryService,
        prompts: ThreadHostToolPromptRecorder
    ) -> PullRequestAgenticThreadService {
        PullRequestAgenticThreadService(
            lifecycleService: sidebar.viewModel.threadLifecycle,
            linkService: PullRequestLinkService(modelContext: sidebar.context, service: host.pullRequests),
            pullRequestsService: host.pullRequests,
            settingsService: host.settingsService,
            worktreeManager: sidebar.worktreeManager,
            taskWorkspaceOwnershipService: sidebar.taskWorkspaceOwnershipService,
            harnessDiscovery: discovery,
            directoryExists: { _ in false },
            currentBranch: { _ in nil },
            reviewTeamCoordinator: coordinator,
            activity: coordinator.activity,
            startInitialPrompt: { conversation, prompt in
                prompts.record(conversationID: conversation.id, prompt: prompt)
            }
        )
    }
}
