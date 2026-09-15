import SwiftData
import XCTest

@testable import Alveary

@MainActor
final class ContentViewNotificationRoutingTests: XCTestCase {
    func testOpenConversationSelectsThreadAndConversation() throws {
        let fixture = try RoutingTestFixture()
        let conversation = fixture.seedConversation(threadName: "Thread", archivedAt: nil)

        openConversationInAppState(
            conversationId: conversation.id,
            modelContext: fixture.context,
            appState: fixture.appState
        )

        guard case .thread(let thread) = fixture.appState.selectedSidebarItem else {
            return XCTFail("selectedSidebarItem should resolve to the conversation's thread")
        }
        XCTAssertEqual(thread.persistentModelID, conversation.thread?.persistentModelID)
        XCTAssertEqual(
            fixture.appState.selectedConversationIDs[thread.persistentModelID],
            conversation.persistentModelID
        )
    }

    func testOpenConversationIgnoresArchivedThread() throws {
        let fixture = try RoutingTestFixture()
        let conversation = fixture.seedConversation(threadName: "Archived", archivedAt: Date())

        openConversationInAppState(
            conversationId: conversation.id,
            modelContext: fixture.context,
            appState: fixture.appState
        )

        XCTAssertNil(fixture.appState.selectedSidebarItem)
        XCTAssertTrue(fixture.appState.selectedConversationIDs.isEmpty)
    }

    func testOpenConversationAndActiveHarnessIgnoreDraftThread() throws {
        let fixture = try RoutingTestFixture()
        let conversation = fixture.seedConversation(threadName: "Draft", archivedAt: nil, isDraft: true)
        let thread = try XCTUnwrap(conversation.thread)

        openConversationInAppState(
            conversationId: conversation.id,
            modelContext: fixture.context,
            appState: fixture.appState
        )

        XCTAssertNil(fixture.appState.selectedSidebarItem)
        fixture.appState.selectedConversationIDs[thread.persistentModelID] = conversation.persistentModelID
        fixture.appState.selectedSidebarItem = .thread(thread)
        XCTAssertNil(makeActiveConversationProvider(for: fixture.appState, modelContext: fixture.context)())
    }

    func testOpenConversationIgnoresMissingConversationId() throws {
        let fixture = try RoutingTestFixture()

        openConversationInAppState(
            conversationId: "missing",
            modelContext: fixture.context,
            appState: fixture.appState
        )

        XCTAssertNil(fixture.appState.selectedSidebarItem)
    }

    func testTranscriptThreadCardSelectsItsThread() throws {
        let fixture = try RoutingTestFixture()
        let conversation = fixture.seedConversation(threadName: "Thread", archivedAt: nil)

        openTranscriptThreadInAppState(
            conversationId: conversation.id,
            modelContext: fixture.context,
            appState: fixture.appState
        )

        guard case .thread(let thread) = fixture.appState.selectedSidebarItem else {
            return XCTFail("selectedSidebarItem should resolve to the card's thread")
        }
        XCTAssertEqual(thread.persistentModelID, conversation.thread?.persistentModelID)
    }

    /// An archive card's thread has no sidebar row left, so the card lands on the screen that
    /// still lists it rather than doing nothing.
    func testTranscriptThreadCardRoutesAnArchivedThreadToTheArchivedScreen() throws {
        let fixture = try RoutingTestFixture()
        let conversation = fixture.seedConversation(threadName: "Archived", archivedAt: Date())

        openTranscriptThreadInAppState(
            conversationId: conversation.id,
            modelContext: fixture.context,
            appState: fixture.appState
        )

        XCTAssertEqual(fixture.appState.selectedSidebarItem, .archived)
        XCTAssertTrue(fixture.appState.selectedConversationIDs.isEmpty)
    }

    func testTranscriptThreadCardIgnoresDraftAndMissingThreads() throws {
        let fixture = try RoutingTestFixture()
        let draft = fixture.seedConversation(threadName: "Draft", archivedAt: nil, isDraft: true)

        openTranscriptThreadInAppState(
            conversationId: draft.id,
            modelContext: fixture.context,
            appState: fixture.appState
        )
        XCTAssertNil(fixture.appState.selectedSidebarItem)

        openTranscriptThreadInAppState(
            conversationId: "missing",
            modelContext: fixture.context,
            appState: fixture.appState
        )
        XCTAssertNil(fixture.appState.selectedSidebarItem)
    }

    func testActiveConversationProviderReturnsNilWhenNoThreadSelected() throws {
        let fixture = try RoutingTestFixture()
        let harness = makeActiveConversationProvider(for: fixture.appState, modelContext: fixture.context)

        XCTAssertNil(harness())
    }

    func testActiveConversationProviderReturnsSelectedConversationIdForThread() throws {
        let fixture = try RoutingTestFixture()
        let conversation = fixture.seedConversation(threadName: "Thread", archivedAt: nil)
        let thread = try XCTUnwrap(conversation.thread)
        fixture.appState.selectedConversationIDs[thread.persistentModelID] = conversation.persistentModelID
        fixture.appState.selectedSidebarItem = .thread(thread)

        let harness = makeActiveConversationProvider(for: fixture.appState, modelContext: fixture.context)

        XCTAssertEqual(harness(), conversation.id)
    }

    func testActiveConversationProviderReleasesAppStateWeakly() throws {
        let fixture = try RoutingTestFixture()
        let conversation = fixture.seedConversation(threadName: "Thread", archivedAt: nil)
        let thread = try XCTUnwrap(conversation.thread)

        var strongAppState: AppState? = AppState()
        strongAppState?.selectedConversationIDs[thread.persistentModelID] = conversation.persistentModelID
        strongAppState?.selectedSidebarItem = .thread(thread)

        let harness = makeActiveConversationProvider(for: strongAppState!, modelContext: fixture.context)
        XCTAssertEqual(harness(), conversation.id)

        strongAppState = nil
        XCTAssertNil(harness())
    }

    func testAppNavigationIsBlockedWhileVoiceModelModalIsPresented() {
        let lifecycleController = VoiceInputLifecycleController(service: DisabledVoiceInputService())
        let sink = NotificationRoutingVoiceInputSinkFake(isModelPreparationModalPresented: true)
        lifecycleController.setActiveComposerSink(sink)
        var actionCount = 0

        let didPerform = performAppNavigationIfModelPreparationModalAbsent(
            lifecycleController: lifecycleController
        ) {
            actionCount += 1
        }

        XCTAssertFalse(didPerform)
        XCTAssertEqual(actionCount, 0)
    }

    func testRecordingLikeComposerLockDoesNotBlockAppNavigation() {
        let lifecycleController = VoiceInputLifecycleController(service: DisabledVoiceInputService())
        let sink = NotificationRoutingVoiceInputSinkFake(isModelPreparationModalPresented: false)
        lifecycleController.setActiveComposerSink(sink)
        var actionCount = 0

        let didPerform = performAppNavigationIfModelPreparationModalAbsent(
            lifecycleController: lifecycleController
        ) {
            actionCount += 1
        }

        XCTAssertTrue(lifecycleController.isComposerInteractionLocked)
        XCTAssertFalse(lifecycleController.isModelPreparationModalPresented)
        XCTAssertTrue(didPerform)
        XCTAssertEqual(actionCount, 1)
    }

    func testDeferredNotificationRemainsPendingUntilVoiceModelModalCloses() {
        let lifecycleController = VoiceInputLifecycleController(service: DisabledVoiceInputService())
        let sink = NotificationRoutingVoiceInputSinkFake(isModelPreparationModalPresented: true)
        let router = NotificationRouter()
        router.requestOpen(conversationId: "pending-conversation")
        lifecycleController.setActiveComposerSink(sink)

        performAppNavigationIfModelPreparationModalAbsent(lifecycleController: lifecycleController) {
            router.clearPendingIfMatches("pending-conversation")
        }
        XCTAssertEqual(router.pendingConversationId, "pending-conversation")

        lifecycleController.clearActiveComposerSink(sink)
        performAppNavigationIfModelPreparationModalAbsent(lifecycleController: lifecycleController) {
            router.clearPendingIfMatches("pending-conversation")
        }
        XCTAssertNil(router.pendingConversationId)
    }

    func testStatusMenuCommandsReplayAfterModelPreparationFinishes() throws {
        let component = AppDI.makeTestComponent(isStoredInMemoryOnly: true)
        let lifecycleController = component.voiceInputLifecycleController
        let router = component.menuBarCommandRouter
        let sink = NotificationRoutingVoiceInputSinkFake(isModelPreparationModalPresented: true)

        for kind in [MenuBarCommandKind.newThread, .openSettings] {
            let appState = AppState()
            let view = ContentView(component: component, appState: appState)
            lifecycleController.setActiveComposerSink(sink)
            switch kind {
            case .newThread: router.requestNewThread()
            case .openSettings: router.requestOpenSettings()
            }
            let request = try XCTUnwrap(router.pendingCommand)

            view.routePendingMenuBarCommandIfModelPreparationAllows(request)

            XCTAssertEqual(router.pendingCommand, request)
            XCTAssertNil(appState.pendingCommand)
            XCTAssertNil(appState.selectedSidebarItem)

            lifecycleController.clearActiveComposerSink(sink)
            view.routePendingMenuBarCommandIfModelPreparationAllows(router.pendingCommand)

            XCTAssertNil(router.pendingCommand)
            switch kind {
            case .newThread:
                guard case .newThread = appState.pendingCommand else {
                    return XCTFail("The reopened window should receive the new-thread request")
                }
            case .openSettings:
                XCTAssertEqual(appState.selectedSidebarItem, .settings)
            }
        }
    }

    func testPendingCommandWaitsWhenVoiceModelModalAppearsAfterAsyncWorkStarts() {
        let commandID = UUID()

        XCTAssertFalse(pendingCommandCanProceed(
            commandID: commandID,
            currentCommandID: commandID,
            isModelPreparationModalPresented: true
        ))
        XCTAssertTrue(pendingCommandCanProceed(
            commandID: commandID,
            currentCommandID: commandID,
            isModelPreparationModalPresented: false
        ))
    }

    func testPendingCommandCannotCompleteAfterAReplacementCommandWins() {
        XCTAssertFalse(pendingCommandCanProceed(
            commandID: UUID(),
            currentCommandID: UUID(),
            isModelPreparationModalPresented: false
        ))
    }

    func testVoiceModelCacheClearIsBlockedOnlyByModelPreparationModal() {
        let lifecycleController = VoiceInputLifecycleController(service: DisabledVoiceInputService())
        let modelModalSink = NotificationRoutingVoiceInputSinkFake(isModelPreparationModalPresented: true)
        lifecycleController.setActiveComposerSink(modelModalSink)
        var actionCount = 0

        XCTAssertFalse(performVoiceModelCacheClearIfModelPreparationModalAbsent(
            lifecycleController: lifecycleController
        ) {
            actionCount += 1
        })
        XCTAssertEqual(actionCount, 0)

        lifecycleController.clearActiveComposerSink(modelModalSink)
        let recordingLikeSink = NotificationRoutingVoiceInputSinkFake(isModelPreparationModalPresented: false)
        lifecycleController.setActiveComposerSink(recordingLikeSink)
        XCTAssertTrue(performVoiceModelCacheClearIfModelPreparationModalAbsent(
            lifecycleController: lifecycleController
        ) {
            actionCount += 1
        })
        XCTAssertEqual(actionCount, 1)
    }
}

@MainActor
private final class NotificationRoutingVoiceInputSinkFake: VoiceInputComposerSink {
    let isModelPreparationModalPresented: Bool

    init(isModelPreparationModalPresented: Bool) {
        self.isModelPreparationModalPresented = isModelPreparationModalPresented
    }

    func forceVoiceInputCommitSynchronously() {}
}

@MainActor
private struct RoutingTestFixture {
    let container: ModelContainer
    let context: ModelContext
    let appState: AppState

    init() throws {
        container = try ModelContainer(
            for: Project.self,
            AgentThread.self,
            Conversation.self,
            ConversationEventRecord.self,
            ScheduledTask.self,
            ScheduledTaskRun.self,
            ScheduledTaskProposal.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        context = ModelContext(container)
        appState = AppState()
    }

    @discardableResult
    func seedConversation(threadName: String, archivedAt: Date?, isDraft: Bool = false) -> Conversation {
        let thread = AgentThread(name: threadName, hasCustomName: true, isDraft: isDraft, archivedAt: archivedAt)
        let conversation = Conversation(isMain: true, thread: thread)
        context.insert(thread)
        context.insert(conversation)
        try? context.save()
        return conversation
    }
}
