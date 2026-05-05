import AppKit
import SnapshotTesting
import SwiftData
import SwiftUI
import XCTest

@testable import Alveary

extension SnapshotTests {
    func testConversationTabsBusyStatusSpinnerVisible() {
        assertConversationTabsStatusSnapshot(
            status: .busy,
            named: "conversation_tabs_busy_spinner"
        )
    }

    func testConversationTabsWaitingForUserStatusDotVisible() {
        assertConversationTabsStatusSnapshot(
            status: .waitingForUser,
            named: "conversation_tabs_waiting_for_user_dot"
        )
    }

    func testConversationTabsInlineCodeChip() {
        let thread = AgentThread(name: "Inline Code Tab Coverage")
        let chipConversation = Conversation(
            id: "chip",
            title: "Test `code block`",
            provider: "claude",
            isMain: true,
            displayOrder: 0,
            thread: thread
        )
        let plainConversation = Conversation(
            id: "plain",
            provider: "claude",
            isMain: false,
            displayOrder: 1,
            thread: thread
        )
        thread.conversations = [chipConversation, plainConversation]

        assertMacSnapshot(
            ThreadDetailConversationTabs(
                conversations: thread.conversations,
                selectedConversation: chipConversation,
                statusVersion: 0,
                statusForConversation: { _ in .unread },
                onSelect: { _ in },
                onCommitRename: { _, _ in },
                onRemove: { _ in },
                onCreate: {},
                isCreateDisabled: false,
                editingConversationID: .constant(nil)
            ),
            size: CGSize(width: 640, height: 72),
            named: "conversation_tabs_inline_code"
        )
    }

    func testConversationTabsMentionChip() {
        let thread = AgentThread(name: "Mention Tab Coverage")
        let mentionConversation = Conversation(
            id: "mention",
            title: "@.alveary.json",
            provider: "claude",
            isMain: true,
            displayOrder: 0,
            thread: thread
        )
        let plainConversation = Conversation(
            id: "plain",
            provider: "claude",
            isMain: false,
            displayOrder: 1,
            thread: thread
        )
        thread.conversations = [mentionConversation, plainConversation]

        assertMacSnapshot(
            ThreadDetailConversationTabs(
                conversations: thread.conversations,
                selectedConversation: mentionConversation,
                statusVersion: 0,
                statusForConversation: { _ in .unread },
                onSelect: { _ in },
                onCommitRename: { _, _ in },
                onRemove: { _ in },
                onCreate: {},
                isCreateDisabled: false,
                editingConversationID: .constant(nil)
            ),
            size: CGSize(width: 640, height: 72),
            named: "conversation_tabs_mention"
        )
    }

    func testConversationTabsSingleInlineCode() {
        let thread = AgentThread(name: "Single Conversation Inline Code")
        let onlyConversation = Conversation(
            id: "only",
            title: "Test `code block`",
            provider: "claude",
            isMain: true,
            displayOrder: 0,
            thread: thread
        )
        thread.conversations = [onlyConversation]

        assertMacSnapshot(
            ThreadDetailConversationTabs(
                conversations: thread.conversations,
                selectedConversation: onlyConversation,
                statusVersion: 0,
                statusForConversation: { _ in .unread },
                onSelect: { _ in },
                onCommitRename: { _, _ in },
                onRemove: { _ in },
                onCreate: {},
                isCreateDisabled: false,
                editingConversationID: .constant(nil)
            ),
            size: CGSize(width: 640, height: 72),
            named: "conversation_tabs_single_inline_code"
        )
    }

    func testConversationTabsDividerVisibleInDarkMode() {
        assertConversationTabsStatusSnapshot(
            status: .busy,
            named: "conversation_tabs_dark_divider",
            colorScheme: .dark
        )
    }

    private func assertConversationTabsStatusSnapshot(
        status: ThreadStatus,
        named: String,
        colorScheme: ColorScheme = .light,
        file: StaticString = #filePath,
        testName: String = #function,
        line: UInt = #line
    ) {
        let thread = AgentThread(name: "Status Dot Coverage")
        let mainConversation = Conversation(
            id: "main",
            provider: "claude",
            isMain: true,
            displayOrder: 0,
            thread: thread
        )
        let secondConversation = Conversation(
            id: "side",
            title: "Follow-up",
            provider: "claude",
            isMain: false,
            displayOrder: 1,
            thread: thread
        )
        thread.conversations = [mainConversation, secondConversation]

        assertMacSnapshot(
            ThreadDetailConversationTabs(
                conversations: thread.conversations,
                selectedConversation: mainConversation,
                statusVersion: 0,
                statusForConversation: { conversation in
                    conversation.id == mainConversation.id ? status : .stopped
                },
                onSelect: { _ in },
                onCommitRename: { _, _ in },
                onRemove: { _ in },
                onCreate: {},
                isCreateDisabled: false,
                editingConversationID: .constant(nil)
            ),
            size: CGSize(width: 640, height: 72),
            named: named,
            colorScheme: colorScheme,
            file: file,
            testName: testName,
            line: line
        )
    }

    // Covers the overflow state: enough conversation tabs at a narrow pane width that
    // the row must scroll. Pins the greedy ScrollView + trailing `New Conversation`
    // button layout so a regression (e.g. reintroducing a sibling `Spacer()` alongside
    // the flexible ScrollView) is caught. The trailing-edge divider is not captured in
    // the baseline — `onScrollGeometryChange` dispatches its action asynchronously,
    // after the snapshot pass's `displayIfNeeded()`. Unlike the terminal pane's
    // equivalent test (which does capture its divider), the conversation-tab layout
    // timing doesn't stabilize in time; see the `testConversationTabsOverflow` bullet
    // in `Alveary/Views/Chat/AGENTS.md` for the full story.
    func testConversationTabsOverflow() {
        let thread = AgentThread(name: "Overflow Tab Coverage")
        var conversations: [Conversation] = []
        for index in 1...8 {
            conversations.append(
                Conversation(
                    id: "conv-\(index)",
                    title: "Conversation \(index)",
                    provider: "claude",
                    isMain: index == 1,
                    displayOrder: index,
                    thread: thread
                )
            )
        }
        thread.conversations = conversations

        assertMacSnapshot(
            ThreadDetailConversationTabs(
                conversations: thread.conversations,
                selectedConversation: conversations[0],
                statusVersion: 0,
                statusForConversation: { _ in .stopped },
                onSelect: { _ in },
                onCommitRename: { _, _ in },
                onRemove: { _ in },
                onCreate: {},
                isCreateDisabled: false,
                editingConversationID: .constant(nil)
            ),
            size: CGSize(width: 500, height: 72),
            named: "conversation_tabs_overflow"
        )
    }

    func testConversationTabsEditingChip() {
        let thread = AgentThread(name: "Editing Chip Coverage")
        let mainConversation = Conversation(
            id: "main",
            provider: "claude",
            isMain: true,
            displayOrder: 0,
            thread: thread
        )
        let secondConversation = Conversation(
            id: "side",
            title: "Follow-up",
            provider: "claude",
            isMain: false,
            displayOrder: 1,
            thread: thread
        )
        thread.conversations = [mainConversation, secondConversation]

        assertMacSnapshot(
            ThreadDetailConversationTabs(
                conversations: thread.conversations,
                selectedConversation: secondConversation,
                statusVersion: 0,
                statusForConversation: { _ in .stopped },
                onSelect: { _ in },
                onCommitRename: { _, _ in },
                onRemove: { _ in },
                onCreate: {},
                isCreateDisabled: false,
                editingConversationID: .constant(secondConversation.persistentModelID)
            ),
            size: CGSize(width: 640, height: 72),
            named: "conversation_tabs_editing_chip"
        )
    }

    func testThreadDetailViewSelectedConversationTabStatusUpdatesAfterNotification() async throws {
        let fixture = try ThreadDetailStatusFixture()
        let host = MountedMacSnapshotHost(
            fixture.view,
            size: CGSize(width: 760, height: 72)
        )

        host.assertSnapshot(named: "thread_detail_selected_tab_idle")

        await fixture.agentsManager.setStatus(.busy, for: fixture.selectedConversation.id)
        NotificationCenter.default.post(
            name: .agentStatusChanged,
            object: nil,
            userInfo: [
                "conversationId": fixture.selectedConversation.id,
                "signal": ActivitySignal.busy
            ]
        )
        await Task.yield()
        await Task.yield()

        host.assertSnapshot(named: "thread_detail_selected_tab_busy_after_notification")
    }
}

@MainActor
private struct ThreadDetailStatusFixture {
    struct SeededModel {
        let container: ModelContainer
        let context: ModelContext
        let thread: AgentThread
        let selectedConversation: Conversation
    }

    let container: ModelContainer
    let context: ModelContext
    let appState: AppState
    let agentsManager: SnapshotMockAgentsManager
    let runtimeStore: MockConversationRuntimeStore
    let settingsService: InMemorySettingsService
    let providerRegistry: DefaultProviderRegistry
    let worktreeManager: MockWorktreeManager
    let providerSetup: MockProviderSetupService
    let contextWindowCache: MockContextWindowCache
    let fileListManager: SnapshotMockFileListManager
    let notificationManager: RecordingNotificationManager
    let diffViewModel: DiffViewerViewModel
    let thread: AgentThread
    let selectedConversation: Conversation

    init() throws {
        let seededData = try Self.makeSeededModel()
        container = seededData.container
        context = seededData.context
        thread = seededData.thread
        selectedConversation = seededData.selectedConversation

        appState = AppState()
        appState.selectedSidebarItem = .thread(thread)
        appState.selectConversation(selectedConversation, in: thread)

        agentsManager = SnapshotMockAgentsManager()
        runtimeStore = MockConversationRuntimeStore()
        settingsService = InMemorySettingsService()
        providerRegistry = DefaultProviderRegistry(agentRegistry: DefaultAgentRegistry())
        worktreeManager = MockWorktreeManager(
            worktreeInfo: WorktreeInfo(path: "/tmp/alveary-worktree", branch: "main")
        )
        providerSetup = MockProviderSetupService()
        contextWindowCache = MockContextWindowCache()
        fileListManager = SnapshotMockFileListManager()
        notificationManager = RecordingNotificationManager()
        diffViewModel = DiffViewerViewModel(
            gitService: SnapshotMockGitService(statusResults: [[]], diffResults: [""]),
            gitHubService: SnapshotMockGitHubService(),
            fileListManager: fileListManager,
            agentsManager: agentsManager,
            fsEventDebounceDuration: .seconds(10),
            idlePollInterval: .seconds(10)
        )
    }

    var view: some View {
        ThreadDetailView(
            thread: thread,
            appState: appState,
            modelContext: context,
            agentsManager: agentsManager,
            runtimeStore: runtimeStore,
            keepAwakeService: RecordingKeepAwakeService(),
            settingsService: settingsService,
            providerRegistry: providerRegistry,
            worktreeManager: worktreeManager,
            providerSetup: providerSetup,
            contextWindowCache: contextWindowCache,
            fileListManager: fileListManager,
            notificationManager: notificationManager,
            loadSkillCompletions: { [] },
            diffViewModel: diffViewModel
        )
        .environment(\.modelContext, context)
    }

    private static func makeSeededModel() throws -> SeededModel {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Project.self,
            AgentThread.self,
            Conversation.self,
            ConversationEventRecord.self,
            configurations: configuration
        )
        let context = ModelContext(container)

        let project = Project(path: "/tmp/alveary-project", name: "Alveary")
        let thread = AgentThread(name: "Thread Detail Status", hasCompletedInitialSetup: true, project: project)
        let mainConversation = Conversation(
            id: "main",
            title: "Main",
            provider: "claude",
            isMain: true,
            displayOrder: 0,
            thread: thread
        )
        let sideConversation = Conversation(
            id: "side",
            title: "Follow-up",
            provider: "claude",
            isMain: false,
            displayOrder: 1,
            thread: thread
        )
        thread.conversations = [mainConversation, sideConversation]
        project.threads = [thread]

        context.insert(project)
        context.insert(thread)
        context.insert(mainConversation)
        context.insert(sideConversation)
        try context.save()

        return SeededModel(
            container: container,
            context: context,
            thread: thread,
            selectedConversation: mainConversation
        )
    }
}

@MainActor
private final class MountedMacSnapshotHost<Content: View> {
    private let controller: NSHostingController<AnyView>
    private let window: NSWindow

    init(_ view: Content, size: CGSize, colorScheme: ColorScheme = .light) {
        let appearanceName: NSAppearance.Name = colorScheme == .dark ? .darkAqua : .aqua
        let rootView = AnyView(
            view
                .transaction { $0.animation = nil }
                .environment(\.locale, Locale(identifier: "en_US_POSIX"))
                .environment(\.timeZone, TimeZone(secondsFromGMT: 0) ?? .current)
                .environment(\.layoutDirection, .leftToRight)
                .environment(\.colorScheme, colorScheme)
                .frame(width: size.width, height: size.height, alignment: .topLeading)
                .background(Color(nsColor: .windowBackgroundColor))
        )

        controller = NSHostingController(rootView: rootView)
        controller.view.frame = CGRect(origin: .zero, size: size)
        controller.view.appearance = NSAppearance(named: appearanceName)

        let offscreenOrigin = CGPoint(x: -size.width - 1000, y: -size.height - 1000)
        window = NSWindow(
            contentRect: CGRect(origin: offscreenOrigin, size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: appearanceName)
        window.backgroundColor = .windowBackgroundColor
        window.contentViewController = controller
    }

    func assertSnapshot(
        named: String,
        file: StaticString = #filePath,
        testName: String = #function,
        line: UInt = #line
    ) {
        let isRecordingSnapshots = ProcessInfo.processInfo.environment["RECORD_SNAPSHOTS"] == "1"
        window.makeFirstResponder(nil)
        window.layoutIfNeeded()
        window.displayIfNeeded()
        controller.view.layoutSubtreeIfNeeded()
        controller.view.displayIfNeeded()

        SnapshotTesting.assertSnapshot(
            of: controller,
            as: .image(precision: 0.99, perceptualPrecision: 0.99),
            named: named,
            record: isRecordingSnapshots ? true : nil,
            file: file,
            testName: testName,
            line: line
        )
    }
}
