import Foundation
import SwiftData
import XCTest

@testable import Alveary

@MainActor
final class ScheduledTaskProposalQueueTests: XCTestCase {
    func testPresentsSameTimestampProposalsInEnqueueOrderAndAdvancesAfterRejection() throws {
        let fixture = try ScheduledTaskProposalQueueFixture()
        let second = try fixture.insertProposal(
            id: "a-second",
            action: .create,
            createdAt: fixture.now,
            enqueueOrdinal: 2,
            definitionDraft: fixture.makeDefinitionDraft(title: "Second")
        )
        let first = try fixture.insertProposal(
            id: "z-first",
            action: .create,
            createdAt: fixture.now,
            enqueueOrdinal: 1,
            definitionDraft: fixture.makeDefinitionDraft(title: "First")
        )
        let firstID = first.id
        let secondID = second.id
        let coordinator = fixture.makeCoordinator()

        XCTAssertEqual(coordinator.currentProposal?.id, firstID)

        coordinator.reject(proposalID: firstID)

        XCTAssertNil(fixture.context.resolveScheduledTaskProposal(id: firstID))
        XCTAssertEqual(coordinator.currentProposal?.id, secondID)
    }

    func testReloadDeletesProposalWhoseSourceConversationNoLongerResolves() throws {
        let fixture = try ScheduledTaskProposalQueueFixture()
        let proposal = try fixture.insertProposal(
            id: "orphan",
            action: .create,
            definitionDraft: fixture.makeDefinitionDraft(title: "Orphan")
        )
        proposal.sourceConversationID = "missing-conversation"
        try fixture.context.save()
        let proposalID = proposal.id

        let coordinator = fixture.makeCoordinator()

        XCTAssertNil(coordinator.currentProposal)
        XCTAssertNil(fixture.context.resolveScheduledTaskProposal(id: proposalID))
        XCTAssertEqual(try fixture.context.fetchCount(FetchDescriptor<Conversation>()), 1)
    }

    func testConfirmCreatePersistsDefinitionAndConsumesProposalTogether() throws {
        let fixture = try ScheduledTaskProposalQueueFixture()
        let definitionDraft = fixture.makeDefinitionDraft(title: "Created from proposal")
        let proposal = try fixture.insertProposal(
            id: "create",
            action: .create,
            definitionDraft: definitionDraft
        )
        let coordinator = fixture.makeCoordinator()
        let viewModel = fixture.makeScheduledTasksViewModel()
        let editorDraft = viewModel.makeProposalDraft(
            definitionDraft,
            definitionID: nil,
            expectedRevision: nil
        )
        let saveRecorder = ScheduledTaskProposalSaveRecorder()
        let saveObserver = NotificationCenter.default.addObserver(
            forName: ModelContext.didSave,
            object: fixture.context,
            queue: nil
        ) { _ in
            saveRecorder.recordSave()
        }
        defer { NotificationCenter.default.removeObserver(saveObserver) }

        XCTAssertTrue(
            coordinator.confirmEditorProposal(
                proposalID: proposal.id,
                draft: editorDraft,
                viewModel: viewModel
            )
        )

        let verificationContext = ModelContext(fixture.container)
        let definitions = try verificationContext.fetch(FetchDescriptor<ScheduledTask>())
        XCTAssertEqual(definitions.map(\.title), ["Created from proposal"])
        XCTAssertEqual(definitions.first?.prompt, definitionDraft.prompt)
        XCTAssertEqual(definitions.first?.recurrence, definitionDraft.recurrence)
        XCTAssertEqual(try verificationContext.fetchCount(FetchDescriptor<ScheduledTaskProposal>()), 0)
        XCTAssertEqual(saveRecorder.saveCount, 1)
        XCTAssertNil(coordinator.currentProposal)
    }

    func testConfirmCreateValidationFailureKeepsProposalAndCreatesNoDefinition() throws {
        let fixture = try ScheduledTaskProposalQueueFixture()
        let definitionDraft = fixture.makeDefinitionDraft(title: "Invalid create")
        let proposal = try fixture.insertProposal(
            id: "invalid-create",
            action: .create,
            definitionDraft: definitionDraft
        )
        let coordinator = fixture.makeCoordinator()
        let viewModel = fixture.makeScheduledTasksViewModel()
        var editorDraft = viewModel.makeProposalDraft(
            definitionDraft,
            definitionID: nil,
            expectedRevision: nil
        )
        editorDraft.prompt = ""

        XCTAssertFalse(
            coordinator.confirmEditorProposal(
                proposalID: proposal.id,
                draft: editorDraft,
                viewModel: viewModel
            )
        )

        XCTAssertNotNil(fixture.context.resolveScheduledTaskProposal(id: proposal.id))
        XCTAssertEqual(try fixture.context.fetchCount(FetchDescriptor<ScheduledTask>()), 0)
        XCTAssertEqual(coordinator.errorMessage, ScheduledTasksViewModelError.promptRequired.localizedDescription)
    }

}

private final class ScheduledTaskProposalSaveRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var saveCount: Int {
        lock.withLock { count }
    }

    func recordSave() {
        lock.withLock {
            count += 1
        }
    }
}

@MainActor
final class ScheduledTaskProposalQueueFixture {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let container: ModelContainer
    let context: ModelContext
    let notificationCenter = NotificationCenter()
    let mutationService: ScheduledTaskMutationService

    init() throws {
        container = try ModelContainer(
            for: Project.self,
            AgentThread.self,
            Conversation.self,
            ConversationEventRecord.self,
            ScheduledTask.self,
            ScheduledTaskRun.self,
            ScheduledTaskProposal.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        context = ModelContext(container)
        mutationService = ScheduledTaskMutationService(
            modelContext: context,
            notificationCenter: notificationCenter
        )
    }

    func makeCoordinator(
        saveModelContext: @escaping (ModelContext) throws -> Void = { try $0.save() },
        runNow: @escaping @MainActor (ScheduledTaskRunNowRequest) -> Bool = { _ in true }
    ) -> ScheduledTaskProposalQueueCoordinator {
        ScheduledTaskProposalQueueCoordinator(
            modelContext: context,
            mutationService: mutationService,
            notificationCenter: notificationCenter,
            saveModelContext: saveModelContext,
            runNow: runNow,
            now: { self.now }
        )
    }

    func makeScheduledTasksViewModel() -> ScheduledTasksViewModel {
        ScheduledTasksViewModel(
            modelContext: context,
            mutationService: mutationService,
            settingsService: InMemorySettingsService(),
            notificationCenter: notificationCenter,
            runNow: { _ in true },
            now: { self.now }
        )
    }

    func insertDefinition(
        id: String,
        revision: Int = 1,
        state: ScheduledTaskState = .active,
        nextOccurrenceAt: Date? = nil
    ) throws -> ScheduledTask {
        let definition = ScheduledTask(
            id: id,
            title: "Original",
            prompt: "Original prompt",
            revision: revision,
            state: state,
            recurrence: .daily(hour: 8, minute: 0),
            timeZoneIdentifier: "UTC",
            providerID: "codex",
            effort: "medium",
            permissionMode: "on-request",
            nextOccurrenceAt: nextOccurrenceAt,
            createdAt: now.addingTimeInterval(-100),
            modifiedAt: now.addingTimeInterval(-50)
        )
        context.insert(definition)
        try context.save()
        return definition
    }

    func insertProposal(
        id: String,
        action: ScheduledTaskProposalAction,
        createdAt: Date? = nil,
        enqueueOrdinal: Int64? = nil,
        definitionDraft: ScheduledTaskProposalDefinitionDraft? = nil
    ) throws -> ScheduledTaskProposal {
        let conversation = Conversation(id: "conversation-\(id)", provider: "codex")
        let proposal = ScheduledTaskProposal(
            id: "proposal-\(id)",
            deduplicationKey: "deduplication-\(id)",
            action: action,
            canonicalPayloadJSON: #"{"action":"proposal"}"#,
            canonicalPayloadHash: "hash-\(id)",
            sourceProviderID: "codex",
            sourceProcessToken: UUID(),
            sourceRequestID: "string:request-\(id)",
            definitionDraft: definitionDraft,
            enqueueOrdinal: enqueueOrdinal,
            createdAt: createdAt ?? now,
            sourceConversation: conversation
        )
        context.insert(conversation)
        context.insert(proposal)
        try context.save()
        return proposal
    }

    func insertTargetProposal(
        id: String,
        action: ScheduledTaskProposalAction,
        definition: ScheduledTask,
        expectedRevision: Int? = nil,
        definitionDraft: ScheduledTaskProposalDefinitionDraft? = nil
    ) throws -> ScheduledTaskProposal {
        let conversation = Conversation(id: "conversation-\(id)", provider: "codex")
        let proposal = ScheduledTaskProposal(
            id: "proposal-\(id)",
            deduplicationKey: "deduplication-\(id)",
            action: action,
            canonicalPayloadJSON: #"{"action":"proposal"}"#,
            canonicalPayloadHash: "hash-\(id)",
            sourceProviderID: "codex",
            sourceProcessToken: UUID(),
            sourceRequestID: "string:request-\(id)",
            targetDefinitionID: definition.id,
            expectedDefinitionRevision: expectedRevision ?? definition.revision,
            targetTitleSnapshot: definition.title,
            targetScheduleSummarySnapshot: "Daily at 8:00 AM",
            definitionDraft: definitionDraft,
            createdAt: now,
            sourceConversation: conversation
        )
        context.insert(conversation)
        context.insert(proposal)
        try context.save()
        return proposal
    }

    func makeDefinitionDraft(
        title: String,
        prompt: String = "Do the proposed work.",
        recurrence: ScheduledTaskRecurrence = .daily(hour: 10, minute: 15),
        grantedRoots: [String] = ["/tmp/proposal-grant"]
    ) -> ScheduledTaskProposalDefinitionDraft {
        ScheduledTaskProposalDefinitionDraft(
            title: title,
            prompt: prompt,
            recurrence: recurrence,
            timeZoneIdentifier: "UTC",
            providerID: "codex",
            model: nil,
            effort: "medium",
            permissionMode: "on-request",
            workspaceKind: .privateWorkspace,
            workspaceStrategy: .worktree,
            grantedRoots: grantedRoots,
            projectPath: nil
        )
    }
}
