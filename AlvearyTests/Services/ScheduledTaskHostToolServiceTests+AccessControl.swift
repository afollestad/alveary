import AgentCLIKit
import Foundation
import SwiftData
import XCTest

@testable import Alveary

@MainActor
extension ScheduledTaskHostToolServiceTests {
    func testAutomatedScheduledRunCannotListOrProposeSchedules() throws {
        let fixture = try ScheduledTaskHostToolFixture.task(
            descriptor: TaskWorkspaceDescriptor(
                primaryRoot: "/tmp/automated-task",
                grantedRoots: [],
                ownershipStrategy: .privateOwned,
                ownershipMarkerID: "automated-marker"
            )
        )
        let definition = fixture.insertDefinition(id: "source-schedule")
        let run = ScheduledTaskRun(
            snapshotting: definition,
            occurrenceID: "source-occurrence",
            occurrenceAt: Date(timeIntervalSince1970: 900),
            triggerKind: .scheduled,
            status: .running,
            thread: fixture.thread
        )
        fixture.modelContext.insert(run)
        fixture.thread.scheduledTaskRun = run
        try fixture.modelContext.save()

        let listResult = fixture.service.handle(
            context: fixture.agentContext(),
            call: AgentCLIKit.AgentHostToolCall(name: ScheduledTaskHostToolCatalog.listToolName)
        )
        let proposalResult = fixture.service.handle(
            context: fixture.agentContext(),
            call: AgentCLIKit.AgentHostToolCall(
                name: ScheduledTaskHostToolCatalog.proposeToolName,
                arguments: createArguments()
            )
        )

        XCTAssertTrue(listResult.isError)
        XCTAssertTrue(proposalResult.isError)
        XCTAssertTrue(proposalResult.text.contains("Automated scheduled runs"))
        XCTAssertEqual(try fixture.modelContext.fetchCount(FetchDescriptor<ScheduledTaskProposal>()), 0)
    }

    func testListRejectsMismatchedProviderAndProposalRequiresRequestIdentity() throws {
        let fixture = try ScheduledTaskHostToolFixture.project()
        let mismatchedList = fixture.service.handle(
            context: fixture.agentContext(providerID: .claude),
            call: AgentCLIKit.AgentHostToolCall(name: ScheduledTaskHostToolCatalog.listToolName)
        )
        let missingIdentity = fixture.service.handle(
            context: fixture.agentContext(requestID: nil),
            call: AgentCLIKit.AgentHostToolCall(
                name: ScheduledTaskHostToolCatalog.proposeToolName,
                arguments: createArguments()
            )
        )

        XCTAssertTrue(mismatchedList.isError)
        XCTAssertNil(mismatchedList.structuredContent)
        XCTAssertTrue(missingIdentity.isError)
        XCTAssertEqual(try object(missingIdentity.structuredContent)["status"], .string("error"))
        XCTAssertEqual(try fixture.modelContext.fetchCount(FetchDescriptor<ScheduledTaskProposal>()), 0)
    }
}
