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

    /// An open pane cannot see a mutation the agent made, so every tool that changes the pull
    /// request on GitHub has to announce it. Table-driven because the announcement is posted once
    /// centrally — a tool added later inherits it, and this is what proves the wiring.
    func testEverySuccessfulMutationAnnouncesTheChangeExceptTheReviewProposal() async throws {
        for toolName in PullRequestHostToolCatalog.mutatingToolNames.sorted() {
            let fixture = try PullRequestHostToolFixture()
            let identifier = try XCTUnwrap(PullRequestHostToolFixture.identifier)
            fixture.pullRequests.detailResult = .success(
                makePullRequestDetail(id: identifier, reviewThreads: [
                    makeReviewThread(nodeID: "THREAD_1", path: "Sources/Alpha.swift", line: 3, isPending: false)
                ], viewerCanUpdate: true)
            )
            let recorder = fixture.recordAnnouncements()

            let result = await fixture.handle(toolName)

            XCTAssertFalse(result.isError, "\(toolName): \(result.text)")
            guard toolName != PullRequestHostToolCatalog.proposeReviewToolName else {
                // It writes Alveary's own envelope; the pane already re-reads that every render.
                XCTAssertTrue(recorder.announcements.isEmpty, "propose_pr_review announced a GitHub change")
                continue
            }
            XCTAssertEqual(
                recorder.announcements.map(\.identifier),
                [identifier],
                "\(toolName) did not announce its change"
            )
            XCTAssertEqual(
                recorder.announcements.map(\.affectsListRow),
                [PullRequestHostToolCatalog.stateChangeToolNames.contains(toolName)],
                "\(toolName) misreported whether it moves a list row"
            )
        }
    }

    /// A refusal throws before the announcement, so nothing tells the pane to refetch a pull
    /// request that did not move.
    func testAFailedMutationAnnouncesNothing() async throws {
        let fixture = try PullRequestHostToolFixture()
        fixture.pullRequests.addIssueCommentResult = .failure(.rateLimited)
        let recorder = fixture.recordAnnouncements()

        let result = await fixture.handle(PullRequestHostToolCatalog.commentToolName)

        XCTAssertTrue(result.isError)
        XCTAssertTrue(recorder.announcements.isEmpty)
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
    let summaryHandoff: PullRequestSummaryHandoff
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
        let handoff = PullRequestSummaryHandoff(now: now)
        summaryHandoff = handoff
        service = PullRequestHostToolService(
            modelContext: context,
            pullRequestsService: stub,
            settingsService: settings,
            summaryHandoff: handoff,
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

    /// Collects the change announcements this fixture's service posts, so a table-driven test can
    /// assert that a mutation told an open pane to reload.
    func recordAnnouncements() -> PullRequestHostToolAnnouncementRecorder {
        let recorder = PullRequestHostToolAnnouncementRecorder()
        recorder.notificationCenter = notificationCenter
        recorder.token = notificationCenter.addObserver(
            forName: .pullRequestChangedOnGitHub,
            object: nil,
            queue: nil
        ) { notification in
            guard let announcement = notification.userInfo?[
                PullRequestChangeNotificationKey.announcement
            ] as? PullRequestChangeAnnouncement else {
                return
            }
            MainActor.assumeIsolated {
                recorder.announcements.append(announcement)
            }
        }
        return recorder
    }

    /// Enough arguments for each tool to pass parsing, so a table-driven test reaches the
    /// rule it is actually asserting.
    func minimalArguments(for toolName: String) -> [String: AgentCLIKit.JSONValue] {
        switch toolName {
        case PullRequestHostToolCatalog.listToolName:
            return [:]
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

    /// One `propose_pr_review` comment element.
    /// `side` is omitted by default, which the parser reads as RIGHT.
    static func reviewComment(
        path: String = "Sources/Alpha.swift",
        line: Int = 12,
        side: String? = nil,
        body: String
    ) -> AgentCLIKit.JSONValue {
        var fields: [String: AgentCLIKit.JSONValue] = [
            "path": .string(path),
            "line": .number(Double(line)),
            "body": .string(body)
        ]
        if let side {
            fields["side"] = .string(side)
        }
        return .object(fields)
    }

    /// A `propose_pr_review` call staging one comment per body, all anchored to
    /// `Sources/Alpha.swift` so one stubbed diff covers the batch.
    static func reviewProposalArguments(
        event: String = "comment",
        bodies: [String]
    ) -> [String: AgentCLIKit.JSONValue] {
        let comments = bodies.enumerated().map { index, body in
            reviewComment(path: "Sources/Alpha.swift", line: index + 1, body: body)
        }
        return ["url": .string(url), "event": .string(event), "comments": .array(comments)]
    }

    /// A diff whose `Sources/Alpha.swift` carries new-side lines 1 through `lineCount`, matching
    /// `reviewProposalArguments`' anchors.
    func stubAlphaDiff(lineCount: Int = 5) {
        let added = (1...lineCount).map { "+line \($0)" }.joined(separator: "\n")
        pullRequests.diffResult = .success(
            """
            diff --git a/Sources/Alpha.swift b/Sources/Alpha.swift
            --- a/Sources/Alpha.swift
            +++ b/Sources/Alpha.swift
            @@ -1,0 +1,\(lineCount) @@
            \(added)
            """
        )
    }

    /// A diff whose `Sources/Alpha.swift` carries one context line (old and new 1), one deleted
    /// line (old 2), and one added line (new 2) — the shapes the side rules discriminate on.
    func stubAlphaDiffWithContextAndDeletion() {
        pullRequests.diffResult = .success(
            """
            diff --git a/Sources/Alpha.swift b/Sources/Alpha.swift
            --- a/Sources/Alpha.swift
            +++ b/Sources/Alpha.swift
            @@ -1,2 +1,2 @@
             context line
            -old second
            +new second
            """
        )
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

/// Holds the announcements one test observed, and removes its observer when the test lets go of it.
@MainActor
final class PullRequestHostToolAnnouncementRecorder {
    var announcements: [PullRequestChangeAnnouncement] = []
    var token: (any NSObjectProtocol)?
    var notificationCenter: NotificationCenter?

    deinit {
        MainActor.assumeIsolated {
            if let token {
                notificationCenter?.removeObserver(token)
            }
        }
    }
}
