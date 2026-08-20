import Foundation
import SwiftData
import XCTest

@testable import Alveary

/// A conversation holding one pending review proposal, plus the coordinator that owns it.
/// `secondProposal` adds a second thread with its own, for the paths that survey all of them.
@MainActor
final class ReviewProposalFixture {
    static let proposalID = "proposal-1"
    static let identifier = PullRequestIdentifier(owner: "octo", repo: "alpha", number: 7)
    /// A second thread's pending proposal, for the paths that survey every proposal at once
    /// rather than one card's. Its own pull request, because propose time supersedes a second
    /// proposal against one already spoken for.
    static let secondProposalID = "proposal-2"
    static let secondIdentifier = PullRequestIdentifier(owner: "octo", repo: "alpha", number: 8)

    let modelContext: ModelContext
    let coordinator: PullRequestReviewProposalCoordinator
    let service = StubPullRequestsService()
    let conversation: Conversation
    let notificationCenter = NotificationCenter()
    /// A cache file per fixture, so tests cannot read each other's entries.
    let previewCacheURL: URL

    init(
        body: String? = "Looks good to me.",
        comments: [PullRequestReviewProposalRecord.Comment]? = nil,
        cachedEntry: PullRequestReviewProposalPreviewCache.Entry? = nil,
        corruptCache: Bool = false,
        remoteReloadDelay: Duration = .zero,
        secondProposal: Bool = false
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
        let thread = AgentThread(name: "Thread")
        let sourceConversation = Conversation(id: "source-conversation", provider: "codex", thread: thread)
        conversation = sourceConversation
        thread.conversations = [sourceConversation]
        context.insert(thread)
        try sourceConversation.storePullRequestReviewProposal(
            Self.record(
                id: Self.proposalID,
                identifier: Self.identifier,
                body: body,
                comments: comments,
                createdAt: Date(timeIntervalSince1970: 1_000)
            )
        )
        if secondProposal {
            try Self.insertSecondProposal(in: context, body: body, comments: comments)
        }
        try context.save()

        previewCacheURL = try Self.makeCacheFile(cachedEntry: cachedEntry, corrupt: corruptCache)

        coordinator = PullRequestReviewProposalCoordinator(
            modelContext: context,
            pullRequestsService: service,
            previewCache: PullRequestReviewProposalPreviewCache(fileURL: previewCacheURL),
            notificationCenter: notificationCenter,
            // Zero by default: a test that posts one announcement has nothing to coalesce and
            // should not wait. Only the burst test needs a window wide enough to span its posts.
            remoteReloadDelay: remoteReloadDelay,
            now: { Date(timeIntervalSince1970: 2_000) }
        )
    }

    deinit {
        try? FileManager.default.removeItem(at: previewCacheURL)
    }

    /// A second thread with its own pending proposal, so a survey of every proposal has more than
    /// one to find.
    private static func insertSecondProposal(
        in context: ModelContext,
        body: String?,
        comments: [PullRequestReviewProposalRecord.Comment]?
    ) throws {
        let thread = AgentThread(name: "Other Thread")
        let conversation = Conversation(id: "other-conversation", provider: "codex", thread: thread)
        thread.conversations = [conversation]
        context.insert(thread)
        try conversation.storePullRequestReviewProposal(
            record(
                id: secondProposalID,
                identifier: secondIdentifier,
                body: body,
                comments: comments,
                // Older, so `warmPreviews` reaches it second and the order under test is fixed.
                createdAt: Date(timeIntervalSince1970: 900)
            )
        )
    }

    private static func record(
        id: String,
        identifier: PullRequestIdentifier,
        body: String?,
        comments: [PullRequestReviewProposalRecord.Comment]?,
        createdAt: Date
    ) -> PullRequestReviewProposalRecord {
        PullRequestReviewProposalRecord(
            payloadVersion: PullRequestReviewProposalRecord.currentPayloadVersion,
            id: id,
            deduplicationKey: "dedup-\(id)",
            repositoryNameWithOwner: identifier.nameWithOwner,
            number: identifier.number,
            event: "approve",
            body: body,
            comments: comments,
            titleSnapshot: "Detail title",
            pendingCommentCountSnapshot: 1,
            sourceProviderID: "codex",
            sourceProcessToken: "token",
            sourceRequestID: "request-\(id)",
            createdAt: createdAt
        )
    }

    private static func makeCacheFile(
        cachedEntry: PullRequestReviewProposalPreviewCache.Entry?,
        corrupt: Bool
    ) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ReviewProposalPreviewCacheTests", isDirectory: true)
            .appendingPathComponent("\(UUID().uuidString).json")
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if corrupt {
            try Data("not json".utf8).write(to: url)
        } else if let cachedEntry {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            try encoder.encode([Self.proposalID: cachedEntry]).write(to: url)
        }
        return url
    }

    /// The entry propose time would seed for `comments`, narrowed from the same diff the service
    /// stub returns so a cached paint and a refresh describe the same hunks.
    static func seededEntry(
        for comments: [PullRequestReviewProposalRecord.Comment],
        identifier: PullRequestIdentifier = ReviewProposalFixture.identifier,
        fileCount: Int = 2,
        viewerLogin: String? = "octocat"
    ) -> PullRequestReviewProposalPreviewCache.Entry {
        PullRequestReviewProposalPreviewCache.Entry(
            identifier: identifier,
            files: ReviewProposalDiffNarrowing.narrowed(
                files: DiffParser.parse(makeUnifiedDiffFixture(fileCount: fileCount)),
                linesByPath: ReviewProposalDiffNarrowing.linesByPath(for: comments)
            ),
            hiddenFileCount: 0,
            viewerLogin: viewerLogin,
            viewerAvatarURL: nil,
            viewerIsAuthor: false,
            fetchedAt: Date(timeIntervalSince1970: 1_500)
        )
    }

    func cachedEntries() -> [String: PullRequestReviewProposalPreviewCache.Entry] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let data = try? Data(contentsOf: previewCacheURL),
              let entries = try? decoder.decode(
                  [String: PullRequestReviewProposalPreviewCache.Entry].self,
                  from: data
              ) else {
            return [:]
        }
        return entries
    }

    /// Posts the announcement an `alveary_host` mutation makes, which drops the hunks a painted
    /// card drew.
    func announceRemoteChange(identifier: PullRequestIdentifier = ReviewProposalFixture.identifier) {
        notificationCenter.post(
            name: .pullRequestChangedOnGitHub,
            object: nil,
            userInfo: [
                PullRequestChangeNotificationKey.announcement: PullRequestChangeAnnouncement(
                    identifier: identifier,
                    affectsListRow: false
                )
            ]
        )
    }

    /// Awaits work the coordinator starts on its own, with no caller to await — the warm refresh
    /// chained behind the cached paint, and the reload an invalidation kicks off.
    func wait(
        until condition: @MainActor () -> Bool,
        _ message: String,
        timeout: TimeInterval = 2
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() {
                return
            }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        XCTFail(message)
    }

    /// The cached paint lands in its own task at init; poll rather than guessing at a sleep.
    func waitForCachedPaint(timeout: TimeInterval = 2) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if case .loaded? = coordinator.preview(forProposalID: Self.proposalID) {
                return
            }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        XCTFail("the cached preview never painted")
    }

    /// Polls the cache file, which a successful refresh writes from its own detached task.
    func waitForCachedEntry(timeout: TimeInterval = 2) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if cachedEntries()[Self.proposalID] != nil {
                return
            }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        XCTFail("the refresh never wrote a cache entry")
    }

    /// A refresh that changes nothing visible still ends in a card-state post, which is the only
    /// signal a test has that it finished. Arm this *before* triggering the refresh.
    func cardStateRecorder() -> ReviewProposalCardStateRecorder {
        ReviewProposalCardStateRecorder(notificationCenter: notificationCenter)
    }

    func wait(
        for recorder: ReviewProposalCardStateRecorder,
        count: Int = 1,
        timeout: TimeInterval = 2
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if recorder.count >= count {
                return
            }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        XCTFail("the card state changed \(recorder.count) times, expected \(count)")
    }

    /// Collects the change announcements this fixture's coordinator posts. `onEach` runs inside
    /// the post, which is how a test can observe state as it stood at that moment.
    func recordAnnouncements(onEach: (@MainActor () -> Void)? = nil) -> ReviewProposalAnnouncementRecorder {
        let recorder = ReviewProposalAnnouncementRecorder()
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
                onEach?()
            }
        }
        recorder.notificationCenter = notificationCenter
        return recorder
    }

    static func stagedComment(
        path: String = "File0.swift",
        line: Int = 1,
        body: String
    ) -> PullRequestReviewProposalRecord.Comment {
        PullRequestReviewProposalRecord.Comment(path: path, line: line, side: "RIGHT", body: body)
    }

    func outcomeMarkers() -> [ConversationEventRecord] {
        conversation.events.filter { $0.type == ConversationEventRecord.hostToolOutcomeType }
    }

    /// `confirm` enters the submitting state before its first suspension, but the caller runs it in
    /// its own `Task`; poll with a deadline so a coordinator that never enters it fails the test
    /// rather than spinning the main actor until CI times out.
    func waitForSubmission(timeout: TimeInterval = 2) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if coordinator.isSubmitting(proposalID: Self.proposalID) {
                return
            }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        XCTFail("the submission never started")
    }

    /// The preview loads in its own task; poll rather than guessing at a sleep.
    func waitForPreview(timeout: TimeInterval = 2) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            switch coordinator.preview(forProposalID: Self.proposalID) {
            case .loaded, .failed:
                return
            case .loading, nil:
                try await Task.sleep(nanoseconds: 5_000_000)
            }
        }
        XCTFail("the preview never settled")
    }
}

/// Counts the card-state posts every preview transition ends with, so a test can await a refresh
/// that changed nothing on screen.
@MainActor
final class ReviewProposalCardStateRecorder {
    private(set) var count = 0
    private var token: (any NSObjectProtocol)?
    private let notificationCenter: NotificationCenter

    init(notificationCenter: NotificationCenter) {
        self.notificationCenter = notificationCenter
        token = notificationCenter.addObserver(
            forName: .reviewProposalCardStateChanged,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.count += 1
            }
        }
    }

    deinit {
        MainActor.assumeIsolated {
            if let token {
                notificationCenter.removeObserver(token)
            }
        }
    }
}

/// Holds the announcements one test observed, and removes its observer when the test lets go of it.
@MainActor
final class ReviewProposalAnnouncementRecorder {
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
