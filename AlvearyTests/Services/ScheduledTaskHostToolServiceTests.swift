import AgentCLIKit
import Foundation
import SwiftData
import XCTest

@testable import Alveary

@MainActor
final class ScheduledTaskHostToolServiceTests: XCTestCase {
    func testListReturnsStableMetadataWithoutPrompts() throws {
        let fixture = try ScheduledTaskHostToolFixture.project()
        let definition = fixture.insertDefinition(
            id: "definition-1",
            title: "Daily review",
            prompt: "SECRET PROMPT CONTENT",
            revision: 4,
            recurrence: .weekdays(days: [2, 4, 6], hour: 8, minute: 5)
        )
        try fixture.modelContext.save()

        let result = fixture.service.handle(
            context: fixture.agentContext(),
            call: AgentCLIKit.AgentHostToolCall(name: ScheduledTaskHostToolCatalog.listToolName)
        )

        XCTAssertFalse(result.isError)
        XCTAssertEqual(result.text, "Found 1 scheduled task.")
        let tasks = try array(try object(result.structuredContent)["tasks"])
        let task = try object(try XCTUnwrap(tasks.first))
        XCTAssertEqual(task["id"], .string(definition.id))
        XCTAssertEqual(task["revision"], .number(4))
        XCTAssertEqual(task["title"], .string("Daily review"))
        XCTAssertEqual(task["state"], .string("active"))
        XCTAssertEqual(task["schedule_summary"], .string("every Monday, Wednesday, Friday at 08:05 [UTC]"))
        XCTAssertFalse(try encoded(result).contains("SECRET PROMPT CONTENT"))
    }

    func testCreateBindsProviderSettingsAndProjectWorkspaceFromSource() throws {
        let notificationCenter = NotificationCenter()
        let notificationBox = ScheduledTaskProposalNotificationBox()
        let observer = notificationCenter.addObserver(
            forName: .scheduledTaskProposalsChanged,
            object: nil,
            queue: nil
        ) { notification in
            notificationBox.notification = notification
        }
        defer { notificationCenter.removeObserver(observer) }
        let fixture = try ScheduledTaskHostToolFixture.project(notificationCenter: notificationCenter)

        let result = fixture.service.handle(
            context: fixture.agentContext(),
            call: AgentCLIKit.AgentHostToolCall(
                name: ScheduledTaskHostToolCatalog.proposeToolName,
                arguments: createArguments()
            )
        )

        XCTAssertFalse(result.isError)
        let proposal = try XCTUnwrap(try fixture.modelContext.fetch(FetchDescriptor<ScheduledTaskProposal>()).first)
        let draft = try XCTUnwrap(proposal.definitionDraft)
        XCTAssertEqual(draft.providerID, "codex")
        XCTAssertEqual(draft.model, "source-model")
        XCTAssertEqual(draft.effort, "high")
        XCTAssertEqual(draft.permissionMode, "workspace-write")
        XCTAssertEqual(draft.workspaceKind, .project)
        XCTAssertEqual(draft.workspaceStrategy, .worktree)
        XCTAssertEqual(draft.projectPath, fixture.project?.path)
        XCTAssertTrue(draft.grantedRoots.isEmpty)
        XCTAssertEqual(proposal.project?.path, fixture.project?.path)
        XCTAssertEqual(proposal.sourceConversation?.id, fixture.conversation.id)
        XCTAssertEqual(proposal.enqueueOrdinal, 1)
        XCTAssertEqual(
            notificationBox.notification?.userInfo?[ScheduledTaskProposalChangeUserInfoKey.proposalID] as? String,
            proposal.id
        )
        XCTAssertEqual(
            notificationBox.notification?.userInfo?[ScheduledTaskProposalChangeUserInfoKey.sourceConversationID] as? String,
            fixture.conversation.id
        )
    }

    func testTaskWithMissingSourceProjectFallsBackToPrivateWorkspaceAndOnlyExplicitGrants() throws {
        let descriptor = TaskWorkspaceDescriptor(
            primaryRoot: "/tmp/obsolete-worktree",
            grantedRoots: ["/tmp/allowed-grant", "/tmp/obsolete-worktree"],
            ownershipStrategy: .projectWorktreeOwned,
            ownershipMarkerID: "marker",
            sourceProjectPath: "/tmp/missing-source-project"
        )
        let fixture = try ScheduledTaskHostToolFixture.task(descriptor: descriptor)

        let result = fixture.service.handle(
            context: fixture.agentContext(),
            call: AgentCLIKit.AgentHostToolCall(
                name: ScheduledTaskHostToolCatalog.proposeToolName,
                arguments: createArguments()
            )
        )

        XCTAssertFalse(result.isError)
        let proposal = try XCTUnwrap(try fixture.modelContext.fetch(FetchDescriptor<ScheduledTaskProposal>()).first)
        let draft = try XCTUnwrap(proposal.definitionDraft)
        XCTAssertEqual(draft.workspaceKind, .privateWorkspace)
        XCTAssertEqual(draft.workspaceStrategy, .worktree)
        XCTAssertEqual(draft.grantedRoots, [CanonicalPath.normalize("/tmp/allowed-grant")])
        XCTAssertFalse(draft.grantedRoots.contains(CanonicalPath.normalize("/tmp/obsolete-worktree")))
        XCTAssertNil(draft.projectPath)
        XCTAssertNil(proposal.project)
    }

}

extension ScheduledTaskHostToolServiceTests {
    func createArguments(title: String = "Daily review") -> [String: AgentCLIKit.JSONValue] {
        [
            "action": .string("create"),
            "title": .string(title),
            "prompt": .string("Review the latest changes."),
            "schedule": .object([
                "kind": .string("daily"),
                "hour": .number(9),
                "minute": .number(15),
                "time_zone": .string("UTC")
            ])
        ]
    }

    func targetArguments(
        action: String,
        definitionID: String,
        revision: Int
    ) -> [String: AgentCLIKit.JSONValue] {
        [
            "action": .string(action),
            "task_id": .string(definitionID),
            "revision": .number(Double(revision))
        ]
    }

    func object(_ value: AgentCLIKit.JSONValue?) throws -> [String: AgentCLIKit.JSONValue] {
        guard case .object(let object)? = value else {
            throw ScheduledTaskHostToolTestError.unexpectedJSON
        }
        return object
    }

    func object(_ value: AgentCLIKit.JSONValue) throws -> [String: AgentCLIKit.JSONValue] {
        guard case .object(let object) = value else {
            throw ScheduledTaskHostToolTestError.unexpectedJSON
        }
        return object
    }

    func array(_ value: AgentCLIKit.JSONValue?) throws -> [AgentCLIKit.JSONValue] {
        guard case .array(let array)? = value else {
            throw ScheduledTaskHostToolTestError.unexpectedJSON
        }
        return array
    }

    func proposalID(_ result: AgentCLIKit.AgentHostToolResult) throws -> String {
        guard case .string(let proposalID)? = try object(result.structuredContent)["proposal_id"] else {
            throw ScheduledTaskHostToolTestError.unexpectedJSON
        }
        return proposalID
    }

    func encoded(_ result: AgentCLIKit.AgentHostToolResult) throws -> String {
        let data = try JSONEncoder().encode(result.structuredContent)
        return result.text + (try XCTUnwrap(String(data: data, encoding: .utf8)))
    }

}

@MainActor
final class ScheduledTaskHostToolFixture {
    let modelContext: ModelContext
    let notificationCenter: NotificationCenter
    let service: ScheduledTaskHostToolService
    let conversation: Conversation
    let thread: AgentThread
    let project: Project?
    private let processToken = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE") ?? UUID()

    static func project(
        notificationCenter: NotificationCenter = NotificationCenter()
    ) throws -> ScheduledTaskHostToolFixture {
        try ScheduledTaskHostToolFixture(
            mode: .project,
            taskWorkspaceDescriptor: nil,
            notificationCenter: notificationCenter
        )
    }

    static func task(
        descriptor: TaskWorkspaceDescriptor,
        notificationCenter: NotificationCenter = NotificationCenter()
    ) throws -> ScheduledTaskHostToolFixture {
        try ScheduledTaskHostToolFixture(
            mode: .task,
            taskWorkspaceDescriptor: descriptor,
            notificationCenter: notificationCenter
        )
    }

    private init(
        mode: AgentThreadMode,
        taskWorkspaceDescriptor: TaskWorkspaceDescriptor?,
        notificationCenter: NotificationCenter
    ) throws {
        let container = try ModelContainer(
            for: Project.self,
            AgentThread.self,
            Conversation.self,
            ConversationEventRecord.self,
            ScheduledTask.self,
            ScheduledTaskRun.self,
            ScheduledTaskProposal.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        modelContext = context
        self.notificationCenter = notificationCenter
        let sourceProject = mode == .project
            ? Project(path: "/tmp/source-project", name: "Source Project")
            : nil
        project = sourceProject
        let sourceThread = AgentThread(
            name: "Source thread",
            permissionMode: "workspace-write",
            effort: "high",
            model: "source-model",
            mode: mode,
            taskWorkspaceDescriptor: taskWorkspaceDescriptor,
            project: sourceProject
        )
        thread = sourceThread
        let sourceConversation = Conversation(id: "source-conversation", provider: "codex", thread: sourceThread)
        conversation = sourceConversation
        sourceThread.conversations = [sourceConversation]
        if let sourceProject {
            sourceProject.threads = [sourceThread]
            context.insert(sourceProject)
        } else {
            context.insert(sourceThread)
        }
        try context.save()
        service = ScheduledTaskHostToolService(
            modelContext: context,
            notificationCenter: notificationCenter,
            now: { Date(timeIntervalSince1970: 1_000) }
        )
    }

    func agentContext(
        requestID: String? = "string:request",
        providerID: AgentCLIKit.AgentProviderID = .codex
    ) -> AgentCLIKit.AgentHostToolCallContext {
        AgentCLIKit.AgentHostToolCallContext(
            conversationId: AgentCLIKit.AgentConversationID(rawValue: conversation.id),
            providerId: providerID,
            processToken: processToken,
            requestId: requestID
        )
    }

    @discardableResult
    func insertDefinition(
        id: String,
        title: String = "Definition",
        prompt: String = "Definition prompt",
        revision: Int = 1,
        recurrence: ScheduledTaskRecurrence = .daily(hour: 9, minute: 0),
        providerID: String = "codex",
        model: String? = nil,
        effort: String = "medium",
        permissionMode: String = "default",
        grantedRoots: [String] = []
    ) -> ScheduledTask {
        let definition = ScheduledTask(
            id: id,
            title: title,
            prompt: prompt,
            revision: revision,
            recurrence: recurrence,
            timeZoneIdentifier: "UTC",
            providerID: providerID,
            model: model,
            effort: effort,
            permissionMode: permissionMode,
            workspaceKind: .privateWorkspace,
            workspaceStrategy: .worktree,
            grantedRoots: grantedRoots
        )
        modelContext.insert(definition)
        return definition
    }
}

private final class ScheduledTaskProposalNotificationBox: @unchecked Sendable {
    var notification: Notification?
}

private enum ScheduledTaskHostToolTestError: Error {
    case unexpectedJSON
}
