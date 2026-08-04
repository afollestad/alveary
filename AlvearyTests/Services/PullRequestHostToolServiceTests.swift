import AgentCLIKit
import Foundation
import SwiftData
import XCTest

@testable import Alveary

/// Cross-cutting rules every pull request tool obeys. Per-tool behavior lives in the
/// `+Topic` companions, which extend this class rather than declaring their own.
@MainActor
final class PullRequestHostToolServiceTests: XCTestCase {
    func testEveryToolRefusesWhenPullRequestIntegrationIsDisabled() async throws {
        let fixture = try PullRequestHostToolFixture()
        fixture.settingsService.update { $0.pullRequestsEnabled = false }

        for tool in PullRequestHostToolCatalog.tools {
            let result = await fixture.service.handle(
                context: fixture.agentContext(),
                call: AgentCLIKit.AgentHostToolCall(
                    name: tool.name,
                    arguments: fixture.minimalArguments(for: tool.name)
                )
            )
            XCTAssertTrue(result.isError, "\(tool.name) acted with the integration turned off")
            XCTAssertEqual(
                result.text,
                PullRequestHostToolServiceError.pullRequestsDisabled.localizedDescription,
                "\(tool.name) did not name the setting"
            )
            // GitHub must not have been reached at all.
            XCTAssertEqual(fixture.pullRequests.detailCallCount, 0)
            XCTAssertEqual(fixture.pullRequests.listCallCount, 0)
        }
    }

    func testOnlyClosingRefusesAnAutomatedScheduledRun() async throws {
        let fixture = try PullRequestHostToolFixture()
        try fixture.attachAutomatedScheduledRun()

        for tool in PullRequestHostToolCatalog.tools {
            let result = await fixture.service.handle(
                context: fixture.agentContext(),
                call: AgentCLIKit.AgentHostToolCall(
                    name: tool.name,
                    arguments: fixture.minimalArguments(for: tool.name)
                )
            )
            let refusal = PullRequestHostToolServiceError
                .automatedRunCannotClosePullRequest
                .localizedDescription
            if tool.name == PullRequestHostToolCatalog.closeToolName {
                XCTAssertEqual(result.text, refusal, "close_pr let an automated run close")
            } else {
                XCTAssertNotEqual(result.text, refusal, "\(tool.name) should serve an automated run")
            }
        }
    }

    func testEveryToolRefusesAnUnresolvableSourceConversation() async throws {
        let fixture = try PullRequestHostToolFixture()

        for tool in PullRequestHostToolCatalog.tools {
            let result = await fixture.service.handle(
                context: fixture.agentContext(conversationID: "not-a-conversation"),
                call: AgentCLIKit.AgentHostToolCall(
                    name: tool.name,
                    arguments: fixture.minimalArguments(for: tool.name)
                )
            )
            XCTAssertEqual(
                result.text,
                PullRequestHostToolServiceError.sourceConversationUnavailable.localizedDescription,
                "\(tool.name) acted for a conversation Alveary cannot place"
            )
        }
    }

    func testMutatingToolErrorsCarryTheStatusFieldTheirOutputSchemaRequires() async throws {
        let fixture = try PullRequestHostToolFixture()
        fixture.settingsService.update { $0.pullRequestsEnabled = false }

        for tool in PullRequestHostToolCatalog.tools {
            let result = await fixture.service.handle(
                context: fixture.agentContext(),
                call: AgentCLIKit.AgentHostToolCall(name: tool.name, arguments: [:])
            )
            if PullRequestHostToolCatalog.mutatingToolNames.contains(tool.name) {
                let content = try object(result.structuredContent)
                XCTAssertEqual(content["status"], .string("error"), "\(tool.name) error lacked a status")
                XCTAssertNotNil(content["message"])
            } else {
                XCTAssertNil(result.structuredContent, "\(tool.name) is read-only and should not carry status")
            }
        }
    }

    func testUnknownToolNameIsRefused() async throws {
        let fixture = try PullRequestHostToolFixture()

        let result = await fixture.service.handle(
            context: fixture.agentContext(),
            call: AgentCLIKit.AgentHostToolCall(name: "get_pr_secrets")
        )
        XCTAssertEqual(result.text, PullRequestHostToolServiceError.unsupportedTool.localizedDescription)
    }

    // MARK: - Shared assertion helpers

    func object(_ value: AgentCLIKit.JSONValue?) throws -> [String: AgentCLIKit.JSONValue] {
        guard case .object(let object)? = value else {
            throw XCTSkip("expected a JSON object")
        }
        return object
    }

    func array(_ value: AgentCLIKit.JSONValue?) throws -> [AgentCLIKit.JSONValue] {
        guard case .array(let array)? = value else {
            throw XCTSkip("expected a JSON array")
        }
        return array
    }

    /// Text plus encoded structured content, for assertions that nothing leaked into either.
    func encoded(_ result: AgentCLIKit.AgentHostToolResult) throws -> String {
        guard let structuredContent = result.structuredContent else {
            return result.text
        }
        return try result.text + HostToolDeduplication.canonicalJSON(structuredContent)
    }
}

/// In-memory host state plus a stubbed GitHub, with a frozen clock, process token, and
/// proposal id so receipts and proposals are assertable.
@MainActor
final class PullRequestHostToolFixture {
    let modelContext: ModelContext
    let service: PullRequestHostToolService
    let pullRequests: StubPullRequestsService
    let settingsService: InMemorySettingsService
    let notificationCenter: NotificationCenter
    let project: Project
    let thread: AgentThread
    let conversation: Conversation
    let processToken = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE") ?? UUID()
    static let proposalID = "proposal-1"
    static let identifier = PullRequestIdentifier(nameWithOwner: "octo/alpha", number: 7)
    static let url = "https://github.com/octo/alpha/pull/7"

    init(
        now: @escaping () -> Date = { Date(timeIntervalSince1970: 1_000) },
        notificationCenter: NotificationCenter = NotificationCenter()
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

        let sourceProject = Project(path: "/tmp/source-project", name: "Source Project")
        project = sourceProject
        let sourceThread = AgentThread(name: "Source thread", project: sourceProject)
        thread = sourceThread
        let sourceConversation = Conversation(id: "source-conversation", provider: "codex", thread: sourceThread)
        conversation = sourceConversation
        sourceThread.conversations = [sourceConversation]
        sourceProject.threads = [sourceThread]
        context.insert(sourceProject)
        try context.save()

        let stub = StubPullRequestsService()
        pullRequests = stub
        let settings = InMemorySettingsService()
        settingsService = settings
        service = PullRequestHostToolService(
            modelContext: context,
            pullRequestsService: stub,
            settingsService: settings,
            notificationCenter: notificationCenter,
            now: now,
            makeProposalID: { Self.proposalID }
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

    func handle(
        _ toolName: String,
        arguments: [String: AgentCLIKit.JSONValue]? = nil,
        context: AgentCLIKit.AgentHostToolCallContext? = nil
    ) async -> AgentCLIKit.AgentHostToolResult {
        await service.handle(
            context: context ?? agentContext(),
            call: AgentCLIKit.AgentHostToolCall(
                name: toolName,
                arguments: arguments ?? minimalArguments(for: toolName)
            )
        )
    }

    /// Enough arguments for each tool to pass parsing, so a table-driven test reaches the
    /// rule it is actually asserting.
    func minimalArguments(for toolName: String) -> [String: AgentCLIKit.JSONValue] {
        switch toolName {
        case PullRequestHostToolCatalog.listToolName:
            return [:]
        case PullRequestHostToolCatalog.addReviewCommentsToolName:
            return [
                "url": .string(Self.url),
                "comments": .array([Self.reviewComment(body: "Needs a guard here.")])
            ]
        case PullRequestHostToolCatalog.replyToThreadToolName:
            return [
                "url": .string(Self.url),
                "thread_id": .string("THREAD_1"),
                "body": .string("Agreed.")
            ]
        case PullRequestHostToolCatalog.resolveThreadToolName,
             PullRequestHostToolCatalog.unresolveThreadToolName:
            return ["url": .string(Self.url), "thread_id": .string("THREAD_1")]
        case PullRequestHostToolCatalog.commentToolName:
            return ["url": .string(Self.url), "body": .string("Looks good.")]
        case PullRequestHostToolCatalog.proposeReviewToolName:
            return ["url": .string(Self.url), "event": .string("approve")]
        default:
            return ["url": .string(Self.url)]
        }
    }

    /// One `add_pr_review_comments` element. The body is what the stub derives its thread ids
    /// from, so a distinct body is how a test tells one comment's result from another's.
    static func reviewComment(
        path: String = "Sources/Alpha.swift",
        line: Int = 12,
        body: String
    ) -> AgentCLIKit.JSONValue {
        .object([
            "path": .string(path),
            "line": .number(Double(line)),
            "body": .string(body)
        ])
    }

    /// A batch, one comment per body. Anchors follow position — `Sources/Alpha.swift:1`,
    /// `Sources/Beta.swift:2`, and so on — so the bodies stay the assertable part.
    static func reviewCommentArguments(bodies: [String]) -> [String: AgentCLIKit.JSONValue] {
        let names = ["Alpha", "Beta", "Gamma", "Delta", "Epsilon"]
        let comments = bodies.enumerated().map { index, body in
            reviewComment(
                path: "Sources/\(names[index % names.count]).swift",
                line: index + 1,
                body: body
            )
        }
        return ["url": .string(url), "comments": .array(comments)]
    }

    /// An adopted draft that takes the first comment and then refuses, for partial-batch coverage.
    func failReviewCommentAfterTheFirst() throws {
        pullRequests.detailResult = .success(
            makePullRequestDetail(
                id: try XCTUnwrap(Self.identifier),
                pendingReviewNodeID: "EXISTING_DRAFT"
            )
        )
        pullRequests.addPendingCommentResults = [
            .success(
                StubPullRequestsService.makePendingThread(
                    path: "Sources/Alpha.swift",
                    line: 1,
                    side: .right,
                    body: "First"
                )
            ),
            .failure(.transport("offline"))
        ]
    }

    /// Makes the calling thread an automated scheduled run, which only `close_pr` refuses.
    func attachAutomatedScheduledRun() throws {
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
        thread.scheduledTaskRun = run
        try modelContext.save()
    }
}
