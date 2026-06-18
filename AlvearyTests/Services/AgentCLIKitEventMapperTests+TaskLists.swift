import AgentCLIKit
import XCTest

@testable import Alveary

extension AgentCLIKitEventMapperTests {
    func testMapsTaskListMetadataToTaskListSnapshot() {
        let events = AgentCLIKitEventMapper().conversationEvents(from: envelope(.task(AgentTaskEvent(
            id: "codex-plan-turn-1",
            phase: .progress,
            description: "Plan updated",
            taskType: "plan",
            status: "updated",
            metadata: [
                "todos": .array([
                    .object([
                        "id": .string("codex-plan-turn-1-0"),
                        "subject": .string("Inspect the current state"),
                        "status": .string("completed")
                    ]),
                    .object([
                        "id": .string("codex-plan-turn-1-1"),
                        "subject": .string("Implement the bridge fix"),
                        "activeForm": .string("Implementing the bridge fix"),
                        "status": .string("inProgress")
                    ]),
                    .object([
                        "id": .string("codex-plan-turn-1-2"),
                        "subject": .string("Verify the result"),
                        "status": .string("pending")
                    ])
                ])
            ]
        ))))

        XCTAssertEqual(events, [
            .taskListSnapshot(ConversationTaskListSnapshot(
                id: "tasks-codex-plan-turn-1",
                items: [
                    ConversationTaskListItem(
                        id: "codex-plan-turn-1-0",
                        content: "Inspect the current state",
                        status: .completed
                    ),
                    ConversationTaskListItem(
                        id: "codex-plan-turn-1-1",
                        content: "Implement the bridge fix",
                        activeForm: "Implementing the bridge fix",
                        status: .inProgress
                    ),
                    ConversationTaskListItem(
                        id: "codex-plan-turn-1-2",
                        content: "Verify the result",
                        status: .pending
                    )
                ]
            ))
        ])
    }

    func testDropsCodexPlanDeltaWithoutSnapshot() {
        let events = AgentCLIKitEventMapper().conversationEvents(from: envelope(.task(AgentTaskEvent(
            id: "plan-delta-1",
            phase: .progress,
            description: "Implement",
            taskType: "plan",
            status: "streaming",
            metadata: ["codex_plan_delta": .string("Implement")]
        ))))

        XCTAssertEqual(events, [])
    }
}
