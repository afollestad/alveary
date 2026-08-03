import XCTest

@testable import Alveary

@MainActor
final class HostToolTranscriptCatalogTests: XCTestCase {
    func testDescriptorLookupCoversHostSchedulingTools() {
        XCTAssertNotNil(
            HostToolTranscriptCatalog.descriptor(
                forToolName: HostToolTranscriptCatalog.toolName(ScheduledTaskHostToolCatalog.proposeToolName)
            )
        )
        // Claude qualifies host tool names; Codex reports them bare. Both must match.
        XCTAssertNotNil(
            HostToolTranscriptCatalog.descriptor(forToolName: ScheduledTaskHostToolCatalog.proposeToolName)
        )
        // The list tool renders as an ordinary tool row, so it has no widget descriptor.
        XCTAssertNil(
            HostToolTranscriptCatalog.descriptor(forToolName: ScheduledTaskHostToolCatalog.listToolName)
        )
        XCTAssertTrue(
            ScheduledTaskListToolPresentation.isListTool(named: ScheduledTaskHostToolCatalog.listToolName)
        )
        XCTAssertTrue(
            ScheduledTaskListToolPresentation.isListTool(
                named: HostToolTranscriptCatalog.toolName(ScheduledTaskHostToolCatalog.listToolName)
            )
        )
        XCTAssertNil(HostToolTranscriptCatalog.descriptor(forToolName: "mcp__other__do_thing"))
        XCTAssertNil(HostToolTranscriptCatalog.descriptor(forToolName: "do_thing"))
    }

    func testProposalContentParsesCreateRequestAndReceipt() throws {
        let content = try XCTUnwrap(
            ScheduledTaskWidgetParsing.proposalContent(
                input: createInput,
                output: #"{"action":"create","message":"Opened.","proposal_id":"p-1","status":"pending_confirmation","title":"Daily hello"}"#,
                isError: false
            )
        )
        XCTAssertEqual(content.action, .create)
        XCTAssertEqual(content.proposedTitle, "Daily hello")
        XCTAssertEqual(content.proposalID, "p-1")
        XCTAssertEqual(content.status, .pendingConfirmation)
        XCTAssertEqual(content.recurrence, .daily(hour: 8, minute: 0))
        XCTAssertTrue(content.isEditorProposal)
    }

    func testProposalContentNamesTaskFromReceiptWhenInputHasNoTitle() throws {
        let content = try XCTUnwrap(
            ScheduledTaskWidgetParsing.proposalContent(
                input: #"{"action":"pause","task_id":"task-1","revision":3}"#,
                output: #"{"action":"pause","message":"Opened.","proposal_id":"p-2","status":"pending_confirmation","title":"Nightly audit"}"#,
                isError: false
            )
        )
        XCTAssertEqual(content.action, .pause)
        XCTAssertEqual(content.proposedTitle, "Nightly audit")
        XCTAssertFalse(content.isEditorProposal)
    }

    func testProposalContentReportsRunningBeforeAResultArrives() throws {
        let content = try XCTUnwrap(
            ScheduledTaskWidgetParsing.proposalContent(input: createInput, output: nil, isError: false)
        )
        XCTAssertEqual(content.status, .running)
        XCTAssertNil(content.proposalID)
    }

    func testProposalContentReportsFailureForErrorResults() throws {
        let content = try XCTUnwrap(
            ScheduledTaskWidgetParsing.proposalContent(
                input: createInput,
                output: #"{"status":"error","message":"Ambiguous schedule."}"#,
                isError: true
            )
        )
        XCTAssertEqual(content.status, .failed)
        XCTAssertEqual(content.message, "Ambiguous schedule.")
    }

    /// Codex surfaces the host tool's plain-text fallback, not structured content, so a
    /// result with no `proposal_id` still represents an opened proposal.
    func testPlainTextResultStillReadsAsAnOpenedProposal() throws {
        let content = try XCTUnwrap(
            ScheduledTaskWidgetParsing.proposalContent(
                input: createInput,
                output: "Opened a scheduling proposal for confirmation. No scheduled task has changed yet.",
                isError: false
            )
        )
        XCTAssertEqual(content.status, .pendingConfirmation)
        XCTAssertNil(content.proposalID)
        XCTAssertEqual(content.message, "Opened a scheduling proposal for confirmation. No scheduled task has changed yet.")
    }

    func testAppliedResultReadsAsAlreadyInEffect() throws {
        let content = try XCTUnwrap(
            ScheduledTaskWidgetParsing.proposalContent(
                input: #"{"action":"pause","task_id":"task-1","revision":3}"#,
                output: #"{"action":"pause","message":"Paused it.","status":"applied","title":"Nightly audit"}"#,
                isError: false
            )
        )
        XCTAssertEqual(content.status, .applied)
        XCTAssertNil(content.proposalID)

        let entry = HostToolWidgetEntry(
            id: "tool-1",
            toolName: ScheduledTaskHostToolCatalog.proposeToolName,
            content: .scheduledTaskProposal(content),
            isComplete: true
        )
        XCTAssertTrue(entry.isAppliedProposal)
        XCTAssertFalse(entry.isUnresolvedProposal)
        XCTAssertEqual(HostToolWidgetSummary.text(for: entry), "Scheduled task paused: Nightly audit")
    }

    /// Run-now's resolved copy follows the launched run: present tense while it is in
    /// flight, past once it finishes or when history is restored later.
    func testRunNowSummaryFollowsTheRunLifecycle() throws {
        let content = try XCTUnwrap(
            ScheduledTaskWidgetParsing.proposalContent(
                input: #"{"action":"run_now","task_id":"task-1","revision":3}"#,
                output: #"{"action":"run_now","message":"Started.","status":"applied","title":"Say hello"}"#,
                isError: false
            )
        )
        let entry = HostToolWidgetEntry(
            id: "tool-1",
            toolName: ScheduledTaskHostToolCatalog.proposeToolName,
            content: .scheduledTaskProposal(content),
            isComplete: true
        )
        XCTAssertEqual(
            HostToolWidgetSummary.text(for: entry, isTargetRunInFlight: true),
            "Running scheduled task now: Say hello"
        )
        XCTAssertEqual(
            HostToolWidgetSummary.text(for: entry, isTargetRunInFlight: false),
            "Ran scheduled task: Say hello"
        )
    }

    /// A plain-text fallback result carries no title; the outcome marker's does.
    func testSummaryNamesTheTaskFromTheOutcomeMarkerTitle() throws {
        let content = try XCTUnwrap(
            ScheduledTaskWidgetParsing.proposalContent(
                input: #"{"action":"resume","task_id":"task-1","revision":3}"#,
                output: "Resumed Nightly audit. Future occurrences continue from now.",
                isError: false
            )
        )
        let entry = HostToolWidgetEntry(
            id: "tool-1",
            toolName: ScheduledTaskHostToolCatalog.proposeToolName,
            content: .scheduledTaskProposal(content),
            isComplete: true,
            outcome: .confirmed,
            outcomeTitle: "Nightly audit"
        )
        XCTAssertEqual(HostToolWidgetSummary.text(for: entry), "Scheduled task resumed: Nightly audit")
    }

    /// The host never opens a proposal for pause/resume/run-now, so a plain-text
    /// fallback result for them already took effect — the widget must not read as
    /// pending while its outcome marker waits for the turn-end rebuild.
    func testPlainTextResultForAnImmediateActionReadsAsApplied() throws {
        let cases: [(action: String, phrase: String)] = [
            (action: "pause", phrase: "Scheduled task paused"),
            (action: "resume", phrase: "Scheduled task resumed"),
            (action: "run_now", phrase: "Ran scheduled task")
        ]
        for testCase in cases {
            let content = try XCTUnwrap(
                ScheduledTaskWidgetParsing.proposalContent(
                    input: "{\"action\":\"\(testCase.action)\",\"task_id\":\"task-1\",\"revision\":3}",
                    output: "Done.",
                    isError: false
                ),
                testCase.action
            )
            XCTAssertEqual(content.status, .applied, testCase.action)

            let entry = HostToolWidgetEntry(
                id: "tool-1",
                toolName: ScheduledTaskHostToolCatalog.proposeToolName,
                content: .scheduledTaskProposal(content),
                isComplete: true
            )
            XCTAssertEqual(HostToolWidgetSummary.text(for: entry), testCase.phrase, testCase.action)
        }
    }

    func testUnreadableInputFallsBackToTheGenericToolRow() {
        XCTAssertNil(ScheduledTaskWidgetParsing.proposalContent(input: "not json", output: nil, isError: false))
        XCTAssertNil(ScheduledTaskWidgetParsing.proposalContent(input: #"{"foo":1}"#, output: nil, isError: false))
    }

    func testOutcomeKeyMatchesTheProposalIdentifier() {
        let descriptor = HostToolTranscriptCatalog.descriptor(
            forToolName: HostToolTranscriptCatalog.toolName(ScheduledTaskHostToolCatalog.proposeToolName)
        )
        XCTAssertEqual(descriptor?.outcomeKey(#"{"proposal_id":"p-9"}"#), "p-9")
        XCTAssertNil(descriptor?.outcomeKey(nil))
    }

    func testOutcomeMarkerPayloadRoundTrips() {
        for outcome in [HostToolWidgetOutcome.confirmed, .rejected] {
            let content = HostToolWidgetOutcomeMarker.content(for: outcome)
            XCTAssertEqual(HostToolWidgetOutcomeMarker.outcome(fromContent: content), outcome)
            XCTAssertNil(HostToolWidgetOutcomeMarker.definitionID(fromContent: content))
            XCTAssertNil(HostToolWidgetOutcomeMarker.title(fromContent: content))
        }
        // A confirmed create only learns its definition from the marker.
        let created = HostToolWidgetOutcomeMarker.content(
            for: .confirmed,
            definitionID: "task-9",
            title: "Nightly audit"
        )
        XCTAssertEqual(HostToolWidgetOutcomeMarker.outcome(fromContent: created), .confirmed)
        XCTAssertEqual(HostToolWidgetOutcomeMarker.definitionID(fromContent: created), "task-9")
        XCTAssertEqual(HostToolWidgetOutcomeMarker.title(fromContent: created), "Nightly audit")
        XCTAssertNil(HostToolWidgetOutcomeMarker.outcome(fromContent: "{}"))
    }

    func testAppliedActionResolvesItsTaskFromTheRequest() throws {
        let content = try XCTUnwrap(
            ScheduledTaskWidgetParsing.proposalContent(
                input: #"{"action":"pause","task_id":"task-1","revision":3}"#,
                output: #"{"action":"pause","message":"Paused it.","status":"applied","title":"Nightly audit"}"#,
                isError: false
            )
        )
        let entry = HostToolWidgetEntry(
            id: "tool-1",
            toolName: ScheduledTaskHostToolCatalog.proposeToolName,
            content: .scheduledTaskProposal(content),
            isComplete: true
        )
        XCTAssertEqual(entry.resolvedScheduledTaskID, "task-1")
        XCTAssertEqual(
            entry.withOutcome(.confirmed, definitionID: "task-2").resolvedScheduledTaskID,
            "task-2"
        )
    }

    private let createInput = #"""
    {"action":"create","title":"Daily hello","prompt":"Say hello.","schedule":{"kind":"daily","hour":8,"minute":0}}
    """#
}
