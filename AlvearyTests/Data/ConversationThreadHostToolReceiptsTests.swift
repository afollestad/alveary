import Foundation
import SwiftData
import XCTest

@testable import Alveary

@MainActor
final class ConversationThreadHostToolReceiptsTests: XCTestCase {
    private let processToken = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE") ?? UUID()
    private let otherProcessToken = UUID(uuidString: "11111111-2222-3333-4444-555555555555") ?? UUID()
    private let now = Date(timeIntervalSince1970: 1_000_000)

    func testARecordedReceiptIsFoundByItsKey() throws {
        let conversation = try makeConversation()

        try conversation.recordThreadHostToolReceipt(makeReceipt(key: "alpha"))

        let found = try conversation.threadHostToolReceipt(
            matching: "alpha",
            currentProcessToken: processToken,
            at: now
        )
        XCTAssertEqual(found?.threadID, "thread-alpha")
        XCTAssertNil(
            try conversation.threadHostToolReceipt(
                matching: "beta",
                currentProcessToken: processToken,
                at: now
            )
        )
    }

    func testRecordingTheSameKeyTwiceKeepsTheFirstResult() throws {
        let conversation = try makeConversation()

        try conversation.recordThreadHostToolReceipt(makeReceipt(key: "alpha", threadID: "thread-first"))
        try conversation.recordThreadHostToolReceipt(makeReceipt(key: "alpha", threadID: "thread-second"))

        let found = try conversation.threadHostToolReceipt(
            matching: "alpha",
            currentProcessToken: processToken,
            at: now
        )
        XCTAssertEqual(found?.threadID, "thread-first")
    }

    /// A receipt cannot survive a provider restart, or a genuinely new call reusing a request ID
    /// would replay a stale result.
    func testReceiptsFromAnotherProcessAreDropped() throws {
        let conversation = try makeConversation()
        try conversation.recordThreadHostToolReceipt(makeReceipt(key: "alpha"))

        let found = try conversation.threadHostToolReceipt(
            matching: "alpha",
            currentProcessToken: otherProcessToken,
            at: now
        )

        XCTAssertNil(found)
        XCTAssertNil(conversation.threadHostToolReceiptsJSON)
    }

    func testReceiptsPastTheRetentionWindowAreDropped() throws {
        let conversation = try makeConversation()
        try conversation.recordThreadHostToolReceipt(makeReceipt(key: "alpha"))

        let expired = now.addingTimeInterval(Conversation.threadHostToolReceiptRetention + 1)
        let found = try conversation.threadHostToolReceipt(
            matching: "alpha",
            currentProcessToken: processToken,
            at: expired
        )

        XCTAssertNil(found)
    }

    func testTheLedgerIsCappedAndKeepsTheNewestEntries() throws {
        let conversation = try makeConversation()
        let overflow = Conversation.maximumThreadHostToolReceiptCount + 10

        for index in 0..<overflow {
            try conversation.recordThreadHostToolReceipt(makeReceipt(key: "key-\(index)"))
        }

        XCTAssertNil(
            try conversation.threadHostToolReceipt(
                matching: "key-0",
                currentProcessToken: processToken,
                at: now
            )
        )
        XCTAssertNotNil(
            try conversation.threadHostToolReceipt(
                matching: "key-\(overflow - 1)",
                currentProcessToken: processToken,
                at: now
            )
        )
    }

    func testAnEmptyLedgerClearsTheStoredColumn() throws {
        let conversation = try makeConversation()
        try conversation.recordThreadHostToolReceipt(makeReceipt(key: "alpha"))
        XCTAssertNotNil(conversation.threadHostToolReceiptsJSON)

        _ = try conversation.threadHostToolReceipt(
            matching: "alpha",
            currentProcessToken: otherProcessToken,
            at: now
        )

        XCTAssertNil(conversation.threadHostToolReceiptsJSON)
    }

    /// The two ledgers are independent columns; one must not disturb the other.
    func testTheThreadLedgerIsSeparateFromTheSchedulingLedger() throws {
        let conversation = try makeConversation()

        try conversation.recordThreadHostToolReceipt(makeReceipt(key: "alpha"))

        XCTAssertNotNil(conversation.threadHostToolReceiptsJSON)
        XCTAssertNil(conversation.scheduledTaskProposalReceiptsJSON)
    }

    /// Receipts written before `send_prompt_to_thread` existed carry no status, and must keep
    /// decoding as the `create_thread` results they were.
    func testAReceiptWithoutAStatusStillDecodes() throws {
        let conversation = try makeConversation()
        conversation.threadHostToolReceiptsJSON = """
        [{"createdAt":"2001-01-12T13:46:40Z","deduplicationKey":"alpha","message":"Created the thread.",\
        "sourceProcessToken":"\(processToken.uuidString.lowercased())","threadID":"thread-alpha"}]
        """

        let found = try conversation.threadHostToolReceipt(
            matching: "alpha",
            currentProcessToken: processToken,
            at: now
        )

        XCTAssertEqual(found?.threadID, "thread-alpha")
        XCTAssertNil(found?.status)
    }

    func testAReceiptStatusRoundTrips() throws {
        let conversation = try makeConversation()
        var receipt = makeReceipt(key: "alpha")
        receipt.status = "queued"

        try conversation.recordThreadHostToolReceipt(receipt)

        let found = try conversation.threadHostToolReceipt(
            matching: "alpha",
            currentProcessToken: processToken,
            at: now
        )
        XCTAssertEqual(found?.status, "queued")
    }

    private func makeReceipt(key: String, threadID: String = "thread-alpha") -> ThreadHostToolReceipt {
        ThreadHostToolReceipt(
            deduplicationKey: key,
            threadID: threadID,
            name: "Release checklist",
            message: "Created the thread.",
            sourceProcessToken: processToken.uuidString.lowercased(),
            createdAt: now
        )
    }

    private func makeConversation() throws -> Conversation {
        let container = try ModelContainer(
            for: Project.self,
            AgentThread.self,
            Conversation.self,
            ConversationEventRecord.self,
            ScheduledTask.self,
            ScheduledTaskRun.self,
            ScheduledTaskProposal.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let conversation = Conversation(id: "source-conversation", provider: "codex")
        context.insert(conversation)
        try context.save()
        return conversation
    }
}
