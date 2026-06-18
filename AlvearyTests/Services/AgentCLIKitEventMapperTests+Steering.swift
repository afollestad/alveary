import AgentCLIKit
import XCTest

@testable import Alveary

extension AgentCLIKitEventMapperTests {
    func testMapsSteeringTaggedUserMessageToSteeredConversation() {
        let events = AgentCLIKitEventMapper().conversationEvents(from: envelope(.message(AgentMessageEvent(
            role: .user,
            text: "Focus on tests",
            metadata: [
                AgentSteeringMetadata.isSteering: .bool(true),
                AgentSteeringMetadata.inputId: .string("local-user-1"),
                AgentSteeringMetadata.signal: .string(AgentSteeringMetadata.signalRuntimeInputAccepted)
            ]
        ))))

        XCTAssertEqual(events, [.steeredConversation(inputID: "local-user-1")])
    }

    func testUntaggedUserMessageRemainsNormalMessageEvent() {
        let events = AgentCLIKitEventMapper().conversationEvents(from: envelope(.message(AgentMessageEvent(
            role: .user,
            text: "Normal replay"
        ))))

        XCTAssertEqual(events, [.message(role: "user", content: "Normal replay", parentToolUseId: nil)])
    }

    func testSteeringUserMessageWithUnknownSignalRemainsNormalMessageEvent() {
        let events = AgentCLIKitEventMapper().conversationEvents(from: envelope(.message(AgentMessageEvent(
            role: .user,
            text: "Unknown signal",
            metadata: [
                AgentSteeringMetadata.isSteering: .bool(true),
                AgentSteeringMetadata.inputId: .string("local-user-1"),
                AgentSteeringMetadata.signal: .string("unknown")
            ]
        ))))

        XCTAssertEqual(events, [.message(role: "user", content: "Unknown signal", parentToolUseId: nil)])
    }
}
