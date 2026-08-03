import AgentCLIKit
import Foundation
import SwiftData
import XCTest

@testable import Alveary

@MainActor
extension ScheduledTaskHostToolServiceTests {
    func testTheReadToolRejectsArgumentsAndNamesItself() throws {
        let fixture = try ScheduledTaskHostToolFixture.project()

        let toolName = ScheduledTaskHostToolCatalog.listToolName
        let result = fixture.service.handle(
            context: fixture.agentContext(),
            call: AgentCLIKit.AgentHostToolCall(
                name: toolName,
                arguments: ["filter": .string("anything")]
            )
        )

        XCTAssertTrue(result.isError)
        XCTAssertTrue(result.text.contains("\(toolName) does not accept arguments."), result.text)
    }

    /// The read tool resolves the calling conversation first, so a caller whose conversation
    /// Alveary cannot resolve reads nothing — not even the task list.
    func testReadToolsRequireAUsableSourceConversation() throws {
        let fixture = try ScheduledTaskHostToolFixture.project()
        fixture.thread.archivedAt = Date(timeIntervalSince1970: 10)
        try fixture.modelContext.save()

        let result = fixture.service.handle(
            context: fixture.agentContext(),
            call: AgentCLIKit.AgentHostToolCall(name: ScheduledTaskHostToolCatalog.listToolName)
        )

        XCTAssertTrue(result.isError)
    }
}

extension ScheduledTaskHostToolFixture {
    @discardableResult
    func insertTargetThread(name: String, conversationID: String) throws -> AgentThread {
        let target = AgentThread(name: name, mode: .task)
        target.conversations = [Conversation(id: conversationID, provider: "codex", thread: target)]
        modelContext.insert(target)
        try modelContext.save()
        return target
    }
}
