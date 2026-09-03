import AgentCLIKit
import Foundation
import XCTest

@testable import Alveary

@MainActor
extension ThreadHostToolRequestParserTests {
    func testSendPromptReadsBothFieldsAndHashesThem() throws {
        let parser = ThreadHostToolRequestParser()
        let arguments: [String: AgentCLIKit.JSONValue] = [
            "thread_id": .string("conv-1"),
            "prompt": .string("Summarize your progress.")
        ]

        let request = try parser.parseSendPrompt(arguments: arguments)

        XCTAssertEqual(request.threadID, "conv-1")
        XCTAssertEqual(request.prompt, "Summarize your progress.")
        XCTAssertEqual(try parser.parseSendPrompt(arguments: arguments).canonicalPayloadHash, request.canonicalPayloadHash)
        // Another thread or another prompt is its own request, never a replay of this one.
        XCTAssertNotEqual(
            try parser.parseSendPrompt(arguments: ["thread_id": .string("conv-2"), "prompt": .string("Summarize your progress.")])
                .canonicalPayloadHash,
            request.canonicalPayloadHash
        )
        XCTAssertNotEqual(
            try parser.parseSendPrompt(arguments: ["thread_id": .string("conv-1"), "prompt": .string("Stop.")])
                .canonicalPayloadHash,
            request.canonicalPayloadHash
        )
    }

    func testSendPromptRequiresBothFieldsAndRefusesUnknownOnes() {
        let parser = ThreadHostToolRequestParser()
        let rejected: [[String: AgentCLIKit.JSONValue]] = [
            ["thread_id": .string("conv-1")],
            ["prompt": .string("Summarize.")],
            ["thread_id": .string("conv-1"), "prompt": .string("   ")],
            ["thread_id": .string("conv-1"), "prompt": .string("Summarize."), "wait": .bool(true)]
        ]
        for arguments in rejected {
            XCTAssertThrowsError(try parser.parseSendPrompt(arguments: arguments), "\(arguments)") { error in
                XCTAssertTrue(error is HostToolRequestError, "\(error)")
            }
        }
    }
}
