import AgentCLIKit
import Foundation
import SwiftData
import XCTest

@testable import Alveary

@MainActor
final class ThreadHostToolServiceTests: XCTestCase {
    func testUnknownToolNameIsRejected() async throws {
        let fixture = try ThreadHostToolFixture()

        let result = await fixture.service.handle(
            context: fixture.agentContext(),
            call: AgentCLIKit.AgentHostToolCall(name: "delete_thread")
        )

        XCTAssertTrue(result.isError)
        XCTAssertEqual(result.text, ThreadHostToolServiceError.unsupportedTool.localizedDescription)
    }

    func testHostToolNamesMatchTheAdvertisedCatalog() throws {
        let fixture = try ThreadHostToolFixture()

        XCTAssertEqual(fixture.service.hostToolNames, Set(ThreadHostToolCatalog.tools.map(\.name)))
        XCTAssertEqual(fixture.service.featureID, "threads")
    }

    /// Archiving is reversible only from the Archived screen and deletion is not, so the catalog
    /// must never grow a delete tool.
    func testCatalogAdvertisesNoDeletionTool() {
        let names = ThreadHostToolCatalog.tools.map(\.name)

        XCTAssertEqual(
            names.sorted(),
            [
                "archive_thread",
                "create_thread",
                "link_pr",
                "list_linked_prs",
                "list_projects",
                "list_threads",
                "pin_thread",
                "unlink_pr",
                "unpin_thread"
            ]
        )
        for name in names {
            XCTAssertFalse(name.contains("delete"), name)
        }
        XCTAssertTrue(ThreadHostToolCatalog.instructionsFragment.contains("never claim a thread was deleted"))
    }

    func testMutatingToolsRejectAnAutomatedScheduledRunSource() async throws {
        let fixture = try ThreadHostToolFixture()
        let run = fixture.attachNonterminalScheduledRun()
        fixture.thread.scheduledTaskRun = run
        try fixture.modelContext.save()

        for call in [
            AgentCLIKit.AgentHostToolCall(
                name: ThreadHostToolCatalog.createThreadToolName,
                arguments: ["project_path": .string(fixture.project.path)]
            ),
            AgentCLIKit.AgentHostToolCall(
                name: ThreadHostToolCatalog.archiveThreadToolName,
                arguments: ["thread_id": .string("other-main")]
            )
        ] {
            let result = await fixture.service.handle(context: fixture.agentContext(), call: call)

            XCTAssertTrue(result.isError, call.name)
            XCTAssertEqual(
                result.text,
                ThreadHostToolServiceError.automatedRunCannotManageThreads.localizedDescription
            )
        }
    }

    /// Listing changes nothing, so an automated run may still read.
    func testListingStaysAvailableToAnAutomatedScheduledRunSource() async throws {
        let fixture = try ThreadHostToolFixture()
        fixture.thread.scheduledTaskRun = fixture.attachNonterminalScheduledRun()
        try fixture.modelContext.save()

        let result = await fixture.service.handle(
            context: fixture.agentContext(),
            call: AgentCLIKit.AgentHostToolCall(name: ThreadHostToolCatalog.listThreadsToolName)
        )

        XCTAssertFalse(result.isError)
    }

    func testEveryToolRequiresAUsableSourceConversation() async throws {
        let fixture = try ThreadHostToolFixture()
        fixture.thread.archivedAt = Date(timeIntervalSince1970: 10)
        try fixture.modelContext.save()

        for tool in ThreadHostToolCatalog.tools {
            let result = await fixture.service.handle(
                context: fixture.agentContext(),
                call: AgentCLIKit.AgentHostToolCall(name: tool.name, arguments: fixture.minimalArguments(for: tool.name))
            )

            XCTAssertTrue(result.isError, tool.name)
            XCTAssertEqual(
                result.text,
                ThreadHostToolServiceError.sourceConversationUnavailable.localizedDescription,
                tool.name
            )
        }
    }

    func testMutatingToolErrorsCarryAStatusFieldAndReadsDoNot() async throws {
        let fixture = try ThreadHostToolFixture()

        let readResult = await fixture.service.handle(
            context: fixture.agentContext(),
            call: AgentCLIKit.AgentHostToolCall(
                name: ThreadHostToolCatalog.listThreadsToolName,
                arguments: ["filter": .string("anything")]
            )
        )
        XCTAssertTrue(readResult.isError)
        XCTAssertNil(readResult.structuredContent)

        let mutatingResult = await fixture.service.handle(
            context: fixture.agentContext(),
            call: AgentCLIKit.AgentHostToolCall(
                name: ThreadHostToolCatalog.archiveThreadToolName,
                arguments: ["thread_id": .string("missing")]
            )
        )
        XCTAssertTrue(mutatingResult.isError)
        XCTAssertEqual(try object(mutatingResult.structuredContent)["status"], .string("error"))
    }
}

extension ThreadHostToolServiceTests {
    func object(_ value: AgentCLIKit.JSONValue?) throws -> [String: AgentCLIKit.JSONValue] {
        guard case .object(let object)? = value else {
            throw ThreadHostToolFixtureError.unexpectedShape
        }
        return object
    }

    func array(_ value: AgentCLIKit.JSONValue?) throws -> [AgentCLIKit.JSONValue] {
        guard case .array(let array)? = value else {
            throw ThreadHostToolFixtureError.unexpectedShape
        }
        return array
    }

    func encoded(_ result: AgentCLIKit.AgentHostToolResult) throws -> String {
        let data = try JSONEncoder().encode(result.structuredContent)
        return result.text + (try XCTUnwrap(String(data: data, encoding: .utf8)))
    }
}

enum ThreadHostToolFixtureError: Error {
    case unexpectedShape
}

/// Records the initial prompts `create_thread` dispatched, so tests can assert a replayed retry
/// did not start a second turn.
@MainActor
final class ThreadHostToolPromptRecorder {
    private(set) var dispatched: [(conversationID: String, prompt: String)] = []

    func record(conversationID: String, prompt: String) {
        dispatched.append((conversationID, prompt))
    }

    var prompts: [String] {
        dispatched.map(\.prompt)
    }
}

@MainActor
final class ThreadHostToolFixture {
    let sidebar: SidebarTestFixture
    let service: ThreadHostToolService
    let pullRequests: StubPullRequestsService
    let project: Project
    let thread: AgentThread
    let conversation: Conversation
    let startedPrompts = ThreadHostToolPromptRecorder()
    let processToken = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE") ?? UUID()

    var modelContext: ModelContext { sidebar.context }

    init(
        providerDiscovery: (any AgentCLIKit.AgentProviderDiscoveryService)? = nil,
        providerSessionActions: RecordingProviderSessionActionService = RecordingProviderSessionActionService(),
        saveThreadCreation: @escaping @MainActor (ModelContext) throws -> Void = { try $0.save() },
        now: @escaping () -> Date = { Date(timeIntervalSince1970: 1_000) }
    ) throws {
        sidebar = try SidebarTestFixture(
            providerSessionActions: providerSessionActions,
            saveThreadCreation: saveThreadCreation
        )
        let sourceProject = Project(path: "/tmp/source-project", name: "Source Project")
        project = sourceProject
        let sourceThread = AgentThread(
            name: "Source thread",
            permissionMode: "on-request",
            effort: "high",
            model: "source-model",
            project: sourceProject
        )
        thread = sourceThread
        let sourceConversation = Conversation(id: "source-conversation", provider: "codex", thread: sourceThread)
        conversation = sourceConversation
        sourceThread.conversations = [sourceConversation]
        sourceProject.threads = [sourceThread]
        sidebar.context.insert(sourceProject)
        try sidebar.context.save()

        let recorder = startedPrompts
        let pullRequestsService = StubPullRequestsService()
        pullRequests = pullRequestsService
        service = ThreadHostToolService(
            modelContext: sidebar.context,
            lifecycleService: sidebar.viewModel.threadLifecycle,
            linkService: PullRequestLinkService(
                modelContext: sidebar.context,
                service: pullRequestsService,
                now: { Date(timeIntervalSince1970: 4_242) }
            ),
            settingsService: sidebar.settingsService,
            providerDiscovery: providerDiscovery,
            startInitialPrompt: { conversation, prompt in
                recorder.record(conversationID: conversation.id, prompt: prompt)
            },
            now: now
        )
    }

    func agentContext(
        requestID: String? = "request-1",
        providerID: AgentCLIKit.AgentProviderID = .codex,
        conversationID: String? = nil
    ) -> AgentCLIKit.AgentHostToolCallContext {
        AgentCLIKit.AgentHostToolCallContext(
            conversationId: AgentCLIKit.AgentConversationID(rawValue: conversationID ?? conversation.id),
            providerId: providerID,
            processToken: processToken,
            requestId: requestID
        )
    }

    @discardableResult
    func insertThread(
        name: String,
        conversationID: String,
        mode: AgentThreadMode = .task,
        project: Project? = nil
    ) throws -> AgentThread {
        let target = AgentThread(name: name, mode: mode, project: project)
        target.conversations = [Conversation(id: conversationID, provider: "codex", thread: target)]
        modelContext.insert(target)
        try modelContext.save()
        return target
    }

    /// Makes the calling conversation's thread a Task. Only its mode decides an inherited
    /// placement, so this leaves the workspace fields alone.
    func makeSourceThreadATask() throws {
        thread.mode = .task
        thread.project = nil
        try modelContext.save()
    }

    /// A run whose status is nonterminal, which blocks thread mutations from its source.
    func attachNonterminalScheduledRun() -> ScheduledTaskRun {
        let run = ScheduledTaskRun(
            occurrenceID: UUID().uuidString,
            definitionID: "automated-definition",
            definitionRevision: 1,
            occurrenceAt: Date(timeIntervalSince1970: 1_800_000_000),
            triggerKind: .scheduled,
            status: .running,
            titleSnapshot: "Automated run",
            promptSnapshot: "Continue work.",
            destinationSnapshot: .newThread,
            timeZoneIdentifierSnapshot: "Etc/UTC",
            providerIDSnapshot: "codex",
            effortSnapshot: "high",
            permissionModeSnapshot: "on-request",
            workspaceKindSnapshot: .project,
            workspaceStrategySnapshot: .localCheckout
        )
        modelContext.insert(run)
        return run
    }

    func minimalArguments(for toolName: String) -> [String: AgentCLIKit.JSONValue] {
        switch toolName {
        case ThreadHostToolCatalog.createThreadToolName:
            return ["project_path": .string(project.path)]
        case ThreadHostToolCatalog.archiveThreadToolName:
            return ["thread_id": .string("some-thread")]
        case ThreadHostToolCatalog.linkPullRequestToolName, ThreadHostToolCatalog.unlinkPullRequestToolName:
            return ["url": .string("https://github.com/octo/alpha/pull/7")]
        case ThreadHostToolCatalog.pinThreadToolName, ThreadHostToolCatalog.unpinThreadToolName:
            return ["thread_id": .string("some-thread")]
        default:
            return [:]
        }
    }
}
