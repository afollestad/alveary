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

    /// Deletion is irreversible, so it still opens a proposal and changes nothing.
    func testDeleteOpensAProposalWithoutChangingTheDefinition() throws {
        let fixture = try ScheduledTaskHostToolFixture.project()
        let target = fixture.insertDefinition(id: "target-delete", revision: 5)
        try fixture.modelContext.save()

        let result = fixture.service.handle(
            context: fixture.agentContext(requestID: "string:delete"),
            call: AgentCLIKit.AgentHostToolCall(
                name: ScheduledTaskHostToolCatalog.proposeToolName,
                arguments: targetArguments(action: "delete", definitionID: target.id, revision: 5)
            )
        )

        XCTAssertFalse(result.isError)
        let proposal = try XCTUnwrap(try fixture.modelContext.fetch(FetchDescriptor<ScheduledTaskProposal>()).first)
        XCTAssertEqual(proposal.action, .delete)
        XCTAssertEqual(proposal.targetDefinitionID, target.id)
        XCTAssertEqual(proposal.expectedDefinitionRevision, 5)
        XCTAssertNil(proposal.definitionDraft)
        XCTAssertEqual(target.state, .active)
        XCTAssertEqual(target.revision, 5)
    }

    /// Pause and resume are reversible and revision-checked, so they skip confirmation.
    func testPauseAndResumeApplyImmediatelyWithoutAProposal() throws {
        struct StateChangeCase {
            let action: ScheduledTaskProposalAction
            let initialState: ScheduledTaskState
            let expectedState: ScheduledTaskState
        }
        let cases = [
            StateChangeCase(action: .pause, initialState: .active, expectedState: .paused),
            StateChangeCase(action: .resume, initialState: .paused, expectedState: .active)
        ]

        for testCase in cases {
            let action = testCase.action
            let initialState = testCase.initialState
            let expectedState = testCase.expectedState
            let fixture = try ScheduledTaskHostToolFixture.project()
            let target = fixture.insertDefinition(id: "target-\(action.rawValue)", revision: 5)
            target.state = initialState
            try fixture.modelContext.save()

            let result = fixture.service.handle(
                context: fixture.agentContext(requestID: "string:\(action.rawValue)"),
                call: AgentCLIKit.AgentHostToolCall(
                    name: ScheduledTaskHostToolCatalog.proposeToolName,
                    arguments: targetArguments(action: action.rawValue, definitionID: target.id, revision: 5)
                )
            )

            XCTAssertFalse(result.isError, action.rawValue)
            XCTAssertEqual(try status(result), "applied", action.rawValue)
            XCTAssertEqual(try fixture.modelContext.fetchCount(FetchDescriptor<ScheduledTaskProposal>()), 0, action.rawValue)
            XCTAssertEqual(target.state, expectedState, action.rawValue)
            XCTAssertEqual(target.revision, 6, action.rawValue)

            // The marker is what resolves the transcript widget on providers whose tool
            // result is a plain-text fallback.
            let markers = try outcomeMarkers(in: fixture.modelContext)
            XCTAssertEqual(markers.count, 1, action.rawValue)
            let content = try XCTUnwrap(markers.first?.content, action.rawValue)
            XCTAssertEqual(HostToolWidgetOutcomeMarker.outcome(fromContent: content), .confirmed, action.rawValue)
            XCTAssertEqual(HostToolWidgetOutcomeMarker.definitionID(fromContent: content), target.id, action.rawValue)
            XCTAssertEqual(HostToolWidgetOutcomeMarker.title(fromContent: content), "Definition", action.rawValue)
        }
    }

    /// A retried run-now replays its receipt instead of launching a second run.
    func testRunNowAppliesImmediatelyAndRetryDoesNotStartASecondRun() throws {
        let fixture = try ScheduledTaskHostToolFixture.project()
        let target = fixture.insertDefinition(id: "target-run-now", revision: 5)
        try fixture.modelContext.save()
        let call = AgentCLIKit.AgentHostToolCall(
            name: ScheduledTaskHostToolCatalog.proposeToolName,
            arguments: targetArguments(action: "run_now", definitionID: target.id, revision: 5)
        )
        let context = fixture.agentContext(requestID: "string:run-now")

        let first = fixture.service.handle(context: context, call: call)
        let retry = fixture.service.handle(context: context, call: call)

        XCTAssertFalse(first.isError)
        XCTAssertEqual(try status(first), "applied")
        XCTAssertEqual(retry.text, first.text)
        XCTAssertEqual(fixture.startedRunNowRequests.count, 1)
        XCTAssertEqual(try fixture.modelContext.fetchCount(FetchDescriptor<ScheduledTaskProposal>()), 0)
        // The replayed retry must not stamp a second outcome marker.
        XCTAssertEqual(try outcomeMarkers(in: fixture.modelContext).count, 1)
    }

    private func status(_ result: AgentCLIKit.AgentHostToolResult) throws -> String? {
        guard case let .object(object)? = result.structuredContent,
              case let .string(status)? = object["status"] else {
            return nil
        }
        return status
    }

    private func outcomeMarkers(in modelContext: ModelContext) throws -> [ConversationEventRecord] {
        let type = ConversationEventRecord.hostToolOutcomeType
        return try modelContext.fetch(
            FetchDescriptor<ConversationEventRecord>(predicate: #Predicate { $0.type == type })
        )
    }
}
