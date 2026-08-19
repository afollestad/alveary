import Foundation
import XCTest

@testable import Alveary

/// Where a spawned thread lands in the sidebar. Each route reads its own `AppSettings` id — the
/// one thing besides name, prompt, and checkout that the two kinds do not share — and every
/// unusable id degrades to `Tasks`, because `insertTaskThread` throws on a missing section and a
/// footer button has nowhere to explain a refusal.
@MainActor
extension PullRequestAgenticThreadServiceTests {
    private func createCustomSection(named name: String, in fixture: SidebarTestFixture) throws -> String {
        guard case .created(let descriptor) = try fixture.viewModel.createSection(name: name),
              case .custom(let id) = descriptor.id else {
            throw SidebarSectionServiceError.sectionMissing
        }
        return id
    }

    private func startedThread(_ start: StartFixture, conversationID: String) -> AgentThread? {
        start.fixture.context.resolveConversation(conversationID: conversationID)?.thread
    }

    func testEachRouteLandsInItsOwnChosenSection() async throws {
        let start = try makeStartFixture()
        let reviewSection = try createCustomSection(named: "Reviews", in: start.fixture)
        let feedbackSection = try createCustomSection(named: "Fixes", in: start.fixture)
        start.fixture.settingsService.update { settings in
            settings.pullRequestReviewSectionID = reviewSection
            settings.pullRequestAddressFeedbackSectionID = feedbackSection
        }

        let review = try await start.service.start(kind: .review, identifier: start.identifier, url: start.url)
        let feedback = try await start.service.start(
            kind: .addressFeedback,
            identifier: start.identifier,
            url: start.url
        )
        try await review.dispatch.value
        try await feedback.dispatch.value

        XCTAssertEqual(startedThread(start, conversationID: review.conversationID)?.customSection?.id, reviewSection)
        XCTAssertEqual(startedThread(start, conversationID: feedback.conversationID)?.customSection?.id, feedbackSection)
    }

    /// The placement must stay visible: a section renders only for a projectless task-mode thread,
    /// and the address-feedback checkout ladder carries its checkout in the workspace descriptor
    /// rather than on `project` precisely so this holds.
    func testASectionedThreadStaysProjectlessSoTheSectionRenders() async throws {
        let start = try makeStartFixture()
        let section = try createCustomSection(named: "Reviews", in: start.fixture)
        start.fixture.settingsService.update { $0.pullRequestReviewSectionID = section }

        let started = try await start.service.start(kind: .review, identifier: start.identifier, url: start.url)
        try await started.dispatch.value

        let thread = startedThread(start, conversationID: started.conversationID)
        XCTAssertNil(thread?.project)
        XCTAssertEqual(thread?.effectiveMode, .task)
    }

    func testAnUnpinnedRouteLandsInTasks() async throws {
        let start = try makeStartFixture()
        _ = try createCustomSection(named: "Reviews", in: start.fixture)

        let started = try await start.service.start(kind: .review, identifier: start.identifier, url: start.url)
        try await started.dispatch.value

        XCTAssertNil(startedThread(start, conversationID: started.conversationID)?.customSection)
    }

    /// The regression this pins: `AppSettings` stores a bare id with no relationship nullifying
    /// it, so a removed section is ordinary. Letting the seed carry it would throw
    /// `sectionMissing` and fail the whole start.
    func testARemovedSectionStartsTheThreadInTasksRatherThanFailing() async throws {
        let start = try makeStartFixture()
        start.fixture.settingsService.update { $0.pullRequestReviewSectionID = "section-that-never-existed" }

        let started = try await start.service.start(kind: .review, identifier: start.identifier, url: start.url)
        try await started.dispatch.value

        XCTAssertFalse(started.conversationID.isEmpty)
        XCTAssertNil(startedThread(start, conversationID: started.conversationID)?.customSection)
    }

    /// A builtin row's id is reachable through the same store, and pinning or a Project placement
    /// is what puts a thread in `Pinned` or `Projects` — never this setting.
    func testABuiltinSectionIDDegradesToTasks() async throws {
        let start = try makeStartFixture()
        // Builtin rows are seeded, not present by default; normalization is what mints them.
        try SidebarSectionNormalization.normalize(in: start.fixture.context)
        try start.fixture.context.save()
        let sections = try SidebarSectionNormalization.allSections(in: start.fixture.context)
        let pinnedID = try XCTUnwrap(sections.first { $0.kind == .pinned }?.id)
        start.fixture.settingsService.update { $0.pullRequestAddressFeedbackSectionID = pinnedID }

        let started = try await start.service.start(
            kind: .addressFeedback,
            identifier: start.identifier,
            url: start.url
        )
        try await started.dispatch.value

        XCTAssertNil(startedThread(start, conversationID: started.conversationID)?.customSection)
    }
}
