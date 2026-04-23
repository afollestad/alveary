import Foundation

@testable import Alveary

func collectedEvents(from stream: AsyncStream<ConversationEvent>) async -> [ConversationEvent] {
    var events: [ConversationEvent] = []
    for await event in stream {
        events.append(event)
    }
    return events
}
