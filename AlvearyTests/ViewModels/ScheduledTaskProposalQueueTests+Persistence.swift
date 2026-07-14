import AgentCLIKit
import Foundation
import SwiftData
import XCTest

@testable import Alveary

@MainActor
extension ScheduledTaskProposalQueueTests {
    func testUnsupportedPayloadVersionCannotConfirmActionProposal() throws {
        let fixture = try ScheduledTaskProposalQueueFixture()
        let definition = try fixture.insertDefinition(id: "future-version-target", revision: 4)
        let proposal = try fixture.insertTargetProposal(
            id: "future-version-pause",
            action: .pause,
            definition: definition
        )
        proposal.payloadVersion = ScheduledTaskProposal.currentPayloadVersion + 1
        try fixture.context.save()
        let coordinator = fixture.makeCoordinator()

        XCTAssertNotNil(coordinator.currentProposal?.conflictMessage)

        coordinator.confirmActionProposal(proposalID: proposal.id)

        XCTAssertEqual(definition.state, .active)
        XCTAssertEqual(definition.revision, 4)
        XCTAssertNotNil(fixture.context.resolveScheduledTaskProposal(id: proposal.id))
    }

    func testCreateProposalWithTargetIdentityCannotEditDefinition() throws {
        let fixture = try ScheduledTaskProposalQueueFixture()
        let definition = try fixture.insertDefinition(id: "malformed-create-target", revision: 6)
        let definitionDraft = fixture.makeDefinitionDraft(title: "Should not replace the target")
        let proposal = try fixture.insertTargetProposal(
            id: "malformed-targeted-create",
            action: .create,
            definition: definition,
            definitionDraft: definitionDraft
        )
        let coordinator = fixture.makeCoordinator()
        let viewModel = fixture.makeScheduledTasksViewModel()
        let editorDraft = viewModel.makeProposalDraft(
            definitionDraft,
            definitionID: definition.id,
            expectedRevision: definition.revision
        )

        XCTAssertNotNil(coordinator.currentProposal?.conflictMessage)
        XCTAssertFalse(
            coordinator.confirmEditorProposal(
                proposalID: proposal.id,
                draft: editorDraft,
                viewModel: viewModel
            )
        )

        XCTAssertEqual(definition.title, "Original")
        XCTAssertEqual(definition.revision, 6)
        XCTAssertEqual(try fixture.context.fetchCount(FetchDescriptor<ScheduledTask>()), 1)
        XCTAssertNotNil(fixture.context.resolveScheduledTaskProposal(id: proposal.id))
    }

    func testReloadRollsBackOrphanDeletionWhenCleanupSaveFails() throws {
        let fixture = try ScheduledTaskProposalQueueFixture()
        let proposal = try fixture.insertProposal(
            id: "orphan-save-failure",
            action: .create,
            definitionDraft: fixture.makeDefinitionDraft(title: "Orphan")
        )
        proposal.sourceConversationID = "missing-conversation"
        try fixture.context.save()

        let coordinator = fixture.makeCoordinator(saveModelContext: { _ in
            throw ScheduledTaskProposalQueueTestError.injectedSaveFailure
        })

        XCTAssertEqual(
            coordinator.errorMessage,
            ScheduledTaskProposalQueueTestError.injectedSaveFailure.localizedDescription
        )
        XCTAssertNotNil(fixture.context.resolveScheduledTaskProposal(id: proposal.id))
        XCTAssertFalse(fixture.context.hasChanges)
    }

    func testSuccessfulRejectClearsSharedProposalEditorError() throws {
        let fixture = try ScheduledTaskProposalQueueFixture()
        let proposal = try fixture.insertProposal(
            id: "reject-clears-editor-error",
            action: .create,
            definitionDraft: fixture.makeDefinitionDraft(title: "Reject")
        )
        let proposalID = proposal.id
        let coordinator = fixture.makeCoordinator()
        let viewModel = fixture.makeScheduledTasksViewModel()
        var draft = viewModel.makeNewDraft()
        draft.prompt = "Proposal editor validation failed."
        XCTAssertFalse(viewModel.save(draft))
        XCTAssertNotNil(viewModel.editorErrorMessage)

        XCTAssertTrue(
            coordinator.reject(
                proposalID: proposalID,
                clearingProposalErrorIn: viewModel
            )
        )

        XCTAssertNil(viewModel.editorErrorMessage)
        XCTAssertNil(fixture.context.resolveScheduledTaskProposal(id: proposalID))
    }

    func testFailedRejectRollsBackAndKeepsSharedProposalEditorError() throws {
        let fixture = try ScheduledTaskProposalQueueFixture()
        let proposal = try fixture.insertProposal(
            id: "reject-save-failure",
            action: .create,
            definitionDraft: fixture.makeDefinitionDraft(title: "Reject")
        )
        let coordinator = fixture.makeCoordinator(saveModelContext: { _ in
            throw ScheduledTaskProposalQueueTestError.injectedSaveFailure
        })
        let viewModel = fixture.makeScheduledTasksViewModel()
        var draft = viewModel.makeNewDraft()
        draft.prompt = "Proposal editor validation failed."
        XCTAssertFalse(viewModel.save(draft))
        let expectedError = try XCTUnwrap(viewModel.editorErrorMessage)

        XCTAssertFalse(
            coordinator.reject(
                proposalID: proposal.id,
                clearingProposalErrorIn: viewModel
            )
        )

        XCTAssertEqual(viewModel.editorErrorMessage, expectedError)
        XCTAssertEqual(
            coordinator.errorMessage,
            ScheduledTaskProposalQueueTestError.injectedSaveFailure.localizedDescription
        )
        XCTAssertNotNil(fixture.context.resolveScheduledTaskProposal(id: proposal.id))
        XCTAssertFalse(fixture.context.hasChanges)
    }

    func testRejectDoesNotTreatANoncurrentQueuedProposalAsDismissed() throws {
        let fixture = try ScheduledTaskProposalQueueFixture()
        let first = try fixture.insertProposal(
            id: "current",
            action: .create,
            createdAt: fixture.now,
            definitionDraft: fixture.makeDefinitionDraft(title: "Current")
        )
        let queued = try fixture.insertProposal(
            id: "queued",
            action: .create,
            createdAt: fixture.now.addingTimeInterval(1),
            definitionDraft: fixture.makeDefinitionDraft(title: "Queued")
        )
        let coordinator = fixture.makeCoordinator()
        let viewModel = fixture.makeScheduledTasksViewModel()
        var draft = viewModel.makeNewDraft()
        draft.prompt = "Keep this proposal error."
        XCTAssertFalse(viewModel.save(draft))
        let expectedError = try XCTUnwrap(viewModel.editorErrorMessage)

        XCTAssertEqual(coordinator.currentProposal?.id, first.id)
        XCTAssertFalse(
            coordinator.reject(
                proposalID: queued.id,
                clearingProposalErrorIn: viewModel
            )
        )
        XCTAssertNotNil(fixture.context.resolveScheduledTaskProposal(id: queued.id))
        XCTAssertEqual(viewModel.editorErrorMessage, expectedError)
    }

    func testProductionContextTopologySharesHostQueueAndMainMutations() throws {
        let fixture = try ScheduledTaskProposalCrossContextFixture()
        let firstProposalID = try fixture.propose(
            title: "First proposal",
            conversationID: fixture.firstConversationID,
            requestID: "first"
        )
        fixture.coordinator.reload()
        XCTAssertEqual(fixture.coordinator.currentProposal?.id, firstProposalID)

        XCTAssertTrue(fixture.coordinator.reject(proposalID: firstProposalID))
        fixture.advanceClock()
        let replacementProposalID = try fixture.propose(
            title: "Replacement proposal",
            conversationID: fixture.firstConversationID,
            requestID: "replacement"
        )
        XCTAssertNotEqual(replacementProposalID, firstProposalID)
        fixture.coordinator.reload()
        XCTAssertEqual(fixture.coordinator.currentProposal?.id, replacementProposalID)

        let queuedProposalID = try fixture.propose(
            title: "Queued proposal",
            conversationID: fixture.secondConversationID,
            requestID: "queued"
        )
        fixture.coordinator.reload()
        XCTAssertEqual(fixture.coordinator.currentProposal?.id, replacementProposalID)
        XCTAssertEqual(fixture.proposalEnqueueOrdinal(id: replacementProposalID), 1)
        XCTAssertEqual(fixture.proposalEnqueueOrdinal(id: queuedProposalID), 2)
        XCTAssertEqual(
            fixture.proposalCreatedAt(id: replacementProposalID),
            fixture.proposalCreatedAt(id: queuedProposalID)
        )

        XCTAssertTrue(try fixture.confirmEditorProposal(id: replacementProposalID))
        fixture.coordinator.reload()
        XCTAssertEqual(fixture.coordinator.currentProposal?.id, queuedProposalID)
        XCTAssertFalse(fixture.proposalExists(id: replacementProposalID))
        XCTAssertEqual(try fixture.definitionTitles(), ["Replacement proposal"])
    }
}

@MainActor
private final class ScheduledTaskProposalCrossContextFixture {
    let container: ModelContainer
    let mainContext: ModelContext
    let coordinator: ScheduledTaskProposalQueueCoordinator
    let viewModel: ScheduledTasksViewModel
    let firstConversationID = "context-source-1"
    let secondConversationID = "context-source-2"

    private let hostService: ScheduledTaskHostToolService
    private let processToken = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE") ?? UUID()
    private let clock = ScheduledTaskProposalTestClock()

    init() throws {
        container = try Self.makeContainer()
        let resolvedMainContext = ModelContext(container)
        mainContext = resolvedMainContext
        let queueContext = ModelContext(container)
        let notificationCenter = NotificationCenter()
        try Self.insertSources(
            firstConversationID: firstConversationID,
            secondConversationID: secondConversationID,
            into: resolvedMainContext
        )
        let mutationService = ScheduledTaskMutationService(
            modelContext: resolvedMainContext,
            notificationCenter: notificationCenter
        )
        hostService = ScheduledTaskHostToolService(
            modelContext: resolvedMainContext,
            notificationCenter: notificationCenter,
            now: { [clock] in clock.now }
        )
        coordinator = ScheduledTaskProposalQueueCoordinator(
            modelContext: queueContext,
            mutationService: mutationService,
            notificationCenter: notificationCenter,
            runNow: { _ in true },
            now: { [clock] in clock.now }
        )
        viewModel = ScheduledTasksViewModel(
            modelContext: resolvedMainContext,
            mutationService: mutationService,
            settingsService: InMemorySettingsService(),
            notificationCenter: notificationCenter,
            runNow: { _ in true },
            now: { [clock] in clock.now }
        )
    }

    func advanceClock() {
        clock.now.addTimeInterval(1)
    }

    func propose(
        title: String,
        conversationID: String,
        requestID: String
    ) throws -> String {
        let result = hostService.handle(
            context: AgentCLIKit.AgentHostToolCallContext(
                conversationId: AgentCLIKit.AgentConversationID(rawValue: conversationID),
                providerId: .codex,
                processToken: processToken,
                requestId: "string:\(requestID)"
            ),
            call: AgentCLIKit.AgentHostToolCall(
                name: ScheduledTaskHostToolCatalog.proposeToolName,
                arguments: Self.createArguments(title: title)
            )
        )
        guard !result.isError,
              case .object(let output)? = result.structuredContent,
              case .string(let proposalID)? = output["proposal_id"] else {
            throw ScheduledTaskProposalQueueTestError.unexpectedHostResult
        }
        return proposalID
    }

    func confirmEditorProposal(id proposalID: String) throws -> Bool {
        let proposal = try XCTUnwrap(mainContext.resolveScheduledTaskProposal(id: proposalID))
        let definitionDraft = try XCTUnwrap(proposal.definitionDraft)
        return coordinator.confirmEditorProposal(
            proposalID: proposalID,
            draft: viewModel.makeProposalDraft(
                definitionDraft,
                definitionID: nil,
                expectedRevision: nil
            ),
            viewModel: viewModel
        )
    }

    func proposalExists(id: String) -> Bool {
        ModelContext(container).resolveScheduledTaskProposal(id: id) != nil
    }

    func proposalEnqueueOrdinal(id: String) -> Int64? {
        ModelContext(container).resolveScheduledTaskProposal(id: id)?.enqueueOrdinal
    }

    func proposalCreatedAt(id: String) -> Date? {
        ModelContext(container).resolveScheduledTaskProposal(id: id)?.createdAt
    }

    func definitionTitles() throws -> [String] {
        try ModelContext(container).fetch(FetchDescriptor<ScheduledTask>()).map(\.title)
    }

    private static func makeContainer() throws -> ModelContainer {
        try ModelContainer(
            for: Project.self,
            AgentThread.self,
            Conversation.self,
            ConversationEventRecord.self,
            ScheduledTask.self,
            ScheduledTaskRun.self,
            ScheduledTaskProposal.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }

    private static func insertSources(
        firstConversationID: String,
        secondConversationID: String,
        into context: ModelContext
    ) throws {
        let project = Project(path: "/tmp/proposal-context-topology", name: "Context topology")
        let firstThread = AgentThread(name: "First source", mode: .project, project: project)
        let firstConversation = Conversation(id: firstConversationID, provider: "codex", thread: firstThread)
        firstThread.conversations = [firstConversation]
        let secondThread = AgentThread(name: "Second source", mode: .project, project: project)
        let secondConversation = Conversation(id: secondConversationID, provider: "codex", thread: secondThread)
        secondThread.conversations = [secondConversation]
        project.threads = [firstThread, secondThread]
        context.insert(project)
        try context.save()
    }

    private static func createArguments(title: String) -> [String: AgentCLIKit.JSONValue] {
        [
            "action": .string("create"),
            "title": .string(title),
            "prompt": .string("Perform the proposed work."),
            "schedule": .object([
                "kind": .string("daily"),
                "hour": .number(10),
                "minute": .number(15),
                "time_zone": .string("UTC")
            ])
        ]
    }
}

@MainActor
private final class ScheduledTaskProposalTestClock {
    var now = Date(timeIntervalSince1970: 1_800_000_000)
}

private enum ScheduledTaskProposalQueueTestError: LocalizedError {
    case injectedSaveFailure
    case unexpectedHostResult

    var errorDescription: String? {
        switch self {
        case .injectedSaveFailure:
            "Injected proposal save failure."
        case .unexpectedHostResult:
            "The scheduling host tool returned an unexpected result."
        }
    }
}
