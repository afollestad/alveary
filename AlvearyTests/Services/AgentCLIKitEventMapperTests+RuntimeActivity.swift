import AgentCLIKit
import XCTest

@testable import Alveary

extension AgentCLIKitEventMapperTests {
    func testMapsGenericHarnessRuntimeActivity() {
        let mapper = AgentCLIKitEventMapper()
        let active = mapper.conversationEvents(from: runtimeEnvelope(.activity(AgentActivityEvent(
            state: .active,
            turnId: "turn-1"
        ))))
        let idle = mapper.conversationEvents(from: runtimeEnvelope(.activity(AgentActivityEvent(
            state: .idle,
            turnId: "turn-1",
            metadata: ["codex_turn_status": .string("failed")]
        ))))

        XCTAssertEqual(active, [
            .runtimeActivity(state: .active, turnId: "turn-1", outcome: .unknown)
        ])
        XCTAssertEqual(idle, [
            .runtimeActivity(state: .idle, turnId: "turn-1", outcome: .completed)
        ])
    }

    func testMapsCodexRuntimeActivityOutcomes() {
        let mapper = AgentCLIKitEventMapper()

        XCTAssertEqual(
            mapper.conversationEvents(from: runtimeEnvelope(
                .activity(AgentActivityEvent(
                    state: .idle,
                    turnId: "turn-1",
                    metadata: ["codex_turn_status": .string("completed")]
                )),
                harnessId: .codex
            )),
            [.runtimeActivity(state: .idle, turnId: "turn-1", outcome: .completed)]
        )
        XCTAssertEqual(
            mapper.conversationEvents(from: runtimeEnvelope(
                .activity(AgentActivityEvent(
                    state: .idle,
                    turnId: "turn-2",
                    metadata: ["codex_turn_status": .string("failed")]
                )),
                harnessId: .codex
            )),
            [.runtimeActivity(state: .idle, turnId: "turn-2", outcome: .failed(message: "Codex turn failed."))]
        )
        XCTAssertEqual(
            mapper.conversationEvents(from: runtimeEnvelope(
                .activity(AgentActivityEvent(
                    state: .idle,
                    turnId: "turn-3",
                    metadata: ["codex_turn_status": .string("canceled")]
                )),
                harnessId: .codex
            )),
            [.runtimeActivity(state: .idle, turnId: "turn-3", outcome: .interrupted)]
        )
        XCTAssertEqual(
            mapper.conversationEvents(from: runtimeEnvelope(
                .activity(AgentActivityEvent(
                    state: .idle,
                    metadata: ["codex_status": .string("systemError")]
                )),
                harnessId: .codex
            )),
            [
                .runtimeActivity(
                    state: .idle,
                    turnId: nil,
                    outcome: .failed(message: "Codex App Server reported a thread system error.")
                )
            ]
        )
    }

    func testPromotesCodexSystemErrorWarningDiagnosticToError() {
        let events = AgentCLIKitEventMapper().conversationEvents(from: runtimeEnvelope(
            .diagnostic(AgentDiagnosticEvent(
                code: .codexAppServerResponseFailure,
                severity: .warning,
                message: "Codex App Server reported a thread system error.",
                metadata: ["codex_status": .string("systemError")]
            )),
            harnessId: .codex
        ))

        XCTAssertEqual(events, [.error(message: "Codex App Server reported a thread system error.")])
    }

    func testDoesNotPromoteUnrelatedCodexWarningDiagnosticToError() {
        let events = AgentCLIKitEventMapper().conversationEvents(from: runtimeEnvelope(
            .diagnostic(AgentDiagnosticEvent(
                code: .codexAppServerResponseFailure,
                severity: .warning,
                message: "Codex App Server request ignored.",
                metadata: ["codex_request_method": .string("unsupported")]
            )),
            harnessId: .codex
        ))

        XCTAssertTrue(events.isEmpty)
    }

    func testDoesNotPromoteCodexSystemErrorInfoDiagnosticToError() {
        let events = AgentCLIKitEventMapper().conversationEvents(from: runtimeEnvelope(
            .diagnostic(AgentDiagnosticEvent(
                code: .codexAppServerResponseFailure,
                severity: .info,
                message: "Codex App Server reported a thread system error.",
                metadata: ["codex_status": .string("systemError")]
            )),
            harnessId: .codex
        ))

        XCTAssertTrue(events.isEmpty)
    }

    private func runtimeEnvelope(
        _ event: AgentCLIKit.AgentEvent,
        harnessId: AgentCLIKit.AgentHarnessID = .claude
    ) -> AgentCLIKit.AgentEventEnvelope {
        AgentCLIKit.AgentEventEnvelope(
            generation: 1,
            index: 0,
            harnessId: harnessId,
            conversationId: "conversation",
            harnessSessionId: nil,
            source: .stdout,
            event: event,
            createdAt: Date(timeIntervalSince1970: 0)
        )
    }
}
