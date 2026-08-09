#if DEBUG
import Foundation
import SwiftData
import XCTest

@testable import Alveary

/// Guards the invariants the demo dataset has to hold for the app to render it safely: nothing
/// draft, nothing that engages workspace cleanup, and nothing that leaves the sidebar missing a
/// section a screenshot needs.
@MainActor
final class DemoDataSeederTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!

    override func setUp() async throws {
        try await super.setUp()
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
        try DemoDataSeeder.seed(into: context, attachmentsDirectory: attachmentsDirectory)
    }

    override func tearDown() async throws {
        context = nil
        container = nil
        try? FileManager.default.removeItem(at: attachmentsDirectory)
        try await super.tearDown()
    }

    func testSeedsProjectsAndThreadsWithSidebarSafeState() throws {
        let projects = try context.fetch(FetchDescriptor<Project>())
        XCTAssertEqual(projects.count, 4)
        XCTAssertEqual(projects.filter(\.isPinned).count, 1)

        let threads = try context.fetch(FetchDescriptor<AgentThread>())
        XCTAssertFalse(threads.isEmpty)
        // A seeded draft would be deleted at the next launch's stale-draft sweep, and an
        // incomplete setup would raise the project-trust prompt against a fake path.
        XCTAssertTrue(threads.allSatisfy { !$0.isDraft })
        XCTAssertTrue(threads.allSatisfy(\.hasCompletedInitialSetup))
        // Without an archived thread the sidebar's Archived row is absent, not empty.
        XCTAssertTrue(threads.contains { $0.archivedAt != nil })
        // Both spawned review threads plus the two hand-made Task threads.
        XCTAssertEqual(threads.filter { $0.mode == .task }.count, 4)
    }

    func testSidebarOrderFieldsAreDenseAndPinnedProjectsCarryNoRegularOrder() throws {
        let projects = try context.fetch(FetchDescriptor<Project>())
        let threads = try context.fetch(FetchDescriptor<AgentThread>())

        XCTAssertTrue(projects.filter(\.isPinned).allSatisfy { $0.sidebarSortOrder == nil })
        XCTAssertEqual(
            projects.compactMap(\.sidebarSortOrder).sorted(),
            Array(0..<projects.filter { !$0.isPinned }.count)
        )

        // Pinned projects and pinned Task threads share one dense sequence.
        let pinnedOrders = projects.compactMap(\.pinnedSortOrder) + threads.compactMap(\.pinnedSortOrder)
        XCTAssertEqual(pinnedOrders.sorted(), Array(0..<pinnedOrders.count))
    }

    func testFlagshipConversationHasExactlyOneInFlightToolCall() throws {
        let records = try records(inConversation: DemoData.tripSharingConversation)
        let callIDs = Set(
            records.filter { $0.type == ConversationEventRecord.toolCallType }.compactMap(\.toolId)
        )
        let resultIDs = Set(
            records.filter { $0.type == ConversationEventRecord.toolResultType }.compactMap(\.toolId)
        )
        XCTAssertEqual(callIDs.subtracting(resultIDs).count, 1, "The busy dot needs exactly one unfinished tool row")
        // Ordering sorts on `(conversationId, timestamp)`, so equal stamps would render randomly.
        let timestamps = records.map(\.timestamp).sorted()
        XCTAssertEqual(Set(timestamps).count, timestamps.count)
    }

    func testLiveApprovalsStayActionable() throws {
        let records = try records(inConversation: DemoData.flakyMapTestsConversation)
        let approvals = records.filter { $0.type == ConversationEventRecord.toolApprovalType }
        XCTAssertEqual(approvals.count, 2)
        // `nil` renders the same card disabled; the literal `"pending"` is what enables it.
        XCTAssertTrue(approvals.allSatisfy { $0.toolApprovalStatus == "pending" })
        XCTAssertEqual(Set(approvals.compactMap(\.content)).count, 1, "A batch card needs one shared session id")

        // Any later token row whose reason is neither of these marks the approvals resolved.
        let lastApprovalAt = try XCTUnwrap(approvals.map(\.timestamp).max())
        let laterTokenReasons = records
            .filter { $0.type == ConversationEventRecord.tokensType && $0.timestamp > lastApprovalAt }
            .map { $0.stopReason ?? "" }
        XCTAssertTrue(laterTokenReasons.allSatisfy { $0 == "tool_deferred" || $0 == "usage_update" })

        // An unanswered question anywhere in the conversation would disable both buttons.
        XCTAssertFalse(records.contains { $0.toolName == "AskUserQuestion" })
    }

    func testAttachmentRecordsResolveToFilesThatExist() throws {
        for conversationID in [DemoData.tripSharingConversation, DemoData.emptyStatesConversation] {
            let attachments = try records(inConversation: conversationID)
                .map(\.persistedTranscriptAttachments)
                .filter { !$0.isEmpty }
            XCTAssertFalse(attachments.isEmpty, "\(conversationID) should carry attachments")
            for payload in attachments {
                for url in payload.images.map(\.fileURL)
                    + payload.appShots.map(\.screenshot.fileURL)
                    + payload.files.map(\.fileURL) {
                    XCTAssertTrue(FileManager.default.fileExists(atPath: url.path), "missing \(url.path)")
                }
            }
        }
    }

    func testLinkedPullRequestsDecodeAgainstTheServedFixtures() throws {
        let threads = try context.fetch(FetchDescriptor<AgentThread>())
        let projects = try context.fetch(FetchDescriptor<Project>())
        let linked = threads.flatMap(\.linkedPullRequests) + projects.flatMap(\.linkedPullRequests)
        XCTAssertFalse(linked.isEmpty)
        // The screen and the glyphs must name the same pull requests.
        let served = Set(DemoPullRequestFixtures.summaries.map(\.id))
        XCTAssertTrue(linked.allSatisfy { served.contains($0.id) })
    }

    func testActiveScheduledTasksAreDueInTheFuture() throws {
        let tasks = try context.fetch(FetchDescriptor<ScheduledTask>())
        XCTAssertEqual(tasks.count, 6)
        XCTAssertEqual(tasks.filter { $0.state == .active }.count, 3)
        XCTAssertEqual(tasks.filter { $0.state == .paused }.count, 2)
        for task in tasks where task.state == .active {
            let next = try XCTUnwrap(task.nextOccurrenceAt, task.title)
            XCTAssertGreaterThan(next, Date(), task.title)
        }
        XCTAssertTrue(tasks.contains { $0.prompt == DemoData.reviewFanOutPrompt })
    }

    func testSeededRunsAreInertSoCleanupNeverEngages() throws {
        let runs = try context.fetch(FetchDescriptor<ScheduledTaskRun>())
        XCTAssertEqual(runs.count, 2)
        for run in runs {
            XCTAssertTrue(run.hasKnownTerminalStatus)
            XCTAssertFalse(run.requiresFinalizationRecovery)
            XCTAssertNil(run.preparedWorkspaceRoot)
            XCTAssertNil(run.pendingWorktreeCleanupPath)
            let thread = try XCTUnwrap(run.thread)
            XCTAssertFalse(thread.hasBlockingScheduledTaskRunAttachment)
            XCTAssertFalse(thread.hasPendingScheduledTaskWorktreeCleanup)
        }
    }

    func testSeedingIsIdempotentAgainstAPopulatedStore() throws {
        let threadsBefore = try context.fetchCount(FetchDescriptor<AgentThread>())
        try DemoDataSeeder.seed(into: context, attachmentsDirectory: attachmentsDirectory)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<AgentThread>()), threadsBefore)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Project>()), 4)
    }

    private func records(inConversation conversationID: String) throws -> [ConversationEventRecord] {
        let descriptor = FetchDescriptor<ConversationEventRecord>(
            predicate: #Predicate { $0.conversationId == conversationID },
            sortBy: [SortDescriptor(\.timestamp)]
        )
        return try context.fetch(descriptor)
    }

    private var attachmentsDirectory: URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("DemoDataSeederTests", isDirectory: true)
    }
}
#endif
