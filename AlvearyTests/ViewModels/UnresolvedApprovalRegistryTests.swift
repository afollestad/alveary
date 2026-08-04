import Foundation
import SwiftData
import XCTest

@testable import Alveary

@MainActor
final class UnresolvedApprovalRegistryTests: XCTestCase {
    func testNeverAnsweredApprovalSurfacesItsConversation() throws {
        let fixture = try Fixture()
        fixture.insertApproval(conversationID: "conversation-1", toolUseID: "tool-1")

        fixture.registry.start()

        XCTAssertEqual(fixture.registry.conversationIDs, ["conversation-1"])
    }

    func testResolvedStatusesDoNotSurface() throws {
        for status in [ToolApprovalStatus.approved, .denied, .superseded, .approvedForSessionExact] {
            let fixture = try Fixture()
            fixture.insertApproval(conversationID: "conversation-1", toolUseID: "tool-1", status: status)

            fixture.registry.start()

            XCTAssertEqual(fixture.registry.conversationIDs, [], "\(status) should not count as waiting")
        }
    }

    /// The provider can run the tool without Alveary ever stamping the row. Counting those would
    /// leave the thread blue forever.
    func testApprovalWhoseToolAlreadyReturnedDoesNotSurface() throws {
        let fixture = try Fixture()
        fixture.insertApproval(conversationID: "conversation-1", toolUseID: "tool-1")
        fixture.insertToolResult(conversationID: "conversation-1", toolUseID: "tool-1", offset: 10)

        fixture.registry.start()

        XCTAssertEqual(fixture.registry.conversationIDs, [])
    }

    /// A `tool_deferred` stop is the turn parking on this very approval, so it stays actionable.
    func testDeferredStopKeepsTheApprovalActionable() throws {
        let fixture = try Fixture()
        fixture.insertApproval(conversationID: "conversation-1", toolUseID: "tool-1")
        fixture.insertTokens(conversationID: "conversation-1", stopReason: "tool_deferred", offset: 10)

        fixture.registry.start()

        XCTAssertEqual(fixture.registry.conversationIDs, ["conversation-1"])
    }

    func testLaterTerminalTokensRetireTheApproval() throws {
        let fixture = try Fixture()
        fixture.insertApproval(conversationID: "conversation-1", toolUseID: "tool-1")
        fixture.insertTokens(conversationID: "conversation-1", stopReason: "end_turn", offset: 10)

        fixture.registry.start()

        XCTAssertEqual(fixture.registry.conversationIDs, [])
    }

    /// `reload()` stops probing a conversation at its first still-open row, so a conversation whose
    /// *first* row is already retired must still surface on a later one.
    func testConversationSurfacesWhenOnlyALaterRowIsStillOpen() throws {
        let fixture = try Fixture()
        fixture.insertApproval(conversationID: "conversation-1", toolUseID: "tool-1")
        fixture.insertToolResult(conversationID: "conversation-1", toolUseID: "tool-1", offset: 1)
        fixture.insertApproval(conversationID: "conversation-1", toolUseID: "tool-2")

        fixture.registry.start()

        XCTAssertEqual(fixture.registry.conversationIDs, ["conversation-1"])
    }

    func testEveryConversationWithAnOpenRowSurfaces() throws {
        let fixture = try Fixture()
        fixture.insertApproval(conversationID: "conversation-1", toolUseID: "tool-1")
        fixture.insertApproval(conversationID: "conversation-2", toolUseID: "tool-2")
        fixture.insertApproval(conversationID: "conversation-3", toolUseID: "tool-3")
        fixture.insertToolResult(conversationID: "conversation-2", toolUseID: "tool-2", offset: 1)

        fixture.registry.start()

        XCTAssertEqual(fixture.registry.conversationIDs, ["conversation-1", "conversation-3"])
    }

    func testWaitingSignalPicksUpANewlyPersistedApproval() async throws {
        let fixture = try Fixture()
        fixture.registry.start()
        XCTAssertEqual(fixture.registry.conversationIDs, [])

        fixture.insertApproval(conversationID: "conversation-1", toolUseID: "tool-1")
        await fixture.postStatusChange(conversationID: "conversation-1", signal: .waitingForUser)

        XCTAssertEqual(fixture.registry.conversationIDs, ["conversation-1"])
    }

    /// `.agentStatusChanged` fires on every busy/idle flip of every streaming turn. An untracked
    /// conversation reporting anything but waiting cannot have changed this set, so it must not
    /// trigger a reload.
    func testUntrackedNonWaitingSignalDoesNotReload() async throws {
        let fixture = try Fixture()
        fixture.registry.start()

        fixture.insertApproval(conversationID: "conversation-1", toolUseID: "tool-1")
        await fixture.postStatusChange(conversationID: "conversation-2", signal: .busy)

        XCTAssertEqual(fixture.registry.conversationIDs, [])
    }

    func testResolvingATrackedConversationClearsIt() async throws {
        let fixture = try Fixture()
        let record = fixture.insertApproval(conversationID: "conversation-1", toolUseID: "tool-1")
        fixture.registry.start()
        XCTAssertEqual(fixture.registry.conversationIDs, ["conversation-1"])

        record.toolApprovalStatus = ToolApprovalStatus.approved.rawValue
        await fixture.postStatusChange(conversationID: "conversation-1", signal: .busy)

        XCTAssertEqual(fixture.registry.conversationIDs, [])
    }

    /// Nothing loads until `start()`, so a notification arriving during launch cannot pull the
    /// event-store scan back onto the launch path.
    func testNoLoadBeforeStart() async throws {
        let fixture = try Fixture()
        fixture.insertApproval(conversationID: "conversation-1", toolUseID: "tool-1")

        await fixture.postStatusChange(conversationID: "conversation-1", signal: .waitingForUser)

        XCTAssertEqual(fixture.registry.conversationIDs, [])
    }

    /// Nested types do not inherit the suite's actor annotation, and the registry is main-actor.
    @MainActor
    private struct Fixture {
        let container: ModelContainer
        let context: ModelContext
        let notificationCenter: NotificationCenter
        let registry: UnresolvedApprovalRegistry
        private let baseDate = Date(timeIntervalSince1970: 1_000)

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
            notificationCenter = NotificationCenter()
            registry = UnresolvedApprovalRegistry(
                modelContext: context,
                notificationCenter: notificationCenter
            )
        }

        @discardableResult
        func insertApproval(
            conversationID: String,
            toolUseID: String,
            status: ToolApprovalStatus? = nil
        ) -> ConversationEventRecord {
            let record = ConversationEventRecord(
                conversationId: conversationID,
                type: ConversationEventRecord.toolApprovalType,
                toolId: toolUseID,
                toolName: "Bash",
                toolApprovalStatus: status?.rawValue,
                timestamp: baseDate
            )
            context.insert(record)
            try? context.save()
            return record
        }

        func insertToolResult(conversationID: String, toolUseID: String, offset: TimeInterval) {
            let record = ConversationEventRecord(
                conversationId: conversationID,
                type: ConversationEventRecord.toolResultType,
                toolId: toolUseID,
                timestamp: baseDate.addingTimeInterval(offset)
            )
            context.insert(record)
            try? context.save()
        }

        func insertTokens(conversationID: String, stopReason: String, offset: TimeInterval) {
            let record = ConversationEventRecord(
                conversationId: conversationID,
                type: ConversationEventRecord.tokensType,
                stopReason: stopReason,
                timestamp: baseDate.addingTimeInterval(offset)
            )
            context.insert(record)
            try? context.save()
        }

        /// The registry observes through an `AsyncSequence`, so the post has to be handed to the
        /// runtime before the assertion runs.
        func postStatusChange(conversationID: String, signal: ActivitySignal) async {
            notificationCenter.post(
                name: .agentStatusChanged,
                object: nil,
                userInfo: [
                    AgentStatusChangedKey.conversationID: conversationID,
                    AgentStatusChangedKey.signal: signal
                ]
            )
            for _ in 0..<10 {
                await Task.yield()
            }
        }
    }
}
