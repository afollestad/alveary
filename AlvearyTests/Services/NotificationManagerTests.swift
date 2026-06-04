import SwiftData
import XCTest

@testable import Alveary

@MainActor
final class NotificationManagerTests: XCTestCase {
    func testActiveConversationPlaysInAppSoundOnly() throws {
        let service = InMemorySettingsService()
        service.update { $0.notifications.soundName = "Purr" }
        let spy = NotificationSpy()
        let context = try NotificationManagerTestFactory.makeContext()
        let conversation = NotificationManagerTestFactory.seedConversation(in: context.container, threadName: "Thread")
        let manager = NotificationManagerTestFactory.makeManager(
            settingsService: service,
            modelContainer: context.container,
            isAppInForeground: true,
            activeConversationId: conversation.id,
            spy: spy
        )

        manager.handleEvent(.stop(message: nil), conversationId: conversation.id)

        XCTAssertEqual(spy.playedSounds, ["Purr"])
        XCTAssertTrue(spy.postedNotifications.isEmpty)
        XCTAssertFalse(
            NotificationManagerTestFactory.fetchConversation(id: conversation.id, in: context.container)?.isUnread ?? true
        )
        XCTAssertTrue(spy.dismissedConversationIds.isEmpty)
        XCTAssertTrue(spy.badgeCounts.isEmpty)
    }

    func testInactiveConversationPostsNotificationAndMarksUnread() async throws {
        let service = InMemorySettingsService()
        let spy = NotificationSpy()
        let context = try NotificationManagerTestFactory.makeContext()
        let conversation = NotificationManagerTestFactory.seedConversation(in: context.container, threadName: "Thread")
        let manager = NotificationManagerTestFactory.makeManager(
            settingsService: service,
            modelContainer: context.container,
            isAppInForeground: true,
            activeConversationId: "some-other-id",
            spy: spy
        )

        manager.handleEvent(
            .tokens(
                input: 1,
                output: 2,
                cacheRead: 0,
                isError: false,
                stopReason: "end_turn",
                durationMs: 100,
                costUsd: 0.01,
                permissionDenials: []
            ),
            conversationId: conversation.id
        )
        await manager.awaitPendingBadgeUpdate()

        XCTAssertTrue(spy.playedSounds.isEmpty)
        let posted = try XCTUnwrap(spy.postedNotifications.first)
        XCTAssertEqual(posted.context.conversationId, conversation.id)
        XCTAssertEqual(posted.context.threadName, "Thread")
        XCTAssertEqual(posted.message, "Your agent has finished working in \"Thread\"")
        XCTAssertTrue(
            NotificationManagerTestFactory.fetchConversation(id: conversation.id, in: context.container)?.isUnread ?? false
        )
        XCTAssertEqual(spy.badgeCounts.last, 1)
    }

    func testBackgroundAppPostsEvenForActiveConversation() throws {
        let service = InMemorySettingsService()
        let spy = NotificationSpy()
        let context = try NotificationManagerTestFactory.makeContext()
        let conversation = NotificationManagerTestFactory.seedConversation(in: context.container, threadName: "Thread")
        let manager = NotificationManagerTestFactory.makeManager(
            settingsService: service,
            modelContainer: context.container,
            isAppInForeground: false,
            activeConversationId: conversation.id,
            spy: spy
        )

        manager.handleEvent(.stop(message: nil), conversationId: conversation.id)

        XCTAssertEqual(spy.postedNotifications.count, 1)
        XCTAssertTrue(
            NotificationManagerTestFactory.fetchConversation(id: conversation.id, in: context.container)?.isUnread ?? false
        )
    }

    func testCompletionEventAppendsThreadAndConversationWhenMultipleConversations() throws {
        let service = InMemorySettingsService()
        let spy = NotificationSpy()
        let context = try NotificationManagerTestFactory.makeContext()
        let pair = NotificationManagerTestFactory.seedThreadWithConversations(
            in: context.container,
            threadName: "Feature",
            mainTitle: "Main",
            extraTitles: ["Scratch"]
        )
        let manager = NotificationManagerTestFactory.makeManager(
            settingsService: service,
            modelContainer: context.container,
            isAppInForeground: false,
            activeConversationId: nil,
            spy: spy
        )

        manager.handleEvent(.stop(message: nil), conversationId: pair.mainConversationId)

        let posted = try XCTUnwrap(spy.postedNotifications.first)
        XCTAssertEqual(posted.context.threadName, "Feature")
        XCTAssertEqual(posted.context.conversationName, "Main")
        XCTAssertEqual(posted.message, "Your agent has finished working in \"Feature\" / \"Main\"")
    }

    func testPermissionDenialRoutesToPermissionMessage() throws {
        let service = InMemorySettingsService()
        let spy = NotificationSpy()
        let context = try NotificationManagerTestFactory.makeContext()
        let conversation = NotificationManagerTestFactory.seedConversation(in: context.container, threadName: "Thread")
        let manager = NotificationManagerTestFactory.makeManager(
            settingsService: service,
            modelContainer: context.container,
            isAppInForeground: false,
            activeConversationId: nil,
            spy: spy
        )

        manager.handleEvent(
            .tokens(
                input: 1,
                output: 2,
                cacheRead: 0,
                isError: true,
                stopReason: "permission denied",
                durationMs: 100,
                costUsd: 0.01,
                permissionDenials: [PermissionDenialSummary(toolName: "Edit", toolUseId: "tool-1")]
            ),
            conversationId: conversation.id
        )

        XCTAssertEqual(spy.postedNotifications.first?.message, "Your agent needs permission in \"Thread\"")
    }

    func testAskUserQuestionNotificationUsesQuestionSummary() throws {
        let service = InMemorySettingsService()
        let spy = NotificationSpy()
        let context = try NotificationManagerTestFactory.makeContext()
        let conversation = NotificationManagerTestFactory.seedConversation(in: context.container, threadName: "Thread")
        let manager = NotificationManagerTestFactory.makeManager(
            settingsService: service,
            modelContainer: context.container,
            isAppInForeground: false,
            activeConversationId: nil,
            spy: spy
        )

        manager.handleEvent(
            .toolApprovalRequested(
                ToolApprovalRequest(
                    sessionId: "session-1",
                    toolUseId: "toolu_question",
                    toolName: "AskUserQuestion",
                    toolInput: #"{"questions":[{"question":"Pick a release channel","options":[{"label":"Stable","description":"Safe"}]}]}"#
                )
            ),
            conversationId: conversation.id
        )

        XCTAssertEqual(
            spy.postedNotifications.first?.message,
            "Your agent has a question: Pick a release channel in \"Thread\""
        )
    }

    func testToolApprovalNotificationUsesApprovalSummary() throws {
        let service = InMemorySettingsService()
        let spy = NotificationSpy()
        let context = try NotificationManagerTestFactory.makeContext()
        let conversation = NotificationManagerTestFactory.seedConversation(in: context.container, threadName: "Thread")
        let manager = NotificationManagerTestFactory.makeManager(
            settingsService: service,
            modelContainer: context.container,
            isAppInForeground: false,
            activeConversationId: nil,
            spy: spy
        )

        manager.handleEvent(
            .toolApprovalRequested(
                ToolApprovalRequest(
                    sessionId: "session-1",
                    toolUseId: "toolu_bash",
                    toolName: "Bash",
                    toolInput: #"{"command":"swift test"}"#
                )
            ),
            conversationId: conversation.id
        )
        manager.handleEvent(
            .toolApprovalRequested(
                ToolApprovalRequest(
                    sessionId: "session-1",
                    toolUseId: "toolu_write",
                    toolName: "Write",
                    toolInput: #"{"file_path":"/tmp/notes.md"}"#
                )
            ),
            conversationId: conversation.id
        )

        XCTAssertEqual(spy.postedNotifications.map(\.message), [
            "Your agent needs permission: Approve Bash command? swift test in \"Thread\"",
            "Your agent needs permission: Approve writing to a file? /tmp/notes.md in \"Thread\""
        ])
    }

    func testNonTerminalTokensDoNotNotifyDirectly() throws {
        let service = InMemorySettingsService()
        let spy = NotificationSpy()
        let context = try NotificationManagerTestFactory.makeContext()
        let conversation = NotificationManagerTestFactory.seedConversation(in: context.container, threadName: "Thread")
        let manager = NotificationManagerTestFactory.makeManager(
            settingsService: service,
            modelContainer: context.container,
            isAppInForeground: false,
            activeConversationId: nil,
            spy: spy
        )

        manager.handleEvent(
            .tokens(
                input: 0,
                output: 0,
                cacheRead: 0,
                isError: false,
                stopReason: "tool_deferred",
                durationMs: 0,
                costUsd: 0,
                permissionDenials: []
            ),
            conversationId: conversation.id
        )

        XCTAssertTrue(spy.postedNotifications.isEmpty)
        XCTAssertFalse(
            NotificationManagerTestFactory.fetchConversation(id: conversation.id, in: context.container)?.isUnread ?? true
        )
    }

    func testDisabledNotificationsSuppressAllOutputsAndDoesNotMarkUnread() throws {
        let service = InMemorySettingsService()
        service.update { $0.notifications.enabled = false }
        let spy = NotificationSpy()
        let context = try NotificationManagerTestFactory.makeContext()
        let conversation = NotificationManagerTestFactory.seedConversation(in: context.container, threadName: "Thread")
        let manager = NotificationManagerTestFactory.makeManager(
            settingsService: service,
            modelContainer: context.container,
            isAppInForeground: false,
            activeConversationId: nil,
            spy: spy
        )

        manager.handleEvent(.error(message: "Boom"), conversationId: conversation.id)

        XCTAssertTrue(spy.playedSounds.isEmpty)
        XCTAssertTrue(spy.postedNotifications.isEmpty)
        XCTAssertFalse(
            NotificationManagerTestFactory.fetchConversation(id: conversation.id, in: context.container)?.isUnread ?? true
        )
    }

    func testOSNotificationsOffMarksUnreadAndPlaysInAppSound() async throws {
        let service = InMemorySettingsService()
        service.update { $0.notifications.osNotifications = false }
        let spy = NotificationSpy()
        let context = try NotificationManagerTestFactory.makeContext()
        let conversation = NotificationManagerTestFactory.seedConversation(in: context.container, threadName: "Thread")
        let manager = NotificationManagerTestFactory.makeManager(
            settingsService: service,
            modelContainer: context.container,
            isAppInForeground: false,
            activeConversationId: nil,
            spy: spy
        )

        manager.handleEvent(
            .notification(type: "idle_prompt", message: nil),
            conversationId: conversation.id
        )
        await manager.awaitPendingBadgeUpdate()

        XCTAssertEqual(spy.playedSounds, [NotificationSettings.defaultSoundName])
        XCTAssertTrue(spy.postedNotifications.isEmpty)
        XCTAssertTrue(spy.dismissedConversationIds.isEmpty)
        XCTAssertEqual(spy.badgeCounts.last, 1)
        XCTAssertTrue(
            NotificationManagerTestFactory.fetchConversation(id: conversation.id, in: context.container)?.isUnread ?? false
        )
    }

    func testIgnoresNonTerminalEvents() throws {
        let service = InMemorySettingsService()
        let spy = NotificationSpy()
        let context = try NotificationManagerTestFactory.makeContext()
        let conversation = NotificationManagerTestFactory.seedConversation(in: context.container, threadName: "Thread")
        let manager = NotificationManagerTestFactory.makeManager(
            settingsService: service,
            modelContainer: context.container,
            isAppInForeground: true,
            activeConversationId: nil,
            spy: spy
        )

        manager.handleEvent(
            .message(role: "assistant", content: "Working", parentToolUseId: nil),
            conversationId: conversation.id
        )

        XCTAssertTrue(spy.playedSounds.isEmpty)
        XCTAssertTrue(spy.postedNotifications.isEmpty)
        XCTAssertFalse(
            NotificationManagerTestFactory.fetchConversation(id: conversation.id, in: context.container)?.isUnread ?? true
        )
    }

    func testContextCompactionEventsDoNotNotifyOrMarkUnread() throws {
        let service = InMemorySettingsService()
        let spy = NotificationSpy()
        let context = try NotificationManagerTestFactory.makeContext()
        let conversation = NotificationManagerTestFactory.seedConversation(in: context.container, threadName: "Thread")
        let manager = NotificationManagerTestFactory.makeManager(
            settingsService: service,
            modelContainer: context.container,
            isAppInForeground: false,
            activeConversationId: nil,
            spy: spy
        )

        manager.handleEvent(.contextCompactionStarted(id: "compact-1", trigger: "auto"), conversationId: conversation.id)
        manager.handleEvent(.contextCompactionCompleted(id: "compact-1", summary: nil), conversationId: conversation.id)
        manager.handleEvent(.contextCompactionFailed(id: "compact-2", error: "Compact hook failed"), conversationId: conversation.id)

        XCTAssertTrue(spy.playedSounds.isEmpty)
        XCTAssertTrue(spy.postedNotifications.isEmpty)
        XCTAssertFalse(
            NotificationManagerTestFactory.fetchConversation(id: conversation.id, in: context.container)?.isUnread ?? true
        )
    }

    func testMissingConversationFallsBackToBaseMessage() throws {
        let service = InMemorySettingsService()
        let spy = NotificationSpy()
        let context = try NotificationManagerTestFactory.makeContext()
        let manager = NotificationManagerTestFactory.makeManager(
            settingsService: service,
            modelContainer: context.container,
            isAppInForeground: false,
            activeConversationId: nil,
            spy: spy
        )

        manager.handleEvent(.stop(message: nil), conversationId: "missing")

        let posted = try XCTUnwrap(spy.postedNotifications.first)
        XCTAssertEqual(posted.context.conversationId, "missing")
        XCTAssertNil(posted.context.threadId)
        XCTAssertNil(posted.context.threadName)
        XCTAssertNil(posted.context.conversationName)
        XCTAssertEqual(posted.message, "Your agent has finished working")
    }

    func testNotificationRequestUsesConversationIdAsIdentifier() throws {
        let service = InMemorySettingsService()
        let context = try NotificationManagerTestFactory.makeContext()
        let conversation = NotificationManagerTestFactory.seedConversation(in: context.container, threadName: "Thread")
        let manager = DefaultNotificationManager(
            settingsService: service,
            modelContainer: context.container,
            systemNotificationCenter: NotificationCenter()
        )

        let request = manager.makeNotificationRequest(
            context: ConversationNotificationContext(
                conversationId: conversation.id,
                threadId: conversation.thread?.persistentModelID,
                threadName: "Thread",
                conversationName: nil
            ),
            message: "Done",
            playSound: true
        )

        XCTAssertEqual(request.identifier, conversation.id)
        XCTAssertEqual(request.content.title, "Alveary")
        XCTAssertEqual(request.content.userInfo[NotificationUserInfoKey.conversationId] as? String, conversation.id)
    }
}
