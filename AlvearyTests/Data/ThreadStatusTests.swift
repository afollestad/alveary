import SwiftData
import XCTest

@testable import Alveary

@MainActor
final class ThreadStatusTests: XCTestCase {
    func testConversationDisplayStatusBusyWinsOverUnread() throws {
        let pair = try seedPair(isUnread: true)
        XCTAssertEqual(pair.conversation.displayStatus(runtime: .busy, awaitsUserDecision: false), .busy)
    }

    func testConversationDisplayStatusWaitingForUserWinsOverUnread() throws {
        let pair = try seedPair(isUnread: true)
        XCTAssertEqual(pair.conversation.displayStatus(runtime: .waitingForUser, awaitsUserDecision: false), .waitingForUser)
    }

    func testConversationDisplayStatusErrorWinsOverUnread() throws {
        let pair = try seedPair(isUnread: true)
        XCTAssertEqual(pair.conversation.displayStatus(runtime: .error, awaitsUserDecision: false), .error)
    }

    func testConversationDisplayStatusUnreadWhenIdle() throws {
        let pair = try seedPair(isUnread: true)
        XCTAssertEqual(pair.conversation.displayStatus(runtime: .idle, awaitsUserDecision: false), .unread)
    }

    func testConversationDisplayStatusStoppedWhenReadAndNeutral() throws {
        let pair = try seedPair(isUnread: false)
        XCTAssertEqual(pair.conversation.displayStatus(runtime: .neutral, awaitsUserDecision: false), .stopped)
    }

    func testConversationDisplayStatusArchivedOverridesAll() throws {
        let pair = try seedPair(isUnread: true, archived: true)
        XCTAssertEqual(pair.conversation.displayStatus(runtime: .busy, awaitsUserDecision: false), .archived)
    }

    // MARK: - Pending decisions

    /// The green-to-blue upgrade: a queued scheduling proposal marks its conversation unread, and
    /// green already means "done".
    func testConversationDisplayStatusPendingDecisionWinsOverUnread() throws {
        let pair = try seedPair(isUnread: true)
        XCTAssertEqual(pair.conversation.displayStatus(runtime: .idle, awaitsUserDecision: true), .waitingForUser)
    }

    func testConversationDisplayStatusPendingDecisionWinsOverError() throws {
        let pair = try seedPair(isUnread: false)
        XCTAssertEqual(pair.conversation.displayStatus(runtime: .error, awaitsUserDecision: true), .waitingForUser)
    }

    func testConversationDisplayStatusBusyWinsOverPendingDecision() throws {
        let pair = try seedPair(isUnread: false)
        XCTAssertEqual(pair.conversation.displayStatus(runtime: .busy, awaitsUserDecision: true), .busy)
    }

    func testConversationDisplayStatusArchivedOverridesPendingDecision() throws {
        let pair = try seedPair(isUnread: false, archived: true)
        XCTAssertEqual(pair.conversation.displayStatus(runtime: .neutral, awaitsUserDecision: true), .archived)
    }

    func testThreadDisplayStatusWaitingOnPendingDecisionInAnyConversation() throws {
        let seeded = try seedThread(
            conversations: [
                ConversationSpec(isUnread: false, runtime: .neutral),
                ConversationSpec(isUnread: false, runtime: .neutral, awaitsDecision: true)
            ]
        )

        XCTAssertEqual(
            seeded.thread.displayStatus(
                runtimeFor: seeded.runtimeLookup(for:),
                awaitsUserDecisionFor: seeded.decisionLookup(for:)
            ),
            .waitingForUser
        )
    }

    func testThreadDisplayStatusBusyPreferredOverPendingDecision() throws {
        let seeded = try seedThread(
            conversations: [
                ConversationSpec(isUnread: false, runtime: .neutral, awaitsDecision: true),
                ConversationSpec(isUnread: false, runtime: .busy)
            ]
        )

        XCTAssertEqual(
            seeded.thread.displayStatus(
                runtimeFor: seeded.runtimeLookup(for:),
                awaitsUserDecisionFor: seeded.decisionLookup(for:)
            ),
            .busy
        )
    }

    func testThreadDisplayStatusPendingDecisionPreferredOverErrorAndUnread() throws {
        let seeded = try seedThread(
            conversations: [
                ConversationSpec(isUnread: true, runtime: .neutral),
                ConversationSpec(isUnread: false, runtime: .error),
                ConversationSpec(isUnread: false, runtime: .neutral, awaitsDecision: true)
            ]
        )

        XCTAssertEqual(
            seeded.thread.displayStatus(
                runtimeFor: seeded.runtimeLookup(for:),
                awaitsUserDecisionFor: seeded.decisionLookup(for:)
            ),
            .waitingForUser
        )
    }

    func testThreadDisplayStatusBusyOnAnyBusyConversation() throws {
        let seeded = try seedThread(
            conversations: [
                ConversationSpec(isUnread: true, runtime: .neutral),
                ConversationSpec(isUnread: false, runtime: .busy),
                ConversationSpec(isUnread: false, runtime: .neutral)
            ]
        )

        XCTAssertEqual(seeded.thread.displayStatus(
            runtimeFor: seeded.runtimeLookup(for:),
            awaitsUserDecisionFor: seeded.decisionLookup(for:)
        ), .busy)
    }

    func testThreadDisplayStatusErrorPreferredOverUnread() throws {
        let seeded = try seedThread(
            conversations: [
                ConversationSpec(isUnread: true, runtime: .neutral),
                ConversationSpec(isUnread: false, runtime: .error)
            ]
        )

        XCTAssertEqual(seeded.thread.displayStatus(
            runtimeFor: seeded.runtimeLookup(for:),
            awaitsUserDecisionFor: seeded.decisionLookup(for:)
        ), .error)
    }

    func testThreadDisplayStatusWaitingForUserPreferredOverErrorAndUnread() throws {
        let seeded = try seedThread(
            conversations: [
                ConversationSpec(isUnread: true, runtime: .neutral),
                ConversationSpec(isUnread: false, runtime: .error),
                ConversationSpec(isUnread: false, runtime: .waitingForUser)
            ]
        )

        XCTAssertEqual(seeded.thread.displayStatus(
            runtimeFor: seeded.runtimeLookup(for:),
            awaitsUserDecisionFor: seeded.decisionLookup(for:)
        ), .waitingForUser)
    }

    func testThreadDisplayStatusBusyPreferredOverWaitingForUser() throws {
        let seeded = try seedThread(
            conversations: [
                ConversationSpec(isUnread: false, runtime: .waitingForUser),
                ConversationSpec(isUnread: false, runtime: .busy)
            ]
        )

        XCTAssertEqual(seeded.thread.displayStatus(
            runtimeFor: seeded.runtimeLookup(for:),
            awaitsUserDecisionFor: seeded.decisionLookup(for:)
        ), .busy)
    }

    func testThreadDisplayStatusUnreadWhenAnyConversationUnread() throws {
        let seeded = try seedThread(
            conversations: [
                ConversationSpec(isUnread: false),
                ConversationSpec(isUnread: true),
                ConversationSpec(isUnread: false)
            ]
        )

        XCTAssertEqual(seeded.thread.displayStatus(
            runtimeFor: seeded.runtimeLookup(for:),
            awaitsUserDecisionFor: seeded.decisionLookup(for:)
        ), .unread)
    }

    func testThreadDisplayStatusStoppedWhenAllReadAndNeutral() throws {
        let seeded = try seedThread(
            conversations: [
                ConversationSpec(isUnread: false),
                ConversationSpec(isUnread: false)
            ]
        )

        XCTAssertEqual(seeded.thread.displayStatus(
            runtimeFor: seeded.runtimeLookup(for:),
            awaitsUserDecisionFor: seeded.decisionLookup(for:)
        ), .stopped)
    }

    func testThreadDisplayStatusArchivedOverridesUnread() throws {
        let seeded = try seedThread(
            conversations: [ConversationSpec(isUnread: true, runtime: .busy)],
            archivedAt: Date()
        )

        XCTAssertEqual(seeded.thread.displayStatus(
            runtimeFor: seeded.runtimeLookup(for:),
            awaitsUserDecisionFor: seeded.decisionLookup(for:)
        ), .archived)
    }

    private struct ConversationSpec {
        var isUnread = false
        var runtime: ActivitySignal = .neutral
        var awaitsDecision = false
    }

    private struct SeededPair {
        let container: ModelContainer
        let conversation: Conversation
    }

    private struct SeededThread {
        let container: ModelContainer
        let thread: AgentThread
        let runtimeByConversationId: [String: ActivitySignal]
        let decisionByConversationId: [String: Bool]

        func runtimeLookup(for conversation: Conversation) -> ActivitySignal {
            runtimeByConversationId[conversation.id] ?? .neutral
        }

        func decisionLookup(for conversation: Conversation) -> Bool {
            decisionByConversationId[conversation.id] ?? false
        }
    }

    private func makeContainer() throws -> ModelContainer {
        try ModelContainer(
            for: Project.self,
            AgentThread.self,
            Conversation.self,
            ConversationEventRecord.self,
            ScheduledTask.self,
            ScheduledTaskRun.self,
            ScheduledTaskProposal.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }

    private func seedPair(isUnread: Bool, archived: Bool = false) throws -> SeededPair {
        let container = try makeContainer()
        let context = ModelContext(container)
        let thread = AgentThread(name: "Thread", hasCustomName: true, archivedAt: archived ? Date() : nil)
        let conversation = Conversation(isUnread: isUnread, thread: thread)
        context.insert(thread)
        context.insert(conversation)
        try context.save()
        return SeededPair(container: container, conversation: conversation)
    }

    private func seedThread(conversations specs: [ConversationSpec], archivedAt: Date? = nil) throws -> SeededThread {
        let container = try makeContainer()
        let context = ModelContext(container)
        let thread = AgentThread(name: "T", hasCustomName: true, archivedAt: archivedAt)
        context.insert(thread)
        var runtimeByConversationId: [String: ActivitySignal] = [:]
        var decisionByConversationId: [String: Bool] = [:]
        for (index, spec) in specs.enumerated() {
            let conversation = Conversation(
                isMain: index == 0,
                displayOrder: index,
                isUnread: spec.isUnread,
                thread: thread
            )
            context.insert(conversation)
            runtimeByConversationId[conversation.id] = spec.runtime
            decisionByConversationId[conversation.id] = spec.awaitsDecision
        }
        try context.save()
        return SeededThread(
            container: container,
            thread: thread,
            runtimeByConversationId: runtimeByConversationId,
            decisionByConversationId: decisionByConversationId
        )
    }
}
