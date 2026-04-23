import XCTest

@testable import Alveary

extension ClaudeHookServerTests {
    func testHookEndpointDefersAskUserQuestion() async throws {
        let server = DefaultClaudeHookServer(supportDirectory: temporarySupportDirectory())
        let launchConfig = await server.prepareLaunch(permissionMode: "default", conversationId: "conversation-1")
        let launch = try XCTUnwrap(launchConfig)
        let token = try XCTUnwrap(launch.environment["ALVEARY_HOOK_TOKEN"])

        let response = await server.handle(
            request(
                token: token,
                toolName: "AskUserQuestion",
                toolInput: [
                    "questions": [
                        [
                            "question": "Pick one",
                            "options": [["label": "A", "description": "First"]]
                        ]
                    ]
                ]
            )
        )

        XCTAssertEqual(try hookDecision(from: response), "defer")
    }

    func testHookEndpointAllowForAskUserQuestionUsesRecordedUpdatedInput() async throws {
        let server = DefaultClaudeHookServer(supportDirectory: temporarySupportDirectory())
        let launchConfig = await server.prepareLaunch(permissionMode: "default", conversationId: "conversation-1")
        let launch = try XCTUnwrap(launchConfig)
        let token = try XCTUnwrap(launch.environment["ALVEARY_HOOK_TOKEN"])
        let key = ClaudeToolApprovalKey(sessionId: "session-123", toolUseId: "tool-1")
        await server.recordDecision(
            ClaudeToolApprovalResolution(
                decision: .allow,
                updatedInput: #"{"answers":{"Pick one":"A"},"questions":[{"options":[{"description":"First","label":"A"}],"question":"Pick one"}]}"#
            ),
            for: key
        )

        let response = await server.handle(
            request(
                token: token,
                toolName: "AskUserQuestion",
                toolInput: [
                    "questions": [
                        [
                            "question": "Pick one",
                            "options": [["label": "A", "description": "First"]]
                        ]
                    ]
                ]
            )
        )

        XCTAssertEqual(try hookDecision(from: response), "allow")
        XCTAssertEqual(
            try updatedInput(from: response) as? NSDictionary,
            [
                "answers": ["Pick one": "A"],
                "questions": [
                    [
                        "question": "Pick one",
                        "options": [["label": "A", "description": "First"]]
                    ]
                ]
            ] as NSDictionary
        )
    }
}
