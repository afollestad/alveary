import XCTest

@testable import Alveary

final class EventBufferTests: XCTestCase {
    func testSubscriberReceivesReplayAndLiveEvents() async {
        let buffer = EventBuffer()
        buffer.push(.message(role: "assistant", content: "first", parentToolUseId: nil))

        let subscription = buffer.subscribe(afterIndex: 0)
        var iterator = subscription.stream.makeAsyncIterator()

        let replayedEvent = await iterator.next()
        buffer.push(.message(role: "assistant", content: "second", parentToolUseId: nil))
        let liveEvent = await iterator.next()

        XCTAssertEqual(replayedEvent, .message(role: "assistant", content: "first", parentToolUseId: nil))
        XCTAssertEqual(liveEvent, .message(role: "assistant", content: "second", parentToolUseId: nil))
    }

    func testLateSubscriberReplaysThenFinishesAfterFinishAll() async {
        let buffer = EventBuffer()
        buffer.push(.sessionInit(sessionId: "session-1"))
        buffer.finishAll()

        let subscription = buffer.subscribe(afterIndex: 0)
        var iterator = subscription.stream.makeAsyncIterator()

        let replayedEvent = await iterator.next()
        let finishedEvent = await iterator.next()

        XCTAssertEqual(replayedEvent, .sessionInit(sessionId: "session-1"))
        XCTAssertNil(finishedEvent)
    }

    func testReplayCursorStillWorksAfterPersistedPrefixEviction() async {
        let buffer = EventBuffer()

        for index in 0..<5200 {
            buffer.push(.message(role: "assistant", content: "\(index)", parentToolUseId: nil))
        }
        buffer.markPersisted(upTo: 5200)

        for index in 5200..<5300 {
            buffer.push(.message(role: "assistant", content: "\(index)", parentToolUseId: nil))
        }

        let subscription = buffer.subscribe(afterIndex: 5200)
        buffer.finishAll()
        let replayedEvents = await collectAll(from: subscription.stream)

        let expected = (5200..<5300).map {
            ConversationEvent.message(role: "assistant", content: "\($0)", parentToolUseId: nil)
        }
        XCTAssertEqual(buffer.retainedCount, 5043)
        XCTAssertEqual(replayedEvents, expected)
    }

    private func collectAll(from stream: AsyncStream<ConversationEvent>) async -> [ConversationEvent] {
        var collected: [ConversationEvent] = []
        for await event in stream {
            collected.append(event)
        }
        return collected
    }
}
