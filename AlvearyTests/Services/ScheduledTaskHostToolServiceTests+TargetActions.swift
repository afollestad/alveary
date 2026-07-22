import AgentCLIKit
import Foundation
import SwiftData
import XCTest

@testable import Alveary

@MainActor
extension ScheduledTaskHostToolServiceTests {
    func testEditCapturesRevisionAndPreservesDefinitionOwnedSettings() throws {
        let fixture = try ScheduledTaskHostToolFixture.project()
        let target = fixture.insertDefinition(
            id: "definition-edit",
            title: "Old title",
            prompt: "Old prompt",
            revision: 7,
            recurrence: .weekly(weekday: 2, hour: 9, minute: 0),
            providerID: "claude",
            model: "target-model",
            effort: "medium",
            permissionMode: "acceptEdits",
            grantedRoots: ["/tmp/target-grant"]
        )
        try fixture.modelContext.save()

        let result = fixture.service.handle(
            context: fixture.agentContext(),
            call: AgentCLIKit.AgentHostToolCall(
                name: ScheduledTaskHostToolCatalog.proposeToolName,
                arguments: [
                    "action": .string("edit"),
                    "task_id": .string(target.id),
                    "revision": .number(7),
                    "changes": .object([
                        "title": .string("New title"),
                        "schedule": .object([
                            "kind": .string("monthly"),
                            "day": .number(31),
                            "hour": .number(10),
                            "minute": .number(30)
                        ])
                    ])
                ]
            )
        )

        XCTAssertFalse(result.isError)
        let proposal = try XCTUnwrap(try fixture.modelContext.fetch(FetchDescriptor<ScheduledTaskProposal>()).first)
        let draft = try XCTUnwrap(proposal.definitionDraft)
        XCTAssertEqual(proposal.targetDefinitionID, target.id)
        XCTAssertEqual(proposal.expectedDefinitionRevision, 7)
        XCTAssertEqual(proposal.targetTitleSnapshot, "Old title")
        XCTAssertEqual(draft.title, "New title")
        XCTAssertEqual(draft.prompt, "Old prompt")
        XCTAssertEqual(draft.recurrence, .monthly(day: 31, hour: 10, minute: 30))
        XCTAssertEqual(draft.timeZoneIdentifier, "Etc/UTC")
        XCTAssertEqual(draft.providerID, "claude")
        XCTAssertEqual(draft.model, "target-model")
        XCTAssertEqual(draft.permissionMode, "acceptEdits")
        XCTAssertEqual(draft.grantedRoots, [CanonicalPath.normalize("/tmp/target-grant")])
    }

    func testStaleRevisionDoesNotPersistProposal() throws {
        let fixture = try ScheduledTaskHostToolFixture.project()
        let target = fixture.insertDefinition(id: "stale", revision: 3)
        try fixture.modelContext.save()

        let result = fixture.service.handle(
            context: fixture.agentContext(),
            call: AgentCLIKit.AgentHostToolCall(
                name: ScheduledTaskHostToolCatalog.proposeToolName,
                arguments: targetArguments(action: "pause", definitionID: target.id, revision: 2)
            )
        )

        XCTAssertTrue(result.isError)
        XCTAssertTrue(result.text.contains("revision 2 to 3"))
        XCTAssertEqual(try fixture.modelContext.fetchCount(FetchDescriptor<ScheduledTaskProposal>()), 0)
    }

    func testTargetActionsPersistTheRequestedProposalWithoutChangingDefinition() throws {
        let cases: [(ScheduledTaskProposalAction, ScheduledTaskState)] = [
            (.pause, .active),
            (.resume, .paused),
            (.delete, .active),
            (.runNow, .active)
        ]

        for (action, state) in cases {
            let fixture = try ScheduledTaskHostToolFixture.project()
            let target = fixture.insertDefinition(id: "target-\(action.rawValue)", revision: 5)
            target.state = state
            try fixture.modelContext.save()

            let result = fixture.service.handle(
                context: fixture.agentContext(requestID: "string:\(action.rawValue)"),
                call: AgentCLIKit.AgentHostToolCall(
                    name: ScheduledTaskHostToolCatalog.proposeToolName,
                    arguments: targetArguments(action: action.rawValue, definitionID: target.id, revision: 5)
                )
            )

            XCTAssertFalse(result.isError, action.rawValue)
            let proposal = try XCTUnwrap(
                try fixture.modelContext.fetch(FetchDescriptor<ScheduledTaskProposal>()).first,
                action.rawValue
            )
            XCTAssertEqual(proposal.action, action)
            XCTAssertEqual(proposal.targetDefinitionID, target.id)
            XCTAssertEqual(proposal.expectedDefinitionRevision, 5)
            XCTAssertNil(proposal.definitionDraft)
            XCTAssertEqual(target.state, state)
            XCTAssertEqual(target.revision, 5)
        }
    }
}
