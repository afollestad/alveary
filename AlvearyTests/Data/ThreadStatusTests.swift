import SwiftData
import XCTest

@testable import Alveary

@MainActor
final class ThreadStatusTests: XCTestCase {
    func testConversationDisplayStatusBusyWinsOverUnread() throws {
        let pair = try seedPair(isUnread: true)
        XCTAssertEqual(pair.conversation.displayStatus(runtime: .busy), .busy)
    }

    func testConversationDisplayStatusWaitingForUserWinsOverUnread() throws {
        let pair = try seedPair(isUnread: true)
        XCTAssertEqual(pair.conversation.displayStatus(runtime: .waitingForUser), .waitingForUser)
    }

    func testConversationDisplayStatusErrorWinsOverUnread() throws {
        let pair = try seedPair(isUnread: true)
        XCTAssertEqual(pair.conversation.displayStatus(runtime: .error), .error)
    }

    func testConversationDisplayStatusUnreadWhenIdle() throws {
        let pair = try seedPair(isUnread: true)
        XCTAssertEqual(pair.conversation.displayStatus(runtime: .idle), .unread)
    }

    func testConversationDisplayStatusStoppedWhenReadAndNeutral() throws {
        let pair = try seedPair(isUnread: false)
        XCTAssertEqual(pair.conversation.displayStatus(runtime: .neutral), .stopped)
    }

    func testConversationDisplayStatusArchivedOverridesAll() throws {
        let pair = try seedPair(isUnread: true, archived: true)
        XCTAssertEqual(pair.conversation.displayStatus(runtime: .busy), .archived)
    }

    func testThreadDisplayStatusBusyOnAnyBusyConversation() throws {
        let seeded = try seedThread(
            conversations: [
                ConversationSpec(isUnread: true, runtime: .neutral),
                ConversationSpec(isUnread: false, runtime: .busy),
                ConversationSpec(isUnread: false, runtime: .neutral)
            ]
        )

        XCTAssertEqual(seeded.thread.displayStatus(runtimeFor: seeded.runtimeLookup(for:)), .busy)
    }

    func testThreadDisplayStatusErrorPreferredOverUnread() throws {
        let seeded = try seedThread(
            conversations: [
                ConversationSpec(isUnread: true, runtime: .neutral),
                ConversationSpec(isUnread: false, runtime: .error)
            ]
        )

        XCTAssertEqual(seeded.thread.displayStatus(runtimeFor: seeded.runtimeLookup(for:)), .error)
    }

    func testThreadDisplayStatusWaitingForUserPreferredOverErrorAndUnread() throws {
        let seeded = try seedThread(
            conversations: [
                ConversationSpec(isUnread: true, runtime: .neutral),
                ConversationSpec(isUnread: false, runtime: .error),
                ConversationSpec(isUnread: false, runtime: .waitingForUser)
            ]
        )

        XCTAssertEqual(seeded.thread.displayStatus(runtimeFor: seeded.runtimeLookup(for:)), .waitingForUser)
    }

    func testThreadDisplayStatusBusyPreferredOverWaitingForUser() throws {
        let seeded = try seedThread(
            conversations: [
                ConversationSpec(isUnread: false, runtime: .waitingForUser),
                ConversationSpec(isUnread: false, runtime: .busy)
            ]
        )

        XCTAssertEqual(seeded.thread.displayStatus(runtimeFor: seeded.runtimeLookup(for:)), .busy)
    }

    func testThreadDisplayStatusUnreadWhenAnyConversationUnread() throws {
        let seeded = try seedThread(
            conversations: [
                ConversationSpec(isUnread: false),
                ConversationSpec(isUnread: true),
                ConversationSpec(isUnread: false)
            ]
        )

        XCTAssertEqual(seeded.thread.displayStatus(runtimeFor: seeded.runtimeLookup(for:)), .unread)
    }

    func testThreadDisplayStatusStoppedWhenAllReadAndNeutral() throws {
        let seeded = try seedThread(
            conversations: [
                ConversationSpec(isUnread: false),
                ConversationSpec(isUnread: false)
            ]
        )

        XCTAssertEqual(seeded.thread.displayStatus(runtimeFor: seeded.runtimeLookup(for:)), .stopped)
    }

    func testThreadDisplayStatusArchivedOverridesUnread() throws {
        let seeded = try seedThread(
            conversations: [ConversationSpec(isUnread: true, runtime: .busy)],
            archivedAt: Date()
        )

        XCTAssertEqual(seeded.thread.displayStatus(runtimeFor: seeded.runtimeLookup(for:)), .archived)
    }

    private struct ConversationSpec {
        var isUnread = false
        var runtime: ActivitySignal = .neutral
    }

    private struct SeededPair {
        let container: ModelContainer
        let conversation: Conversation
    }

    private struct SeededThread {
        let container: ModelContainer
        let thread: AgentThread
        let runtimeByConversationId: [String: ActivitySignal]

        func runtimeLookup(for conversation: Conversation) -> ActivitySignal {
            runtimeByConversationId[conversation.id] ?? .neutral
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
        for (index, spec) in specs.enumerated() {
            let conversation = Conversation(
                isMain: index == 0,
                displayOrder: index,
                isUnread: spec.isUnread,
                thread: thread
            )
            context.insert(conversation)
            runtimeByConversationId[conversation.id] = spec.runtime
        }
        try context.save()
        return SeededThread(
            container: container,
            thread: thread,
            runtimeByConversationId: runtimeByConversationId
        )
    }
}
