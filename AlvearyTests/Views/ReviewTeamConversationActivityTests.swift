import AppKit
import SwiftUI
import Testing

@testable import Alveary

@MainActor
struct ReviewTeamConversationActivityTests {
    @Test(arguments: [
        (ReviewTeamRun.Phase.preparing, ThreadStatus.busy), (.inspecting, .busy), (.consolidating, .busy),
        (.crossChecking, .busy), (.staging, .busy), (.awaitingDecision, .waitingForUser),
        (.staged, .stopped), (.completed, .stopped), (.cancelled, .stopped)
    ])
    func `coordinator drives sidebar and tab activity without a provider turn`(
        phase: ReviewTeamRun.Phase, expected: ThreadStatus
    ) throws {
        let fixture = try ReviewCoordinatorFixture()
        var run = try fixture.makeRun()
        run.phase = phase
        try fixture.coordinator.persist(run)
        let activity = ConversationWorkActivity(reviewProposals: nil, reviewTeams: fixture.coordinator)
        let attention = ConversationDecisionAttention(
            approvals: nil, scheduledProposals: nil, reviewProposals: nil, settings: AppSettings(), reviewTeams: fixture.coordinator
        )
        let snapshot = ConversationStatusSnapshot(conversation: fixture.conversation, attention: attention, activity: activity)

        #expect(ThreadStatus.folded(isArchived: false, conversations: [snapshot], runtimeFor: { _ in .neutral }) == expected)
        #expect(activity.isWorking("another-conversation") == false)
    }

    @Test(arguments: [true, false])
    func `composer and transcript use collective work independently of provider activity`(isWorking: Bool) throws {
        let fixture = try ConversationViewModelTestFixture()
        let view = ReviewTeamConversationTestFixture.chatView(fixture: fixture, isWorking: isWorking)
        let transcript = ChatTranscriptView(
            viewModel: fixture.viewModel, appState: view.appState, events: [], workingDirectory: nil,
            lastScrollTime: .constant(.distantPast), isFollowing: .constant(true), scrollToBottomRequest: .constant(0),
            isReviewTeamWorking: isWorking
        )

        #expect(view.composerMode == (isWorking ? .progressOnly(.reviewTeam) : .idle))
        #expect(view.composerPresentation.isTextEditorDisabled == isWorking)
        #expect(view.composerPresentation.canUseEscapeToStop == isWorking)
        #expect(transcript.appKitTransientRows.isTurnActive == isWorking)
        #expect(fixture.viewModel.turnState.isActive == false)
    }

    @Test
    func `composer stop button and keyboard stop route to the review team`() throws {
        let fixture = try ConversationViewModelTestFixture()
        var cancelCount = 0
        let view = ReviewTeamConversationTestFixture.chatView(fixture: fixture, isWorking: true, onCancel: { cancelCount += 1 })
        let row = ChatComposerActionRowView()
        row.configure(view.composerActionRowConfiguration(usageSummary: .unreported))
        let stop = try #require(row.modelsDescendants(of: ComposerActionButton.self).first)

        #expect(stop.accessibilityLabel() == "Stop")
        #expect(stop.accessibilityPerformPress())
        #expect(cancelCount == 1)
        view.composerBodyConfiguration.onStop()
        #expect(cancelCount == 2)
    }

    @Test
    func `live cancellation overlays stale progress without changing its saved event`() throws {
        let fixture = try ConversationViewModelTestFixture()
        let reviewFixture = try ReviewCoordinatorFixture()
        var run = try reviewFixture.makeRun(conversationID: fixture.viewModel.conversationID)
        run.phase = .inspecting
        let transcript = try ReviewTeamConversationTestFixture.transcript(fixture: fixture, run: run)
        let persistedItem = try #require(fixture.viewModel.state.grouper.items.first)
        let persistedContent = transcript.events.first?.content
        run.phase = .cancelled
        run.generation += 1
        run.error = "Review cancelled, but its saved state could not be updated."

        let entry = try #require(transcript.appKitTranscriptItems(reviewTeamRun: run).first?.hostToolWidgetEntry)

        #expect(entry.content == .collectiveReviewRun(run))
        #expect(entry.isComplete && entry.isInterrupted && !entry.isError)
        #expect(HostToolWidgetSummary.text(for: entry) == "Review cancelled")
        #expect(HostToolWidgetSummary.detail(for: entry) == run.error)
        #expect(fixture.viewModel.state.grouper.items == [persistedItem])
        #expect(transcript.events.first?.content == persistedContent)
    }

    @Test(arguments: [(true, false), (false, false), (false, true)])
    func `a different live run cannot replace the saved progress card`(sameConversation: Bool, sameRun: Bool) throws {
        let fixture = try ConversationViewModelTestFixture()
        let reviewFixture = try ReviewCoordinatorFixture()
        let run = try reviewFixture.makeRun(conversationID: fixture.viewModel.conversationID)
        let transcript = try ReviewTeamConversationTestFixture.transcript(fixture: fixture, run: run)
        var other = try reviewFixture.makeRun(
            conversationID: sameConversation ? run.conversationID : "another-conversation",
            runID: sameRun ? run.id : UUID().uuidString
        )
        other.phase = .cancelled
        let savedItems = fixture.viewModel.state.grouper.items
        let savedEntry = try #require(savedItems.first?.hostToolWidgetEntry)
        let savedEvent = try #require(transcript.events.first)
        let savedJSON = try #require(savedEvent.content)
        // Event encoding uses second-precision ISO-8601 dates; compare the complete persisted payload.
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let savedRun = try decoder.decode(ReviewTeamRun.self, from: Data(savedJSON.utf8))

        #expect(savedRun.id == run.id)
        #expect(savedRun.conversationID == run.conversationID)
        #expect(savedEntry.content == .collectiveReviewRun(savedRun))
        #expect((other.id == run.id) == sameRun)
        #expect((other.conversationID == run.conversationID) == sameConversation)
        #expect(transcript.appKitTranscriptItems(reviewTeamRun: other) == savedItems)
    }

    @Test
    func `saved progress remains authoritative without a live run`() throws {
        let fixture = try ConversationViewModelTestFixture()
        let reviewFixture = try ReviewCoordinatorFixture()
        let run = try reviewFixture.makeRun(conversationID: fixture.viewModel.conversationID)
        let transcript = try ReviewTeamConversationTestFixture.transcript(fixture: fixture, run: run)

        #expect(transcript.appKitTranscriptItems(reviewTeamRun: nil) == fixture.viewModel.state.grouper.items)
    }

    @Test
    func `an interrupted provider turn cannot interrupt the live review team`() throws {
        let fixture = try ConversationViewModelTestFixture()
        let reviewFixture = try ReviewCoordinatorFixture()
        var run = try reviewFixture.makeRun(conversationID: fixture.viewModel.conversationID)
        run.phase = .inspecting
        let transcript = try ReviewTeamConversationTestFixture.transcript(fixture: fixture, run: run, isReviewTeamWorking: true)
        fixture.viewModel.state.lastTurnInterrupted = true

        let entry = try #require(transcript.appKitTranscriptItems(reviewTeamRun: run).first?.hostToolWidgetEntry)

        #expect(!entry.isComplete && !entry.isInterrupted)
        #expect(entry.content == .collectiveReviewRun(run))
        #expect(transcript.appKitTransientRows.showsInterruptedNote == false)
        #expect(fixture.viewModel.state.lastTurnInterrupted)
    }
}

@MainActor
enum ReviewTeamConversationTestFixture {
    static func transcript(
        fixture: ConversationViewModelTestFixture, run: ReviewTeamRun, isReviewTeamWorking: Bool = false
    ) throws -> ChatTranscriptView {
        let content = try ReviewTeamDigest.jsonString(run)
        let event = ConversationEventRecord(
            id: "collective-review-run:\(run.id)", conversationId: run.conversationID,
            type: ConversationEventRecord.collectiveReviewRunType, content: content
        )
        fixture.viewModel.state.grouper.update(events: [event])
        return ChatTranscriptView(
            viewModel: fixture.viewModel, appState: AppState(), events: [event], workingDirectory: nil,
            lastScrollTime: .constant(.distantPast), isFollowing: .constant(true), scrollToBottomRequest: .constant(0),
            isReviewTeamWorking: isReviewTeamWorking
        )
    }

    static func chatView(
        fixture: ConversationViewModelTestFixture,
        isWorking: Bool,
        onCancel: @escaping () -> Void = {}
    ) -> ChatView {
        ChatView(
            viewModel: fixture.viewModel,
            conversation: fixture.conversation,
            composerCapabilities: ComposerCapabilities(supportedPermissionModes: [], supportsMidTurnSteering: true),
            reasoningConfiguration: makeReasoningConfiguration(
                providerOptions: [.init(value: "codex", title: "Codex")],
                modelOptions: [.init(value: "gpt-5.6-sol", title: "GPT-5.6-Sol")],
                effortOptions: [.init(value: "high", title: "High")],
                selectedProvider: "codex", selectedModel: "gpt-5.6-sol", selectedEffort: "high"
            ),
            defaultEnterBehavior: .queue,
            providerID: "codex",
            runtimeStatus: .neutral,
            isReviewTeamWorking: isWorking,
            onCancelReviewTeam: onCancel,
            contextWindowCache: fixture.contextWindowCache,
            workingDirectory: nil,
            projectTrustPrompt: nil,
            isProjectTrustBlocked: false,
            onTrustProject: { _ in },
            onDenyProjectTrust: { _ in },
            loadFileCompletions: { [] },
            loadSkillCompletions: { [] },
            transcriptTypography: TranscriptTypography(),
            appState: AppState()
        )
    }
}
