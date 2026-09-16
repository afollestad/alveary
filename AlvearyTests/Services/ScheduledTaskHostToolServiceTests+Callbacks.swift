import AgentCLIKit
import SwiftData
import XCTest

@testable import Alveary

@MainActor
extension ScheduledTaskHostToolServiceTests {
    func testOneOffDefaultsToExactCallingTabAndReplaysOriginalTimeAfterDeletion() async throws {
        let fixture = try ScheduledTaskHostToolFixture.project()
        let secondary = Conversation(harness: "codex", isMain: false, displayOrder: 1, thread: fixture.thread)
        fixture.modelContext.insert(secondary)
        try fixture.modelContext.save()
        var clock = Date(timeIntervalSince1970: 1_000.123)
        let service = fixture.makeService(
            requestParser: ScheduledTaskHostToolRequestParser(defaultTimeZoneIdentifier: "Etc/UTC"), now: { clock }
        )
        let original = fixture.agentContext()
        let source = AgentHostToolCallContext(
            conversationId: AgentConversationID(rawValue: secondary.id), harnessId: .codex,
            processToken: original.processToken, requestId: "callback"
        )
        let call = AgentHostToolCall(name: ScheduledTaskHostToolCatalog.proposeToolName, arguments: callbackArguments())
        let result = await service.handle(context: source, call: call)
        XCTAssertFalse(result.isError, result.text)
        let definition = try XCTUnwrap(try fixture.modelContext.fetch(FetchDescriptor<ScheduledTask>()).first)
        XCTAssertEqual(definition.recurrence, .once(Date(timeIntervalSince1970: 2_800.123)))
        XCTAssertEqual(definition.state, .active)
        XCTAssertEqual(definition.targetThread?.id, fixture.thread.id)
        XCTAssertEqual(definition.exactTargetConversationID, secondary.id)
        XCTAssertEqual(definition.resolvedTargetConversation?.id, secondary.id)
        XCTAssertEqual(try object(result.structuredContent)["status"], .string("applied"))
        XCTAssertEqual(try object(result.structuredContent)["task_id"], .string(definition.id))
        XCTAssertEqual(try object(result.structuredContent)["scheduled_at"], .string("1970-01-01T00:46:40.123Z"))
        XCTAssertEqual(try fixture.modelContext.fetchCount(FetchDescriptor<ScheduledTaskProposal>()), 0)
        XCTAssertEqual(try fixture.modelContext.fetchCount(FetchDescriptor<AgentThread>()), 1)
        let markersBeforeRetry = secondary.events.filter { $0.type == ConversationEventRecord.hostToolOutcomeType }.count
        fixture.modelContext.delete(definition)
        try fixture.modelContext.save()
        clock = Date(timeIntervalSince1970: 2_000)
        let retry = await service.handle(context: source, call: call)
        XCTAssertEqual(retry, result)
        XCTAssertEqual(try fixture.modelContext.fetchCount(FetchDescriptor<ScheduledTask>()), 0)
        XCTAssertEqual(secondary.events.filter { $0.type == ConversationEventRecord.hostToolOutcomeType }.count, markersBeforeRetry)
    }

    func testOneOffSupportsExplicitNewThreadAndRecurringDefaultRequiresConfirmation() async throws {
        for destination in ["new_thread", "reused_thread"] {
            let fixture = try ScheduledTaskHostToolFixture.project()
            var arguments = callbackArguments()
            arguments["destination"] = .string(destination)
            let result = await fixture.service.handle(
                context: fixture.agentContext(),
                call: AgentHostToolCall(name: ScheduledTaskHostToolCatalog.proposeToolName, arguments: arguments)
            )
            XCTAssertFalse(result.isError, result.text)
            let definition = try XCTUnwrap(try fixture.modelContext.fetch(FetchDescriptor<ScheduledTask>()).first)
            XCTAssertEqual(definition.destination, destination == "new_thread" ? .newThreadPerRun : .reusedThread)
            XCTAssertNil(definition.targetThread)
            XCTAssertNil(definition.exactTargetConversationID)
            XCTAssertEqual(try fixture.modelContext.fetchCount(FetchDescriptor<AgentThread>()), 1)
        }
        let fixture = try ScheduledTaskHostToolFixture.project()
        var arguments = createArguments()
        arguments.removeValue(forKey: "destination")
        let result = await fixture.service.handle(
            context: fixture.agentContext(), call: AgentHostToolCall(name: ScheduledTaskHostToolCatalog.proposeToolName, arguments: arguments)
        )
        XCTAssertEqual(try object(result.structuredContent)["status"], .string("pending_confirmation"))
        XCTAssertEqual(try fixture.proposalDraft()?.exactTargetConversationID, fixture.conversation.id)
        XCTAssertEqual(try fixture.modelContext.fetchCount(FetchDescriptor<ScheduledTask>()), 0)
    }

    func testOneOffSaveFailureRollsBackDefinitionAndReceiptTogether() async throws {
        let fixture = try ScheduledTaskHostToolFixture.project()
        let persistence = CallbackPersistenceControl()
        let service = ScheduledTaskHostToolFixture.makeService(
            modelContext: fixture.modelContext, notificationCenter: fixture.notificationCenter,
            requestParser: ScheduledTaskHostToolRequestParser(defaultTimeZoneIdentifier: "Etc/UTC"),
            saveChanges: { context in
                if persistence.failSave { throw NSError(domain: "callback-save", code: 1) }
                try context.save()
            }
        )
        let call = AgentHostToolCall(name: ScheduledTaskHostToolCatalog.proposeToolName, arguments: callbackArguments())
        let failed = await service.handle(context: fixture.agentContext(), call: call)
        XCTAssertTrue(failed.isError)
        XCTAssertEqual(try fixture.modelContext.fetchCount(FetchDescriptor<ScheduledTask>()), 0)
        XCTAssertNil(fixture.conversation.scheduledTaskProposalReceiptsJSON)
        persistence.failSave = false
        let result = await service.handle(context: fixture.agentContext(), call: call)
        XCTAssertFalse(result.isError, result.text)
        XCTAssertEqual(try fixture.modelContext.fetchCount(FetchDescriptor<ScheduledTask>()), 1)
    }

    func testOneOffValidationRejectsInvalidTimingAndUntrustedPlacement() async throws {
        let invalidSchedules: [[String: AgentCLIKit.JSONValue]] = [
            ["kind": .string("once"), "after_seconds": .number(0)],
            ["kind": .string("once"), "after_seconds": .number(-1)],
            ["kind": .string("once"), "after_seconds": .number(1.5)],
            ["kind": .string("once"), "after_seconds": .number(9e18)],
            ["kind": .string("once"), "at": .string("1970-01-01T00:00:00Z")],
            ["kind": .string("once"), "at": .string("2030-01-01T00:00:00Z"), "after_seconds": .number(30)]
        ]
        let fixture = try ScheduledTaskHostToolFixture.project()
        var invalidArguments = invalidSchedules.map { schedule -> [String: AgentCLIKit.JSONValue] in
            var arguments = callbackArguments()
            arguments["schedule"] = .object(schedule)
            return arguments
        }
        var spoofed = callbackArguments()
        spoofed["destination"] = .string("current_thread")
        spoofed["target_thread_id"] = .string("different-thread")
        invalidArguments.append(spoofed)
        var workspaceOverride = callbackArguments()
        workspaceOverride["workspace"] = .object(["kind": .string("private")])
        invalidArguments.append(workspaceOverride)
        for arguments in invalidArguments {
            let result = await fixture.service.handle(
                context: fixture.agentContext(),
                call: AgentHostToolCall(name: ScheduledTaskHostToolCatalog.proposeToolName, arguments: arguments)
            )
            XCTAssertTrue(result.isError, result.text)
        }
        XCTAssertEqual(try fixture.modelContext.fetchCount(FetchDescriptor<ScheduledTask>()), 0)
    }

    func testAppliedCallbackTranscriptRestoresTimeAndLinkWithBothHarnessResultFormats() async throws {
        let fixture = try ScheduledTaskHostToolFixture.project()
        let arguments = callbackArguments()
        let result = await fixture.service.handle(
            context: fixture.agentContext(), call: AgentHostToolCall(name: ScheduledTaskHostToolCatalog.proposeToolName, arguments: arguments)
        )
        let input = try XCTUnwrap(String(data: JSONEncoder().encode(JSONValue.object(arguments)), encoding: .utf8))
        let structured = try XCTUnwrap(String(data: JSONEncoder().encode(result.structuredContent), encoding: .utf8))
        let definition = try XCTUnwrap(try fixture.modelContext.fetch(FetchDescriptor<ScheduledTask>()).first)
        for output in [result.text, structured] {
            let content = try XCTUnwrap(ScheduledTaskWidgetParsing.proposalContent(input: input, output: output, isError: false))
            XCTAssertEqual(content.status, .applied)
            XCTAssertEqual(content.targetDefinitionID, definition.id)
            XCTAssertEqual(content.recurrence, .once(Date(timeIntervalSince1970: 2_800)))
        }
        let legacy = ScheduledTaskWidgetParsing.proposalContent(
            input: input, output: "Opened a scheduling proposal for confirmation. No scheduled task has changed yet.", isError: false
        )
        XCTAssertEqual(legacy?.status, .pendingConfirmation)
    }

    func testAbsoluteOneOffSupportsExplicitCurrentAndExistingDestinations() async throws {
        for destination in ["current_thread", "existing_thread"] {
            let fixture = try ScheduledTaskHostToolFixture.project()
            var arguments = callbackArguments()
            arguments["destination"] = .string(destination)
            arguments["schedule"] = .object(["kind": .string("once"), "at": .string("2030-01-01T00:00:00Z")])
            if destination == "existing_thread" { arguments["target_thread_id"] = .string(fixture.conversation.id) }
            let result = await fixture.service.handle(
                context: fixture.agentContext(),
                call: AgentHostToolCall(name: ScheduledTaskHostToolCatalog.proposeToolName, arguments: arguments)
            )
            XCTAssertFalse(result.isError, result.text)
            let definition = try XCTUnwrap(fixture.modelContext.fetch(FetchDescriptor<ScheduledTask>()).first)
            XCTAssertEqual(definition.resolvedTargetConversation?.id, fixture.conversation.id)
            XCTAssertEqual(definition.exactTargetConversationID, destination == "current_thread" ? fixture.conversation.id : nil)
            XCTAssertEqual(try object(result.structuredContent)["destination"], .string(destination))
            XCTAssertEqual(try object(result.structuredContent)["scheduled_at"], .string("2030-01-01T00:00:00.000Z"))
        }
    }

    func testExpiredCallbackNeedsNewTimeBeforeResumeOrRunNow() async throws {
        let fixture = try ScheduledTaskHostToolFixture.project()
        let result = await fixture.service.handle(
            context: fixture.agentContext(),
            call: AgentHostToolCall(name: ScheduledTaskHostToolCatalog.proposeToolName, arguments: callbackArguments())
        )
        XCTAssertFalse(result.isError, result.text)
        let definition = try XCTUnwrap(fixture.modelContext.fetch(FetchDescriptor<ScheduledTask>()).first)
        definition.state = .paused
        definition.recurrence = .once(Date(timeIntervalSince1970: 900))
        try fixture.modelContext.save()
        let mutations = ScheduledTaskMutationService(modelContext: fixture.modelContext)
        for operation in ["resume", "run_now"] {
            XCTAssertThrowsError(try {
                if operation == "resume" {
                    try mutations.resume(definitionID: definition.id, at: Date(timeIntervalSince1970: 1_000))
                } else {
                    _ = try mutations.prepareRunNow(definitionID: definition.id, at: Date(timeIntervalSince1970: 1_000))
                }
            }()) { error in
                XCTAssertEqual(error as? ScheduledTaskMutationError, .oneOffTimeExpired)
            }
        }
        XCTAssertEqual(definition.state, .paused)
    }

    func testHistoricalWorkspaceOnlyProposalRetainsItsRecordedPendingCard() throws {
        let input = #"""
        {"action":"create","title":"Legacy","prompt":"Review.","workspace":{"kind":"private"},
         "schedule":{"kind":"daily","hour":9,"minute":0}}
        """#
        let content = try XCTUnwrap(ScheduledTaskWidgetParsing.proposalContent(
            input: input, output: "Opened a scheduling proposal for confirmation. No scheduled task has changed yet.", isError: false
        ))
        XCTAssertEqual(content.status, .pendingConfirmation)
        XCTAssertEqual(content.recurrence, .daily(hour: 9, minute: 0))
        XCTAssertEqual(content.proposedTitle, "Legacy")
    }

    func testRelativeTimeStartsAtAcceptanceAfterFolderDiscovery() async throws {
        let fixture = try ScheduledTaskHostToolFixture.project()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let clock = CallbackAcceptanceClock()
        let service = ScheduledTaskHostToolFixture.makeService(
            modelContext: fixture.modelContext, notificationCenter: fixture.notificationCenter,
            requestParser: ScheduledTaskHostToolRequestParser(defaultTimeZoneIdentifier: "UTC"),
            now: { clock.date }, resolveSourceFolder: { path in
                clock.date = Date(timeIntervalSince1970: 5_000)
                return SourceFolderSnapshot(path: path)
            }
        )
        var arguments = callbackArguments()
        arguments["destination"] = .string("new_thread")
        arguments["workspace"] = .object(["kind": .string("private"), "granted_roots": .array([.string(directory.path)])])
        let result = await service.handle(
            context: fixture.agentContext(),
            call: AgentHostToolCall(name: ScheduledTaskHostToolCatalog.proposeToolName, arguments: arguments)
        )
        XCTAssertFalse(result.isError, result.text)
        let definition = try XCTUnwrap(fixture.modelContext.fetch(FetchDescriptor<ScheduledTask>()).first)
        XCTAssertEqual(definition.recurrence, .once(Date(timeIntervalSince1970: 6_800)))
    }

    func callbackArguments() -> [String: AgentCLIKit.JSONValue] {
        ["action": .string("create"), "title": .string("Say hello"), "prompt": .string("Say hello."),
         "schedule": .object(["kind": .string("once"), "after_seconds": .number(1_800)])]
    }
}

@MainActor
private final class CallbackPersistenceControl {
    var failSave = true
}

@MainActor
private final class CallbackAcceptanceClock {
    var date = Date(timeIntervalSince1970: 1_000)
}
